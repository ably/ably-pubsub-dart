import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Creates a mock HTTP client that returns 'yes' for connectivity checks.
http.Client createMockHttpClient() {
  return http_testing.MockClient((request) async {
    // Return successful connectivity check response
    return http.Response('yes', 200);
  });
}

/// Unit tests for connection failures when connected (RTN15).
///
/// These tests use mocked WebSocket to verify connection behavior
/// when failures occur after the connection is established.
///
/// Spec: uts/test/realtime/unit/connection/connection_failures_test.md
void main() {
  group('RTN15h1 - DISCONNECTED with token error, no renewal', () {
    // UTS: realtime/unit/RTN15h1/token-error-no-renew-0
    test('transitions to FAILED when token cannot be renewed', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      // Use token directly (no way to renew)
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          token: 'some_token_string',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Server sends DISCONNECTED with token error and closes connection
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(
            code: 40142,
            statusCode: 401,
            message: 'Token expired',
          ),
        ),
      );

      // Should transition to FAILED (no means to renew)
      await _awaitState(client.connection, ConnectionState.failed);

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason, isNotNull);
      // RSA4a2: non-renewable token error wraps with 40171
      expect(client.connection.errorReason!.code, equals(40171));

      mockWs.dispose();
    });
  });

  group('RTN15h2 - DISCONNECTED with token error, renewable', () {
    // UTS: realtime/unit/RTN15h2/token-error-renew-success-0
    test('renews token and resumes connection', () async {
      var connectionAttemptCount = 0;
      var tokenRenewalCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // First connection succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-1',
                connectionKey: 'key-1',
              ),
            );
          } else {
            // Resume after token renewal succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-1', // Same ID = resumed
                connectionKey: 'key-1-renewed',
              ),
            );
          }
        },
      );

      // Use authCallback for token renewal
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            tokenRenewalCount++;
            // Return a new token
            return TokenDetails(
              token: 'renewed_token_$tokenRenewalCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final firstConnectionId = client.connection.id;

      // Server sends DISCONNECTED with token error
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(
            code: 40142,
            statusCode: 401,
            message: 'Token expired',
          ),
        ),
      );

      // Should transition to CONNECTING (to renew and resume)
      await _awaitState(client.connection, ConnectionState.connecting);

      // Should reconnect with renewed token
      await _awaitState(
        client.connection,
        ConnectionState.connected,
      );

      expect(client.connection.state, equals(ConnectionState.connected));
      expect(client.connection.id, equals(firstConnectionId)); // Resumed
      expect(tokenRenewalCount, greaterThan(0)); // Token was renewed

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN15h2/token-error-renew-fails-1
    test('transitions to DISCONNECTED if renewal fails', () async {
      var authCallbackCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
      );

      // Use authCallback that succeeds first time, then fails
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            if (authCallbackCount == 1) {
              // First call succeeds (initial connection)
              return TokenDetails(
                token: 'initial_token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            }
            // Subsequent calls fail (renewal)
            throw const AblyException(
              message: 'Token renewal failed',
              errorInfo: ErrorInfo(
                code: 40140,
                statusCode: 401,
                message: 'Token renewal failed',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Server sends DISCONNECTED with token error
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(
            code: 40142,
            statusCode: 401,
            message: 'Token expired',
          ),
        ),
      );

      // Renewal fails, should go to DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);

      expect(client.connection.state, equals(ConnectionState.disconnected));
      expect(client.connection.errorReason, isNotNull);

      mockWs.dispose();
    });
  });

  group('RTN15h3 - DISCONNECTED with non-token error', () {
    // UTS: realtime/unit/RTN15h3/non-token-error-resume-0
    test('immediately resumes connection', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final capturedUrls = <Uri>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            capturedUrls.add(conn.url);

            if (connectionAttemptCount == 1) {
              // First connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1', // Same ID = resumed
                  connectionKey: 'key-1',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        final originalConnectionId = client.connection.id;

        // Server sends DISCONNECTED with non-token error
        mockWs.activeConnection!.sendToClientAndClose(
          ProtocolMessageHelpers.disconnected(
            error: const ErrorInfo(
              code: 80003,
              statusCode: 503,
              message: 'Service unavailable',
            ),
          ),
        );

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals(originalConnectionId));
        expect(connectionAttemptCount, equals(2));

        // Second connection should include resume parameter
        expect(capturedUrls[1].queryParameters['resume'], equals('key-1'));

        mockWs.dispose();
      });
    });
  });

  group('RTN15j - ERROR with empty channel when CONNECTED', () {
    // UTS: realtime/unit/RTN15j/error-empty-channel-failed-0
    test('transitions to FAILED on connection-level ERROR', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Server sends ERROR with empty channel (connection-level error)
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 50000,
          statusCode: 500,
          message: 'Internal error',
        ),
      );

      await _awaitState(client.connection, ConnectionState.failed);

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(50000));

      mockWs.dispose();
    });
  });

  group('RTN15a - Unexpected transport disconnect', () {
    // UTS: realtime/unit/RTN15a/unexpected-transport-disconnect-0
    test('triggers resume attempt', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        final originalConnectionId = client.connection.id;

        // Simulate unexpected disconnect (no protocol message)
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals(originalConnectionId)); // Resumed
        expect(connectionAttemptCount, equals(2));

        mockWs.dispose();
      });
    });
  });

  group('RTN15b, RTN15c6 - Successful resume', () {
    // UTS: realtime/unit/RTN15b/successful-resume-0
    test('resumes with same connectionId', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final capturedUrls = <Uri>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            capturedUrls.add(conn.url);

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume succeeds (same connectionId)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1-updated',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        expect(client.connection.id, equals('connection-1'));

        // Force disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Connection resumed (same ID)
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals('connection-1'));

        // Connection key was updated (RTN15e)
        expect(client.connection.key, equals('key-1-updated'));

        // Second connection included resume parameter (RTN15b1)
        expect(capturedUrls[1].queryParameters['resume'], equals('key-1'));
        expect(connectionAttemptCount, equals(2));

        mockWs.dispose();
      });
    });
  });

  group('RTN15c7 - Failed resume', () {
    // UTS: realtime/unit/RTN15c7/failed-resume-new-id-0
    test('handles new connectionId indicating failed resume', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume failed (new connectionId + error)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-2', // Different ID
                  connectionKey: 'key-2',
                  error: const ErrorInfo(
                    code: 80008,
                    statusCode: 400,
                    message: 'Unable to recover connection',
                  ),
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        final originalConnectionId = client.connection.id;

        // Force disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // New connection (different ID)
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals('connection-2'));
        expect(client.connection.id, isNot(equals(originalConnectionId)));

        // Connection key updated
        expect(client.connection.key, equals('key-2'));

        mockWs.dispose();
      });
    });
  });

  group('RTN15g - Connection state cleared after connectionStateTtl', () {
    // UTS: realtime/unit/RTN15g/state-cleared-after-ttl-0
    test('makes fresh connection after TTL expires', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final capturedUrls = <Uri>[];
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            capturedUrls.add(conn.url);

            if (connectionAttemptCount == 1) {
              // First connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                  connectionStateTtl: 5000, // 5 seconds TTL
                ),
              );
            } else if (connectionAttemptCount < 6) {
              // Reconnection attempts 2-5 fail (connection refused)
              // This keeps the client in DISCONNECTED state, allowing TTL to expire
              conn.respondWithRefused();
            } else {
              // After TTL expires, fresh connection succeeds (no resume)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-2',
                  connectionKey: 'key-2',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: 1000,
            suspendedRetryTimeout: 2000, // Short timeout for testing
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          httpClient: createMockHttpClient(), // Mock connectivity checker
          timerManager: fakeTimers,
        );

        // Record all state changes
        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        final originalConnectionId = client.connection.id;
        final originalConnectionKey = client.connection.key;

        // Force disconnect - this triggers immediate reconnect (RTN15a)
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Reconnection attempts will keep failing (connection refused)
        // Advance time to trigger retries and eventually pass TTL
        // TTL is 5000ms, disconnectedRetryTimeout is 1000ms, suspendedRetryTimeout is 2000ms
        // We need enough iterations to:
        // 1. Exhaust TTL (5000ms) while in disconnected
        // 2. Transition to suspended
        // 3. Retry from suspended until attempt 6 succeeds
        for (var i = 0; i < 15; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 2500));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.connected) {
            break;
          }
        }

        // Wait for final successful reconnection
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify the state change sequence includes SUSPENDED
        expect(
          stateChanges,
          containsAllInOrder([
            ConnectionState.connecting,
            ConnectionState.connected,
            ConnectionState.disconnected,
            ConnectionState.suspended,
            ConnectionState.connecting,
            ConnectionState.connected,
          ]),
        );

        // RTN15g: New connection (different ID, not resumed - TTL expired)
        expect(client.connection.id, equals('connection-2'));
        expect(client.connection.id, isNot(equals(originalConnectionId)));
        expect(client.connection.key, equals('key-2'));
        expect(client.connection.key, isNot(equals(originalConnectionKey)));

        // Verify the final reconnection URL did NOT have resume parameter
        // (because TTL expired and connection state was cleared)
        final reconnectUrl = capturedUrls.last;
        expect(reconnectUrl.queryParameters.containsKey('resume'), isFalse);

        mockWs.dispose();
      });
    });
  });

  group('RTN15c5 - ERROR with token error during resume', () {
    // UTS: realtime/unit/RTN15c5/token-error-during-resume-0
    test('renews token and retries', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        var tokenRenewalCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else if (connectionAttemptCount == 2) {
              // Resume attempt fails with token error
              conn.respondWithError(
                ProtocolMessageHelpers.error(
                  code: 40142,
                  message: 'Token expired',
                  statusCode: 401,
                ),
              );
            } else {
              // Retry with renewed token succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-2',
                  connectionKey: 'key-2',
                ),
              );
            }
          },
        );

        // Use authCallback for token renewal
        final client = PubSubClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              tokenRenewalCount++;
              return TokenDetails(
                token: 'token_$tokenRenewalCount',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            },
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Force disconnect (will trigger resume attempt with token error)
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Token error on attempt 2 triggers renewal and immediate retry
        // May need another timer elapse for the second retry
        if (client.connection.state != ConnectionState.connected) {
          fakeTimers.elapseTime(const Duration(milliseconds: 1100));
          await _pumpEventQueue();
        }

        expect(client.connection.state, equals(ConnectionState.connected));
        expect(connectionAttemptCount, equals(3));
        expect(tokenRenewalCount, greaterThan(1)); // Initial + renewal

        mockWs.dispose();
      });
    });
  });

  group('RTN15e - Connection key updated after successful resume', () {
    // UTS: realtime/unit/RTN15e/connection-key-updated-0
    test('connection key is updated from CONNECTED message after resume',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume succeeds with new key (same connectionId = resumed)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-2',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify initial key
        expect(client.connection.key, equals('key-1'));

        // Disconnect to trigger resume
        mockWs.activeConnection!.simulateDisconnect();
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Connection resumed (same ID)
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals('connection-1'));

        // RTN15e: Connection key updated to key-2 from the new CONNECTED msg
        expect(client.connection.key, equals('key-2'));

        mockWs.dispose();
      });
    });
  });

  group('RTN15c4 - ERROR with fatal error during resume', () {
    // UTS: realtime/unit/RTN15c4/fatal-error-during-resume-0
    test('transitions to FAILED on fatal error', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // Resume attempt fails with fatal error
              conn.respondWithError(
                ProtocolMessageHelpers.error(
                  code: 50000,
                  message: 'Internal server error',
                  statusCode: 500,
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Force disconnect (will trigger resume with fatal error)
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        expect(client.connection.state, equals(ConnectionState.failed));
        expect(client.connection.errorReason, isNotNull);
        expect(client.connection.errorReason!.code, equals(50000));

        // Only two connection attempts (no retry after fatal error)
        expect(connectionAttemptCount, equals(2));

        mockWs.dispose();
      });
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) {
    return;
  }

  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

/// Pumps the event queue to allow async operations to complete.
/// Used after advancing fake time to let scheduled callbacks run.
Future<void> _pumpEventQueue() async {
  for (var i = 0; i < 1; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

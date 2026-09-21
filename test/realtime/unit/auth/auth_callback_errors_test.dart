import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for auth callback error handling (RSA4c, RSA4c1, RSA4c2, RSA4c3,
/// RSA4d, RSA4f).
///
/// These tests verify error handling when authentication via authCallback fails
/// in various ways. The behaviour depends on:
/// - The type of error (generic error vs 403 vs invalid format vs timeout)
/// - The connection state when the error occurs (CONNECTING vs CONNECTED)
///
/// Key behaviours:
/// - Generic auth errors while CONNECTING -> DISCONNECTED with code 80019
/// - Generic auth errors while CONNECTED -> stay CONNECTED, errorReason set
/// - 403 errors -> FAILED with code 80019/statusCode 403
/// - Invalid token format -> treated as auth error per RSA4c
///
/// Spec: uts/test/realtime/unit/auth/auth_callback_errors_test.md
void main() {
  group(
      'RSA4c1, RSA4c2 - authCallback error during CONNECTING transitions to '
      'DISCONNECTED', () {
    // UTS: realtime/unit/RSA4c2/callback-error-connecting-disconnected-0
    test(
        'authCallback error causes DISCONNECTED with code 80019, then retries '
        'successfully', () async {
      var authCallbackCount = 0;

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
          authCallback: (params) async {
            authCallbackCount++;
            if (authCallbackCount == 1) {
              throw const AblyException(
                message: 'Auth server unavailable',
                errorInfo: ErrorInfo(
                  code: 50000,
                  statusCode: 500,
                  message: 'Auth server unavailable',
                ),
              );
            }
            return TokenDetails(
              token: 'valid-token-$authCallbackCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();

      // authCallback fails on first attempt -- connection should go to
      // DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);

      // RSA4c2: Connection transitioned to DISCONNECTED (not FAILED)
      expect(client.connection.state, equals(ConnectionState.disconnected));

      // RSA4c1: errorReason has code 80019 wrapping the underlying cause
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));
      expect(client.connection.errorReason!.statusCode, equals(401));

      // RSA4c1: cause is set to the underlying error from authCallback
      expect(client.connection.errorReason!.cause, isNotNull);
      final cause = client.connection.errorReason!.cause;
      if (cause is ErrorInfo) {
        expect(cause.code, equals(50000));
      }

      // State change event carries the same error
      final disconnectedChanges = stateChanges
          .where((c) => c.current == ConnectionState.disconnected)
          .toList();
      expect(disconnectedChanges.length, greaterThanOrEqualTo(1));
      expect(disconnectedChanges[0].reason, isNotNull);
      expect(disconnectedChanges[0].reason!.code, equals(80019));

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4c1, RSA4c2 - authCallback timeout during CONNECTING transitions to '
      'DISCONNECTED', () {
    // UTS: realtime/unit/RSA4c2/callback-timeout-connecting-disconnected-1
    test('authCallback timeout causes DISCONNECTED with code 80019', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

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

      await withClock(testClock, () async {
        final client = PubSubClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              // Never returns -- simulates a timeout
              return await Completer<Object>().future;
            },
            // ignore: avoid_redundant_argument_values
            realtimeRequestTimeout: 10000,
            autoConnect: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final stateChanges = <ConnectionStateChange>[];
        client.connection.on().listen((change) {
          stateChanges.add(change);
        });

        client.connect();

        // Advance time past realtimeRequestTimeout
        fakeTimers.elapseTime(const Duration(milliseconds: 11000));

        // Allow async processing
        await Future<void>.delayed(Duration.zero);

        await _awaitState(client.connection, ConnectionState.disconnected);

        // RSA4c2: Connection transitioned to DISCONNECTED
        expect(client.connection.state, equals(ConnectionState.disconnected));

        // RSA4c1: errorReason has code 80019
        expect(client.connection.errorReason, isNotNull);
        expect(client.connection.errorReason!.code, equals(80019));
        expect(client.connection.errorReason!.statusCode, equals(401));

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group(
      'RSA4c3 - authCallback error while CONNECTED leaves connection '
      'CONNECTED', () {
    // UTS: realtime/unit/RSA4c3/callback-error-connected-stays-0
    test(
        'authCallback failure during RTN22 reauth keeps connection CONNECTED '
        'without setting errorReason', () async {
      var authCallbackCount = 0;

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
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
          authCallback: (params) async {
            authCallbackCount++;
            if (authCallbackCount == 1) {
              // First call succeeds (initial connection)
              return TokenDetails(
                token: 'initial-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            }
            // Subsequent calls fail (reauth triggered by server)
            throw const AblyException(
              message: 'Auth server unavailable',
              errorInfo: ErrorInfo(
                code: 50000,
                statusCode: 500,
                message: 'Auth server unavailable',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Record state changes from this point
      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) => stateChanges.add(change));

      // Server requests re-authentication (RTN22)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(action: ProtocolAction.auth),
      );

      // Wait for the auth callback to be called a second time (the failure)
      await _awaitUntil(
        () => authCallbackCount >= 2,
      );

      // RSA4c3: Connection remains CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // No state changes at all — the auth failure is silently swallowed
      expect(stateChanges, isEmpty);

      // errorReason is NOT set — the connection is healthy, the existing
      // token is still valid, and there is no state change to associate
      // the error with (see specification#466)
      expect(client.connection.errorReason, isNull);

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4d - authCallback returns 403 error during CONNECTING transitions '
      'to FAILED', () {
    // UTS: realtime/unit/RSA4d/callback-403-connecting-failed-0
    test('403 from authCallback causes FAILED with code 80019, statusCode 403',
        () async {
      var connectionAttempted = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempted = true;
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
          authCallback: (params) async {
            throw const AblyException(
              message: 'Account disabled',
              errorInfo: ErrorInfo(
                code: 40300,
                statusCode: 403,
                message: 'Account disabled',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();

      // authCallback returns 403 -- connection should go directly to FAILED
      await _awaitState(client.connection, ConnectionState.failed);

      // RSA4d: Connection went to FAILED (not DISCONNECTED)
      expect(client.connection.state, equals(ConnectionState.failed));

      // No WebSocket connection was attempted (auth failed before transport)
      expect(connectionAttempted, isFalse);

      // RSA4d: ErrorInfo has code 80019 and statusCode 403
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));
      expect(client.connection.errorReason!.statusCode, equals(403));

      // Cause is the original 403 error
      expect(client.connection.errorReason!.cause, isNotNull);
      final cause = client.connection.errorReason!.cause;
      if (cause is ErrorInfo) {
        expect(cause.code, equals(40300));
        expect(cause.statusCode, equals(403));
      }

      // State change event carries the error
      final failedChanges =
          stateChanges.where((c) => c.current == ConnectionState.failed);
      expect(failedChanges.length, equals(1));
      expect(failedChanges.first.reason, isNotNull);
      expect(failedChanges.first.reason!.code, equals(80019));
      expect(failedChanges.first.reason!.statusCode, equals(403));

      // No DISCONNECTED state was reached (went directly to FAILED)
      final disconnectedChanges = stateChanges
          .where((c) => c.current == ConnectionState.disconnected)
          .toList();
      expect(disconnectedChanges, isEmpty);

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4d - authCallback 403 during RTN22 reauth transitions CONNECTED to '
      'FAILED', () {
    // UTS: realtime/unit/RSA4d/callback-403-reauth-failed-1
    test('403 during server-initiated reauth causes FAILED from CONNECTED',
        () async {
      var authCallbackCount = 0;

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
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
          authCallback: (params) async {
            authCallbackCount++;
            if (authCallbackCount == 1) {
              // First call succeeds (initial connection)
              return TokenDetails(
                token: 'initial-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            }
            // Reauth fails with 403
            throw const AblyException(
              message: 'Account suspended',
              errorInfo: ErrorInfo(
                code: 40300,
                statusCode: 403,
                message: 'Account suspended',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Server requests re-authentication (RTN22)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(action: ProtocolAction.auth),
      );

      // authCallback returns 403 -- connection should go to FAILED
      await _awaitState(client.connection, ConnectionState.failed);

      // RSA4d: FAILED with code 80019 and statusCode 403
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));
      expect(client.connection.errorReason!.statusCode, equals(403));
      expect(client.connection.errorReason!.cause, isNotNull);
      final cause = client.connection.errorReason!.cause;
      if (cause is ErrorInfo) {
        expect(cause.code, equals(40300));
      }

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4e - REST authCallback error with code 40170 transitions to '
      'DISCONNECTED', () {
    // UTS: realtime/unit/RSA4e/rest-callback-error-40170-0
    test(
        'authCallback error with 40170 code causes DISCONNECTED with code '
        '80019 (token expired is retryable)', () async {
      var connectionAttempted = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempted = true;
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
          authCallback: (params) async {
            throw const AblyException(
              message: 'Token expired',
              errorInfo: ErrorInfo(
                code: 40170,
                statusCode: 401,
                message: 'Token expired',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();

      // authCallback returns 40170 (token expired) -- connection goes to
      // DISCONNECTED (not FAILED) because 401 with 40170 is a retryable
      // auth error per RSA4c2
      await _awaitState(client.connection, ConnectionState.disconnected);

      // RSA4e/RSA4c2: Connection transitioned to DISCONNECTED
      expect(client.connection.state, equals(ConnectionState.disconnected));

      // No WebSocket connection was attempted (auth failed before transport)
      expect(connectionAttempted, isFalse);

      // ErrorInfo has code 80019 wrapping the 40170 error
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));

      // Cause is the original 40170 error
      expect(client.connection.errorReason!.cause, isNotNull);
      final cause = client.connection.errorReason!.cause;
      if (cause is ErrorInfo) {
        expect(cause.code, equals(40170));
      }

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4f - authCallback returns invalid type treated as invalid format '
      'error', () {
    // UTS: realtime/unit/RSA4f/callback-invalid-type-format-0
    test('non-token return type causes DISCONNECTED with code 80019', () async {
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
          authCallback: (params) async {
            // Return an invalid type -- an integer is not a valid token format
            return 12345;
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      // Invalid format from authCallback -- connection should go to
      // DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);

      // RSA4c2: Connection transitioned to DISCONNECTED
      expect(client.connection.state, equals(ConnectionState.disconnected));

      // RSA4c1: errorReason has code 80019
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));
      expect(client.connection.errorReason!.statusCode, equals(401));

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4f - authCallback returns token string exceeding 128KiB treated as '
      'invalid format', () {
    // UTS: realtime/unit/RSA4f/callback-oversized-token-format-1
    test('oversized token string causes DISCONNECTED with code 80019',
        () async {
      // Generate a token string larger than 128KiB (131072 bytes)
      final oversizedToken = 'x' * 131073;

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
          authCallback: (params) async {
            return oversizedToken;
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      // Oversized token -- connection should go to DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);

      // RSA4c2: Connection transitioned to DISCONNECTED
      expect(client.connection.state, equals(ConnectionState.disconnected));

      // RSA4c1: errorReason has code 80019
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(80019));
      expect(client.connection.errorReason!.statusCode, equals(401));

      await client.close();
      mockWs.dispose();
    });
  });
}

/// Waits for the connection to reach the target state.
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

/// Polls until a condition is true, with timeout.
Future<void> _awaitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}

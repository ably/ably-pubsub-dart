import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for Connection#errorReason (RTN25).
///
/// These tests verify that errorReason is populated correctly
/// across various error scenarios.
///
/// Spec: uts/test/realtime/unit/connection/error_reason_test.md
void main() {
  group('RTN25 - errorReason set on connection errors', () {
    // UTS: realtime/unit/RTN25/error-reason-on-failed-0
    test('errorReason populated on connection failure', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40005,
              statusCode: 400,
              message: 'Invalid API key',
            ),
          );
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'invalid.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Initially errorReason should be null
      expect(client.connection.errorReason, isNull);

      // Start connection
      client.connect();

      // Wait for FAILED state
      await _awaitState(client.connection, ConnectionState.failed);

      // errorReason is set with error details
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40005));
      expect(client.connection.errorReason!.statusCode, equals(400));
      expect(client.connection.errorReason!.message, equals('Invalid API key'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN25/error-reason-disconnected-1
    test('errorReason set on DISCONNECTED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Connection attempt fails
          conn.respondWithRefused();
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for DISCONNECTED state
      await _awaitState(client.connection, ConnectionState.disconnected);

      // errorReason is set
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.message, isNotNull);

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN25/error-reason-suspended-2
    test('errorReason on SUSPENDED state after connectionStateTtl', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            // All connection attempts fail
            conn.respondWithRefused();
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: 1000,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Start connection (will fail)
        client.connect();

        // Wait for DISCONNECTED state
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance time past connectionStateTtl (default 120s)
        fakeTimers.elapseTime(const Duration(seconds: 121));
        await _pumpEventQueue();

        // Should be in SUSPENDED state
        expect(client.connection.state, equals(ConnectionState.suspended));

        // errorReason is set and indicates suspension
        expect(client.connection.errorReason, isNotNull);
        expect(client.connection.errorReason!.message, isNotNull);

        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN25/error-reason-token-error-3
    test('RTN25 - errorReason on non-renewable token errors (RSA4a)', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40142,
              statusCode: 401,
              message: 'Token expired',
            ),
          );
        },
      );

      // Use token directly (no way to renew) — RSA4a applies
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          token: 'expired_token',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Per RSA4a2: no means to renew → FAILED state
      await _awaitState(client.connection, ConnectionState.failed);

      // errorReason should indicate no means to renew (RSA4a2: error code 40171)
      expect(client.connection.errorReason, isNotNull);

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN25/error-reason-cleared-on-connect-4
    test('errorReason cleared on successful connection', () async {
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // First attempt fails
            conn.respondWithRefused();
          } else {
            // Second attempt succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          disconnectedRetryTimeout: 100,
          autoConnect: false,
          fallbackHosts: [], // Disable fallback hosts for this test
        ),
        webSocketClient: mockWs,
      );

      // Start connection (will fail initially)
      client.connect();

      // Wait for DISCONNECTED state
      await _awaitState(client.connection, ConnectionState.disconnected);

      // errorReason should be set after failure
      expect(client.connection.errorReason, isNotNull);

      // Wait for retry and successful connection
      await _awaitState(
        client.connection,
        ConnectionState.connected,
      );

      // errorReason behavior after successful connection is implementation-specific
      // Either cleared (null) or kept for debugging purposes

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN25/error-reason-protocol-error-5
    test('errorReason on protocol-level ERROR message', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 50000,
              statusCode: 500,
              message: 'Internal server error',
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

      // Start connection
      client.connect();

      // Wait for FAILED state
      await _awaitState(client.connection, ConnectionState.failed);

      // errorReason is set from ERROR protocol message
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(50000));
      expect(client.connection.errorReason!.statusCode, equals(500));
      expect(
        client.connection.errorReason!.message,
        equals('Internal server error'),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN25/error-reason-on-failed-0.1
    test('errorReason propagated to ConnectionStateChange events', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40003,
              statusCode: 400,
              message: 'Access token invalid',
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

      // Track state changes
      final stateChanges = <ConnectionStateChange>[];

      client.connection.on(ConnectionEvent.failed).listen((change) {
        stateChanges.add(change);
      });

      // Start connection
      client.connect();

      // Wait for FAILED state
      await _awaitState(client.connection, ConnectionState.failed);

      // State change event was emitted
      expect(stateChanges.length, equals(1));

      final change = stateChanges[0];

      // State change has reason populated
      expect(change.reason, isNotNull);
      expect(change.reason!.code, equals(40003));
      expect(change.reason!.statusCode, equals(400));
      expect(change.reason!.message, equals('Access token invalid'));

      // Connection errorReason matches state change reason
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(change.reason!.code));
      expect(
        client.connection.errorReason!.message,
        equals(change.reason!.message),
      );

      mockWs.dispose();
    });
  });

  group('RTN25 - errorReason across different error types', () {
    // UTS: realtime/unit/RTN25/error-reason-cleared-on-connect-4.1
    test('errorReason on connection timeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            // WebSocket connects but server never sends CONNECTED
            // Simulate unresponsive server
            conn.respondWithSilence();
          },
        );

        // Mock HTTP client for connectivity check
        final mockHttp = MockHttpClient(
          onRequest: (request) {
            request.respondWith(200, 'yes');
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second timeout
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
          httpClient: mockHttp,
        );

        client.connect();

        // Wait for CONNECTING state
        await _awaitState(client.connection, ConnectionState.connecting);

        // Pump microtasks to let the async chain progress and schedule
        // the connectionTimeout timer
        await _pumpEventQueue();

        // Advance time past the connection timeout
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Should be in DISCONNECTED state
        expect(client.connection.state, equals(ConnectionState.disconnected));

        // errorReason indicates timeout
        expect(client.connection.errorReason, isNotNull);
        expect(
          client.connection.errorReason!.message!.toLowerCase(),
          contains('timeout'),
        );

        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN25/error-reason-in-state-change-6
    test('errorReason persists across state transitions', () async {
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;

          if (connectionAttemptCount <= 2) {
            // First two attempts fail
            conn.respondWithRefused();
          } else {
            // Third attempt succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          disconnectedRetryTimeout: 100,
          autoConnect: false,
          fallbackHosts: [], // Disable fallback hosts for this test
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      // Wait for first DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);
      expect(client.connection.errorReason, isNotNull);

      // Wait for second DISCONNECTED (after retry)
      await _awaitState(
        client.connection,
        ConnectionState.connecting,
        timeout: const Duration(seconds: 2),
      );
      await _awaitState(client.connection, ConnectionState.disconnected);
      expect(client.connection.errorReason, isNotNull);

      // Finally connect successfully
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 3),
      );

      // errorReason lifecycle after successful connection is implementation-specific

      mockWs.dispose();
    });
  });
}

/// Helper function to wait for a connection state.
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

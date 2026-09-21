import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for Connection#whenState (RTN26).
///
/// These tests verify the whenState convenience function that calls
/// listeners immediately if already in state, or waits for the state.
///
/// Spec: uts/test/realtime/unit/connection/when_state_test.md
void main() {
  group('RTN26a - whenState calls listener immediately if already in state',
      () {
    // UTS: realtime/unit/RTN26a/immediate-callback-current-state-0
    test('invokes callback immediately with null when already in target state',
        () async {
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for CONNECTED state
      await _awaitState(client.connection, ConnectionState.connected);

      // Now call whenState for the current state
      var callbackInvoked = false;
      ConnectionStateChange? callbackArg;

      client.connection.whenState(ConnectionState.connected, (change) {
        callbackInvoked = true;
        callbackArg = change;
      });

      // Callback should be invoked immediately or very quickly
      await Future<void>.delayed(Duration.zero);

      // Callback was invoked immediately
      expect(callbackInvoked, isTrue);

      // Callback was invoked with null argument (not a StateChange object)
      expect(callbackArg, isNull);

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN26b - whenState waits for state if not already in it', () {
    // UTS: realtime/unit/RTN26b/deferred-callback-future-state-0
    test('waits for state transition when not currently in target state',
        () async {
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Connection is in INITIALIZED state
      expect(client.connection.state, equals(ConnectionState.initialized));

      // Set up whenState before connecting
      var callbackInvoked = false;
      ConnectionStateChange? callbackArg;

      client.connection.whenState(ConnectionState.connected, (change) {
        callbackInvoked = true;
        callbackArg = change;
      });

      // Callback should not be invoked yet
      expect(callbackInvoked, isFalse);

      // Start connection
      client.connect();

      // Wait for CONNECTED state
      await _awaitState(client.connection, ConnectionState.connected);

      // Give callback a moment to execute
      await Future<void>.delayed(Duration.zero);

      // Callback was invoked after state transition
      expect(callbackInvoked, isTrue);

      // Callback was invoked with a ConnectionStateChange object (not null)
      expect(callbackArg, isNotNull);
      expect(
        callbackArg!.previous,
        anyOf(
          equals(ConnectionState.initialized),
          equals(ConnectionState.connecting),
        ),
      );
      expect(callbackArg!.current, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN26b/fires-only-once-1
    test('whenState only fires once per call', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 2) {
              // Second attempt (immediate reconnect after disconnect): fail
              // This forces a timer-based retry so we can observe DISCONNECTED.
              conn.respondWithRefused();
            } else {
              // First and third+ attempts: connect
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-id-$connectionAttemptCount',
                  connectionKey: 'connection-key-$connectionAttemptCount',
                ),
              );
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: 1000,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Set up whenState listener
        var callbackCount = 0;

        client.connection.whenState(ConnectionState.connected, (change) {
          callbackCount++;
        });

        // Start connection
        client.connect();

        // Wait for first CONNECTED (immediate mock response)
        await _pumpEventQueue();
        expect(client.connection.state, equals(ConnectionState.connected));

        // Verify callback was invoked once
        expect(callbackCount, equals(1));

        // Force a disconnection — immediate reconnect (attempt 2) fails,
        // so connection enters DISCONNECTED with retry timer scheduled.
        mockWs.activeConnection!.close();
        await _pumpEventQueue();
        expect(client.connection.state, equals(ConnectionState.disconnected));

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Should be connected now after timer-based retry (attempt 3)
        expect(client.connection.state, equals(ConnectionState.connected));

        // Callback was still only invoked once (not again on reconnection)
        expect(callbackCount, equals(1));

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN26 - Multiple whenState calls', () {
    // UTS: realtime/unit/RTN26a/multiple-whenstate-calls-1
    test('multiple whenState listeners handled independently', () async {
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Set up multiple whenState listeners before connecting
      var callback1Invoked = false;
      var callback2Invoked = false;
      var callback3Invoked = false;

      client.connection.whenState(ConnectionState.connected, (change) {
        callback1Invoked = true;
      });

      client.connection.whenState(ConnectionState.connected, (change) {
        callback2Invoked = true;
      });

      client.connection.whenState(ConnectionState.connecting, (change) {
        callback3Invoked = true;
      });

      // Start connection
      client.connect();

      // Wait for CONNECTED state
      await _awaitState(client.connection, ConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // All whenState callbacks were invoked
      expect(callback1Invoked, isTrue);
      expect(callback2Invoked, isTrue);
      expect(callback3Invoked, isTrue);

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN26a/no-fire-for-past-state-2
    test('whenState with already-passed state does not fire', () async {
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for CONNECTED state
      await _awaitState(client.connection, ConnectionState.connected);

      // Now call whenState for a past state (CONNECTING)
      var callbackInvoked = false;

      client.connection.whenState(ConnectionState.connecting, (change) {
        callbackInvoked = true;
      });

      // Wait to see if callback is invoked
      await Future<void>.delayed(Duration.zero);

      // Callback should NOT be invoked (we're not in CONNECTING state anymore)
      expect(callbackInvoked, isFalse);

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN26 - whenState with different states', () {
    // UTS: realtime/unit/RTN26/whenstate-different-states-0
    test('whenState works correctly across different state transitions',
        () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Connection attempt fails
          conn.respondWithRefused();
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          fallbackHosts: [],
        ),
        webSocketClient: mockWs,
      );

      // Set up whenState listeners for various states
      var initializedFired = false;
      var connectingFired = false;
      var disconnectedFired = false;

      client.connection.whenState(ConnectionState.initialized, (change) {
        initializedFired = true;
      });

      client.connection.whenState(ConnectionState.connecting, (change) {
        connectingFired = true;
      });

      client.connection.whenState(ConnectionState.disconnected, (change) {
        disconnectedFired = true;
      });

      // Initially in INITIALIZED
      await Future<void>.delayed(Duration.zero);

      // Should fire immediately for current state
      expect(initializedFired, isTrue);
      expect(connectingFired, isFalse);
      expect(disconnectedFired, isFalse);

      // Start connection
      client.connect();

      // Wait for DISCONNECTED (connection will fail)
      await _awaitState(
        client.connection,
        ConnectionState.disconnected,
      );
      await Future<void>.delayed(Duration.zero);

      // All states were reached and callbacks invoked
      expect(initializedFired, isTrue);
      expect(connectingFired, isTrue);
      expect(disconnectedFired, isTrue);

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN26/whenstate-different-states-0.1
    test('whenState for FAILED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.error(
              code: 50000,
              statusCode: 500,
              message: 'Internal server error',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      var failedFired = false;
      ConnectionStateChange? failedChange;

      client.connection.whenState(ConnectionState.failed, (change) {
        failedFired = true;
        failedChange = change;
      });

      // Start connection
      client.connect();

      // Wait for FAILED state
      await _awaitState(client.connection, ConnectionState.failed);
      await Future<void>.delayed(Duration.zero);

      expect(failedFired, isTrue);
      expect(failedChange, isNotNull);
      expect(failedChange!.current, equals(ConnectionState.failed));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN26/whenstate-different-states-0.2
    test('whenState for CLOSED state', () async {
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      var closedFired = false;

      // Start connection first
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Now set up whenState for CLOSED
      client.connection.whenState(ConnectionState.closed, (change) {
        closedFired = true;
      });

      expect(closedFired, isFalse);

      // Close the connection
      await client.close();

      // Wait for CLOSED state
      await _awaitState(client.connection, ConnectionState.closed);
      await Future<void>.delayed(Duration.zero);

      expect(closedFired, isTrue);
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
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

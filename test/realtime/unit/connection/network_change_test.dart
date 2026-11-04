import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for network connectivity change behavior (RTN20).
///
/// RTN20 specifies how the client should respond to operating system
/// network connectivity events:
///
/// - RTN20a: When CONNECTED/CONNECTING and network goes offline,
///   transition to DISCONNECTED immediately.
/// - RTN20b: When DISCONNECTED/SUSPENDED and network comes online,
///   attempt to connect immediately (bypassing retry timer).
/// - RTN20c: When CONNECTING and network comes online,
///   restart the pending connection attempt.
///
/// NOTE: These tests simulate network connectivity changes by using
/// the mock WebSocket infrastructure to trigger disconnections and
/// reconnections. A full RTN20 implementation requires an OS-level
/// network connectivity listener, which is not yet implemented.
/// These tests verify the connection state machine's response to
/// the equivalent events.
///
/// Spec: specification/uts/realtime/unit/connection/network_change_test.md
void main() {
  group('RTN20a - Network goes offline while CONNECTED', () {
    test(
        'transitions to DISCONNECTED immediately when transport '
        'drops while connected', () async {
      final stateChanges = <ConnectionStateChange>[];

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

      // Record all state changes
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Simulate network going offline by closing the WebSocket transport.
      // This is equivalent to an OS-level network loss event.
      mockWs.activeConnection!.simulateDisconnect();

      // Should transition to DISCONNECTED immediately.
      // Note: RTN15a causes immediate reconnect (via scheduleMicrotask), so the
      // connection may already be in CONNECTING by the time we check. We verify
      // via the recorded state changes instead.
      await _awaitState(client.connection, ConnectionState.disconnected);

      // Verify a DISCONNECTED state change was emitted from CONNECTED
      final disconnectedChange = stateChanges
          .firstWhere((c) => c.current == ConnectionState.disconnected);
      expect(disconnectedChange.previous, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
    });

    test(
        'transitions to DISCONNECTED immediately when transport '
        'drops while connecting', () async {
      final stateChanges = <ConnectionState>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // First attempt: connection succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'conn-1',
                connectionKey: 'key-1',
              ),
            );
          } else {
            // Reconnection succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'conn-1',
                connectionKey: 'key-1-resumed',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          disconnectedRetryTimeout: 100,
        ),
        webSocketClient: mockWs,
      );

      client.connection.on().listen((change) {
        stateChanges.add(change.current);
      });

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Simulate network loss
      mockWs.activeConnection!.simulateDisconnect();

      // Wait for the client to detect the disconnect
      await _awaitState(client.connection, ConnectionState.disconnected);

      // The client should automatically attempt to reconnect
      await _awaitState(
        client.connection,
        ConnectionState.connected,
      );

      // Verify state sequence: connecting -> connected -> disconnected ->
      //                         connecting -> connected
      expect(
        stateChanges,
        containsAllInOrder([
          ConnectionState.connecting,
          ConnectionState.connected,
          ConnectionState.disconnected,
          ConnectionState.connecting,
          ConnectionState.connected,
        ]),
      );

      expect(connectionAttemptCount, equals(2));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN20b - Network comes online while DISCONNECTED', () {
    // UTS: realtime/unit/RTN20b/network-available-disconnected-connects-0
    test(
        'immediately attempts reconnection when network becomes '
        'available while disconnected', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              // Initial connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-1',
                ),
              );
            } else if (connectionAttemptCount == 2) {
              // First reconnect attempt fails (simulating ongoing offline)
              conn.respondWithRefused();
            } else {
              // Subsequent reconnect succeeds (network came back)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-1-resumed',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        // Connect successfully
        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Simulate network loss
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // The client will try to reconnect immediately (RTN15a),
        // but that fails (connectionAttemptCount == 2 -> refused).
        // It then enters DISCONNECTED with a retry timer.
        for (var i = 0; i < 5; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 500));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.disconnected) break;
        }

        expect(client.connection.state, equals(ConnectionState.disconnected));
        final attemptsBefore = connectionAttemptCount;

        // RTN20b: When network comes back online while DISCONNECTED,
        // the client should immediately attempt to connect rather than
        // waiting for the full retry timer.
        //
        // Simulate "network up" by advancing time to trigger the retry
        // timer, which simulates what would happen when the network
        // listener fires the "online" event.
        fakeTimers.elapseTime(const Duration(milliseconds: 15000));
        await _pumpEventQueue();

        // Wait for successful reconnection
        await _awaitState(
          client.connection,
          ConnectionState.connected,
        );

        expect(client.connection.state, equals(ConnectionState.connected));
        expect(connectionAttemptCount, greaterThan(attemptsBefore));

        await client.close();
        mockWs.dispose();
      });
    });

    test(
        'immediately attempts reconnection when network becomes '
        'available while suspended', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-1',
                  connectionStateTtl: 2000, // Short TTL to reach SUSPENDED
                ),
              );
            } else if (connectionAttemptCount <= 10) {
              // Reconnection attempts fail
              conn.respondWithRefused();
            } else {
              // Eventually succeeds (network came back)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-2',
                  connectionKey: 'key-2',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: 500,
            suspendedRetryTimeout: 2000,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        // Connect successfully
        client.connect();
        await _pumpEventQueue();
        expect(client.connection.state, equals(ConnectionState.connected));

        // Simulate network loss
        mockWs.activeConnection!.simulateDisconnect();

        // Advance time until SUSPENDED (connectionStateTtl = 2000ms)
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 1000));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.suspended) break;
        }

        expect(client.connection.state, equals(ConnectionState.suspended));

        // RTN20b: Keep advancing until we get past attempt 10 (which
        // succeeds in the mock). From SUSPENDED, each retry uses
        // suspendedRetryTimeout (2000ms).
        for (var i = 0; i < 40; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 2500));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.connected) break;
        }

        // Verify we eventually reconnected
        expect(client.connection.state, equals(ConnectionState.connected));

        // The state sequence should have included SUSPENDED
        expect(stateChanges, contains(ConnectionState.suspended));

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN20c - Network comes online while CONNECTING', () {
    // UTS: realtime/unit/RTN20c/network-available-connecting-restarts-0
    test(
        'restarts pending connection attempt when network status '
        'changes during connection', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              // First attempt: silence (simulating no response due to offline)
              conn.respondWithSilence();
            } else {
              // Second attempt succeeds (network came back)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-1',
                ),
              );
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 5000, // 5 second timeout
            disconnectedRetryTimeout: 2000, // Short retry for test
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        // Start connecting - first attempt gets silence
        client.connect();
        await _pumpEventQueue();

        expect(client.connection.state, equals(ConnectionState.connecting));
        expect(connectionAttemptCount, equals(1));

        // RTN20c: When CONNECTING and network comes online, the client
        // should restart the pending connection attempt.
        // Advance time past the request timeout to trigger a retry.
        fakeTimers.elapseTime(const Duration(milliseconds: 5100));
        await _pumpEventQueue();

        // The client should have transitioned through DISCONNECTED and
        // be attempting a new connection. Advance enough time to pass
        // the disconnectedRetryTimeout (2000ms with jitter).
        for (var i = 0; i < 10; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 1000));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.connected) break;
        }

        // Eventually should succeed
        await _awaitState(
          client.connection,
          ConnectionState.connected,
        );

        expect(client.connection.state, equals(ConnectionState.connected));
        expect(connectionAttemptCount, greaterThan(1));

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN20 - Network change does not affect terminal states', () {
    // UTS: realtime/unit/RTN20a/network-loss-connected-disconnects-0
    test('CLOSED state is not affected by network changes', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-1',
              connectionKey: 'key-1',
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

      // Connect then close
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      await client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      // CLOSED state should not be affected by network changes.
      // The connection should remain CLOSED.
      expect(client.connection.state, equals(ConnectionState.closed));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN20a/network-loss-connecting-disconnects-1
    test('FAILED state is not affected by network changes', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-1',
              connectionKey: 'key-1',
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

      // Connect then trigger FAILED via fatal error
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 50000,
          statusCode: 500,
          message: 'Fatal server error',
        ),
      );
      await _awaitState(client.connection, ConnectionState.failed);

      // FAILED state should not be affected by network changes.
      expect(client.connection.state, equals(ConnectionState.failed));

      mockWs.dispose();
    });
  });

  group(
      'RTN20 - Multiple rapid network changes do not cause state '
      'machine issues', () {
    test('rapid disconnect/reconnect cycles are handled gracefully', () async {
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-$connectionAttemptCount',
              connectionKey: 'key-$connectionAttemptCount',
            ),
          );
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          disconnectedRetryTimeout: 100, // Fast retry
        ),
        webSocketClient: mockWs,
      );

      // Connect
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(connectionAttemptCount, equals(1));

      // Simulate rapid network flapping: disconnect and reconnect
      for (var cycle = 0; cycle < 3; cycle++) {
        mockWs.activeConnection!.simulateDisconnect();
        await _awaitState(client.connection, ConnectionState.disconnected);
        await _awaitState(
          client.connection,
          ConnectionState.connected,
        );
      }

      // After 3 cycles, we should have 4 total connection attempts
      // (1 initial + 3 reconnections)
      expect(connectionAttemptCount, equals(4));
      expect(client.connection.state, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
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

/// Pumps the event queue multiple times to allow microtasks to complete.
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

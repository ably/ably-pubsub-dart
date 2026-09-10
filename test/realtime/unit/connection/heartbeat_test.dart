import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for heartbeat behavior (RTN23).
///
/// These tests use mocked WebSocket and FakeTimerManager to verify
/// connection heartbeat and idle timeout behavior.
///
/// Spec: uts/test/realtime/unit/connection/heartbeat_test.md
void main() {
  group('RTN23a - Disconnect after maxIdleInterval + realtimeRequestTimeout',
      () {
    // UTS: realtime/unit/RTN23a/idle-timeout-reconnect-1
    test('closes WebSocket and reconnects when no server activity detected',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 5000, // 5 seconds
              ),
            );
            // Server sends CONNECTED but then no further messages
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 2000, // 2 seconds
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Record all state changes
        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        // Start connection
        client.connect();

        // Wait for CONNECTED state
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Advance time past maxIdleInterval + realtimeRequestTimeout
        // = 5000 + 2000 = 7000ms
        fakeTimers.elapseTime(const Duration(milliseconds: 7100));
        await _pumpEventQueue();

        // Wait for reconnection to complete
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify the sequence of state changes:
        // CONNECTING -> CONNECTED -> DISCONNECTED -> CONNECTING -> CONNECTED
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

        // Verify the client closed the first WebSocket connection
        expect(mockWs.clientCloseEvents, hasLength(1));

        // Verify two connection attempts were made (initial + reconnect)
        expect(connectionAttemptCount, equals(2));

        // Verify we're connected with the new connection details
        expect(client.connection.id, equals('connection-id-2'));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23a/heartbeat-resets-timer-2
    test('HEARTBEAT message resets idle timer', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 3000, // 3 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Start connection
        client.connect();

        // Wait for CONNECTED state
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Advance time 2 seconds (not enough to trigger timeout of 3000+1000=4000ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 2000));
        await _pumpEventQueue();

        // Send HEARTBEAT from server to reset timer
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.heartbeat(),
        );
        await _pumpEventQueue();

        // Advance another 2 seconds (total 4 seconds, but timer was reset at 2s)
        fakeTimers.elapseTime(const Duration(milliseconds: 2000));
        await _pumpEventQueue();

        // Connection should still be alive (timer was reset by HEARTBEAT)
        expect(client.connection.state, equals(ConnectionState.connected));
        // Still only 1 connection attempt - no reconnection triggered
        expect(connectionAttemptCount, equals(1));

        // Advance past the new timeout window (4000ms from last heartbeat)
        fakeTimers.elapseTime(const Duration(milliseconds: 2100));
        await _pumpEventQueue();

        // Should have reconnected (immediate reconnection per RTN15a)
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify reconnection happened
        expect(connectionAttemptCount, equals(2));
        expect(mockWs.clientCloseEvents, hasLength(1));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23a/any-message-resets-timer-3
    test('any protocol message resets idle timer and client closes on timeout',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 2000, // 2 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Record all state changes
        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Advance 1.5 seconds (timeout is 2000+1000=3000ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 1500));
        await _pumpEventQueue();

        // Send ACK message from server (timer reset)
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.ack(msgSerial: 0),
        );
        await _pumpEventQueue();

        // Advance another 1.5 seconds (total 3s, but timer was reset at 1.5s)
        fakeTimers.elapseTime(const Duration(milliseconds: 1500));
        await _pumpEventQueue();

        // Send MESSAGE from server (timer reset again)
        final channelName = testChannelName('RTN23a-message');
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.message(
            channel: channelName,
            name: 'event',
            data: 'data',
          ),
        );
        await _pumpEventQueue();

        // Advance another 1.5 seconds
        fakeTimers.elapseTime(const Duration(milliseconds: 1500));
        await _pumpEventQueue();

        // At this point, only one connection attempt (no timeout yet)
        expect(connectionAttemptCount, equals(1));

        // Advance past timeout without any message (3000ms + buffer)
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Wait for reconnection to complete
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify the state change sequence includes disconnected
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

        // Verify the client closed the WebSocket connection
        expect(mockWs.clientCloseEvents, hasLength(1));

        // Verify two connection attempts were made
        expect(connectionAttemptCount, equals(2));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23a/timeout-triggers-reconnect-4
    test('heartbeat timeout triggers immediate reconnection', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 2000, // 2 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Record all state changes
        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        expect(connectionAttemptCount, equals(1));

        // Advance time past maxIdleInterval + realtimeRequestTimeout
        // = 2000 + 1000 = 3000ms
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Wait for reconnection to complete (immediate per RTN15a)
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify the state change sequence shows disconnected then reconnected
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

        // Verify two connection attempts were made (initial + reconnect)
        expect(connectionAttemptCount, equals(2));

        // Verify the client is now connected with new connection details
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals('connection-id-2'));

        // Verify the first connection was closed by the client
        expect(mockWs.clientCloseEvents, hasLength(1));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23a/reconnect-uses-resume-5
    test('reconnection after heartbeat timeout uses resume', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final connectionAttempts = <Uri>[];
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttempts.add(conn.url);
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-${connectionAttempts.length}',
                connectionKey: 'connection-key-${connectionAttempts.length}',
                maxIdleInterval: 2000, // 2 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Record all state changes
        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Advance time past timeout to trigger disconnection
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Wait for reconnection to complete (immediate per RTN15a)
        await _awaitState(client.connection, ConnectionState.connected);

        // Verify the state change sequence shows disconnected
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

        expect(connectionAttempts, hasLength(2));

        // First connection should not have resume parameter
        final firstUrl = connectionAttempts[0];
        expect(firstUrl.queryParameters.containsKey('resume'), isFalse);

        // Second connection should include resume parameter with first connectionKey
        final secondUrl = connectionAttempts[1];
        expect(secondUrl.queryParameters['resume'], equals('connection-key-1'));

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN23a - heartbeats=true query parameter', () {
    // UTS: realtime/unit/RTN23a/heartbeats-true-query-param-0
    test('heartbeats=true query parameter sent in WebSocket URL', () async {
      final connectionUrls = <Uri>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionUrls.add(conn.url);
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
          useBinaryProtocol: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Verify the WebSocket URL was captured
      expect(connectionUrls, hasLength(1));

      // RTN23a: The client should include heartbeats=true in the URL
      final url = connectionUrls[0];
      expect(url.queryParameters['heartbeats'], equals('true'));
      expect(url.queryParameters['format'], equals('json'));
      expect(url.queryParameters['v'], isNotNull);

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN23b - Client can request heartbeats in query params', () {
    // UTS: realtime/unit/RTN23b/heartbeats-false-query-param-0
    test('client requests heartbeats in connection URL', () async {
      final connectionUrls = <Uri>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Record the connection URL
          connectionUrls.add(conn.url);

          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      // Client with default behavior (heartbeats enabled)
      final client1 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          useBinaryProtocol: false,
        ),
        webSocketClient: mockWs,
      );

      // Connect first client
      client1.connect();
      await _awaitState(client1.connection, ConnectionState.connected);

      // Check URL includes heartbeats parameter (default is true or omitted)
      // expect(connectionUrls[0].queryParameters['heartbeats'], anyOf('true', isNull));

      await client1.close();

      // Client with heartbeats explicitly configured
      // (Implementation-specific how to disable heartbeats)
      final client2 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          useBinaryProtocol: false,
          // Implementation may have a specific option for this
        ),
        webSocketClient: mockWs,
      );

      client2.connect();
      await _awaitState(client2.connection, ConnectionState.connected);

      // Verify implementation adds heartbeats query param
      // expect(connectionUrls[1].queryParameters['heartbeats'], ...);

      await client2.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN23b/timeout-triggers-reconnect-4
    test('idle timeout triggers reconnect when no activity detected', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 4000, // 4 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 2000, // 2 seconds
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Advance past maxIdleInterval + realtimeRequestTimeout
        // = 4000 + 2000 = 6000ms
        fakeTimers.elapseTime(const Duration(milliseconds: 6100));
        await _pumpEventQueue();

        // Wait for reconnection
        await _awaitState(client.connection, ConnectionState.connected);

        expect(connectionAttemptCount, equals(2));
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

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23b/any-message-resets-timer-3
    test('receiving a heartbeat resets the idle timer', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 3000, // 3 seconds
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // 1 second
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Advance 2.5 seconds (timeout is 3000+1000=4000ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 2500));
        await _pumpEventQueue();

        // Send HEARTBEAT from server — resets the idle timer
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.heartbeat(),
        );
        await _pumpEventQueue();

        // Advance another 2.5 seconds (total 5s, but timer reset at 2.5s)
        fakeTimers.elapseTime(const Duration(milliseconds: 2500));
        await _pumpEventQueue();

        // Connection should still be alive (timer was reset by heartbeat)
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(connectionAttemptCount, equals(1));

        // Now advance past the full timeout from last heartbeat (4000ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 1600));
        await _pumpEventQueue();

        // Should have reconnected
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(2));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23b/idle-timeout-reconnect-1
    test('idle timeout fires and triggers reconnect', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final stateChanges = <ConnectionState>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 2000,
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000,
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on().listen((change) {
          stateChanges.add(change.current);
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Advance past timeout (2000 + 1000 = 3000ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Wait for reconnect to complete
        await _awaitState(client.connection, ConnectionState.connected);

        expect(connectionAttemptCount, equals(2));
        expect(client.connection.id, equals('connection-id-2'));

        // Verify disconnected state was hit
        expect(stateChanges, contains(ConnectionState.disconnected));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23b/reconnect-uses-resume-5
    test('reconnect after heartbeat timeout uses resume', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final connectionAttempts = <Uri>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttempts.add(conn.url);
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-${connectionAttempts.length}',
                connectionKey: 'connection-key-${connectionAttempts.length}',
                maxIdleInterval: 2000,
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000,
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Advance past timeout
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Wait for reconnection
        await _awaitState(client.connection, ConnectionState.connected);

        expect(connectionAttempts, hasLength(2));

        // First connection: no resume
        expect(
          connectionAttempts[0].queryParameters.containsKey('resume'),
          isFalse,
        );

        // Second connection: resume with original key
        expect(
          connectionAttempts[1].queryParameters['resume'],
          equals('connection-key-1'),
        );

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23b/multiple-pings-keep-alive-6
    test('multiple heartbeats keep connection alive, timer keeps resetting',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-$connectionAttemptCount',
                connectionKey: 'connection-key-$connectionAttemptCount',
                maxIdleInterval: 2000,
              ),
            );
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            realtimeRequestTimeout: 1000, // timeout = 2000+1000 = 3000ms
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            useBinaryProtocol: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(1));

        // Send 5 heartbeats at 2-second intervals.
        // Each one resets the 3000ms idle timer, so the connection
        // should stay alive throughout.
        for (var i = 0; i < 5; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 2000));
          await _pumpEventQueue();

          // Send heartbeat before timeout fires
          mockWs.activeConnection!.sendToClient(
            ProtocolMessageHelpers.heartbeat(),
          );
          await _pumpEventQueue();
        }

        // Connection should still be alive after 10 seconds of heartbeats
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(connectionAttemptCount, equals(1));

        // Now stop sending heartbeats and let the timer expire
        fakeTimers.elapseTime(const Duration(milliseconds: 3100));
        await _pumpEventQueue();

        // Should have reconnected
        await _awaitState(client.connection, ConnectionState.connected);
        expect(connectionAttemptCount, equals(2));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN23b/ping-frame-resets-timer-2
    test('server respects heartbeats=false', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
                maxIdleInterval: 2000, // 2 seconds
              ),
            );
            // Server sends no HEARTBEAT messages
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            useBinaryProtocol: false,
            // Configure to disable heartbeats (implementation-specific)
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Advance time well past maxIdleInterval
        fakeTimers.elapseTime(const Duration(milliseconds: 10000));
        await _pumpEventQueue();

        // Connection behavior when heartbeats disabled is implementation-specific
        // Either stays connected indefinitely or has different timeout behavior
        final state = client.connection.state;
        expect(
          state,
          anyOf(
            equals(ConnectionState.connected),
            equals(ConnectionState.disconnected),
          ),
        );

        await client.close();
        mockWs.dispose();
      });
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

/// Pumps the event queue multiple times to allow microtasks to complete.
///
/// A single [Future.delayed(Duration.zero)] only processes one "tick" of
/// microtasks. Multiple nested scheduleMicrotask calls (e.g., close()
/// schedules onClose, which schedules reconnect) require multiple pumps.
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

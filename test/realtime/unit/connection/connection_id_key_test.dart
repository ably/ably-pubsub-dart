import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for connection id (RTN8) and connection key (RTN9).
///
/// Spec: uts/test/realtime/unit/connection/connection_id_key_test.md
void main() {
  group('RTN8a - Connection ID is unset until connected', () {
    // UTS: realtime/unit/RTN8a/id-unset-until-connected-0
    test('id is null before connecting and set after CONNECTED', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'unique-conn-id-1',
              connectionKey: 'conn-key-1',
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

      // Before connecting, id should be null
      expect(client.connection.id, isNull);

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      expect(client.connection.id, equals('unique-conn-id-1'));

      mockWs.dispose();
    });
  });

  group('RTN9a - Connection key is unset until connected', () {
    // UTS: realtime/unit/RTN9a/key-unset-until-connected-0
    test('key is null before connecting and set after CONNECTED', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'unique-conn-id-1',
              connectionKey: 'conn-key-1',
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

      // Before connecting, key should be null
      expect(client.connection.key, isNull);

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      expect(client.connection.key, equals('conn-key-1'));

      mockWs.dispose();
    });
  });

  group('RTN8b - Connection ID is unique per connection', () {
    // UTS: realtime/unit/RTN8b/id-unique-per-connection-0
    test('two clients receive different connection IDs', () async {
      var connectionCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-id-$connectionCount',
              connectionKey: 'conn-key-$connectionCount',
            ),
          );
        },
      );

      final client1 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final client2 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client1.connect();
      await _awaitState(client1.connection, ConnectionState.connected);

      client2.connect();
      await _awaitState(client2.connection, ConnectionState.connected);

      expect(client1.connection.id, isNot(equals(client2.connection.id)));
      expect(client1.connection.id, equals('conn-id-1'));
      expect(client2.connection.id, equals('conn-id-2'));

      mockWs.dispose();
    });
  });

  group('RTN9b - Connection key is unique per connection', () {
    // UTS: realtime/unit/RTN9b/key-unique-per-connection-0
    test('two clients receive different connection keys', () async {
      var connectionCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-id-$connectionCount',
              connectionKey: 'conn-key-$connectionCount',
            ),
          );
        },
      );

      final client1 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final client2 = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client1.connect();
      await _awaitState(client1.connection, ConnectionState.connected);

      client2.connect();
      await _awaitState(client2.connection, ConnectionState.connected);

      expect(client1.connection.key, isNot(equals(client2.connection.key)));
      expect(client1.connection.key, equals('conn-key-1'));
      expect(client2.connection.key, equals('conn-key-2'));

      mockWs.dispose();
    });
  });

  group('RTN8c - Connection ID is null after CLOSED', () {
    // UTS: realtime/unit/RTN8c/id-null-after-closed-0
    test('id is cleared when connection enters CLOSED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-id-1',
              connectionKey: 'conn-key-1',
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

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(client.connection.id, equals('conn-id-1'));

      await client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      expect(client.connection.id, isNull);

      mockWs.dispose();
    });
  });

  group('RTN9c - Connection key is null after CLOSED', () {
    // UTS: realtime/unit/RTN9c/key-null-after-closed-0
    test('key is cleared when connection enters CLOSED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-id-1',
              connectionKey: 'conn-key-1',
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

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(client.connection.key, equals('conn-key-1'));

      await client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      expect(client.connection.key, isNull);

      mockWs.dispose();
    });
  });

  group('RTN8c, RTN9c - ID and key null after FAILED', () {
    // UTS: realtime/unit/RTN8c/id-key-null-after-failed-1
    test('id and key are cleared on FAILED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 80000,
              statusCode: 400,
              message: 'Fatal error',
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

      client.connect();
      await _awaitState(client.connection, ConnectionState.failed);

      expect(client.connection.id, isNull);
      expect(client.connection.key, isNull);

      mockWs.dispose();
    });
  });

  group('RTN8c, RTN9c - ID and key null after SUSPENDED', () {
    // UTS: realtime/unit/RTN8c/id-key-null-after-suspended-2
    test('id and key are cleared when connection enters SUSPENDED', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) => conn.respondWithRefused(),
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
            suspendedRetryTimeout: 100,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance past connectionStateTtl (120s) to reach SUSPENDED
        fakeTimers.elapseTime(const Duration(seconds: 121));
        await _pumpEventQueue();
        await _awaitState(client.connection, ConnectionState.suspended);

        expect(client.connection.id, isNull);
        expect(client.connection.key, isNull);

        mockWs.dispose();
      });
    });
  });
}

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

Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

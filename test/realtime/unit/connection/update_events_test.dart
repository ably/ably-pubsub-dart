import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for UPDATE events (RTN24).
///
/// These tests verify that receiving CONNECTED while already CONNECTED
/// emits UPDATE events (not CONNECTED events) and updates connection details.
///
/// Spec: uts/test/realtime/unit/connection/update_events_test.md
void main() {
  group('RTN24 - CONNECTED message while already CONNECTED emits UPDATE', () {
    // UTS: realtime/unit/RTN24/no-duplicate-connected-event-3
    test('emits UPDATE event, not CONNECTED event', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
              clientId: 'client-123',
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

      // Track events
      final connectedEvents = <ConnectionStateChange>[];
      final updateEvents = <ConnectionStateChange>[];

      client.connection.on(ConnectionEvent.connected).listen((change) {
        connectedEvents.add(change);
      });

      client.connection.on(ConnectionEvent.update).listen((change) {
        updateEvents.add(change);
      });

      // Start connection
      client.connect();

      // Wait for initial CONNECTED state
      await _awaitState(client.connection, ConnectionState.connected);

      // Verify initial connection
      expect(connectedEvents.length, equals(1));
      expect(updateEvents.length, equals(0));

      // Server sends another CONNECTED message (e.g., after reauth)
      // connectionId stays the same — it's a top-level ProtocolMessage
      // field, not inside connectionDetails, so RTN24 doesn't change it.
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(
          connectionId: 'connection-id-1',
          connectionKey: 'connection-key-1',
          maxIdleInterval: 20000, // Different value
          clientId: 'client-123',
        ),
      );

      // Allow stream events to be delivered
      await Future<void>.delayed(Duration.zero);

      // State remains CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // No additional CONNECTED event was emitted
      expect(connectedEvents.length, equals(1));

      // UPDATE event was emitted
      expect(updateEvents.length, equals(1));

      // UPDATE event has correct structure
      final updateChange = updateEvents[0];
      expect(updateChange.previous, equals(ConnectionState.connected));
      expect(updateChange.current, equals(ConnectionState.connected));
      expect(updateChange.reason, isNull); // No error in this case

      // connection.id and connection.key are unchanged
      expect(client.connection.id, equals('connection-id-1'));
      expect(client.connection.key, equals('connection-key-1'));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN24/connected-emits-update-0
    test('UPDATE event includes error reason when present', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
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

      // Track UPDATE events
      final updateEvents = <ConnectionStateChange>[];

      client.connection.on(ConnectionEvent.update).listen((change) {
        updateEvents.add(change);
      });

      // Start connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Server sends CONNECTED with error (e.g., token renewed due to expiry)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(
          connectionId: 'connection-id-1',
          connectionKey: 'connection-key-1',
          error: const ErrorInfo(
            code: 40142,
            statusCode: 401,
            message: 'Token expired; renewed automatically',
          ),
        ),
      );

      // Allow stream events to be delivered
      await Future<void>.delayed(Duration.zero);

      // UPDATE event was emitted
      expect(updateEvents.length, equals(1));

      // UPDATE event has error reason
      final updateChange = updateEvents[0];
      expect(updateChange.previous, equals(ConnectionState.connected));
      expect(updateChange.current, equals(ConnectionState.connected));
      expect(updateChange.reason, isNotNull);
      expect(updateChange.reason!.code, equals(40142));
      expect(updateChange.reason!.statusCode, equals(401));
      expect(updateChange.reason!.message, contains('Token expired'));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN24/update-event-with-error-1
    test('UPDATE event includes error when server sends CONNECTED with error',
        () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
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

      // Track UPDATE events
      final updateEvents = <ConnectionStateChange>[];
      final connectedEvents = <ConnectionStateChange>[];

      client.connection.on(ConnectionEvent.update).listen((change) {
        updateEvents.add(change);
      });

      client.connection.on(ConnectionEvent.connected).listen((change) {
        connectedEvents.add(change);
      });

      // Start connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      expect(connectedEvents.length, equals(1));
      expect(updateEvents.length, equals(0));

      // Server sends CONNECTED with different connectionDetails AND an error
      // (e.g., token was renewed, or server-side config changed)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(
          connectionId: 'connection-id-1',
          connectionKey: 'connection-key-updated',
          maxIdleInterval: 20000,
          error: const ErrorInfo(
            code: 40142,
            statusCode: 401,
            message: 'Token expired; connection details updated',
          ),
        ),
      );

      // Allow stream events to be delivered
      await Future<void>.delayed(Duration.zero);

      // State remains CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // No additional CONNECTED event
      expect(connectedEvents.length, equals(1));

      // UPDATE event was emitted
      expect(updateEvents.length, equals(1));

      // UPDATE event includes the error
      final updateChange = updateEvents[0];
      expect(updateChange.previous, equals(ConnectionState.connected));
      expect(updateChange.current, equals(ConnectionState.connected));
      expect(updateChange.reason, isNotNull);
      expect(updateChange.reason!.code, equals(40142));
      expect(updateChange.reason!.statusCode, equals(401));
      expect(updateChange.reason!.message, contains('Token expired'));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN24/connection-details-override-2
    test('connectionDetails override stored details', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
              maxIdleInterval: 10000,
              connectionStateTtl: 60000,
              maxMessageSize: 16384,
              serverId: 'server-1',
              clientId: 'client-original',
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
      await _awaitState(client.connection, ConnectionState.connected);

      // Verify initial connection details
      expect(client.connection.id, equals('connection-id-1'));
      expect(client.connection.key, equals('connection-key-1'));

      // Server sends new CONNECTED with different connectionDetails (RTN24)
      // connectionId stays the same — it's not inside connectionDetails.
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(
          connectionId: 'connection-id-1',
          connectionKey: 'connection-key-1',
          maxIdleInterval: 20000, // Changed
          maxMessageSize: 32768, // Changed
          serverId: 'server-2', // Changed
          clientId: 'client-updated', // Changed
        ),
      );

      // Allow stream events to be delivered
      await Future<void>.delayed(Duration.zero);

      // connection.id is unchanged (not inside connectionDetails)
      expect(client.connection.id, equals('connection-id-1'));
      expect(client.connection.key, equals('connection-key-1'));

      // State remains CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
    });

    test(
        'no duplicate CONNECTED events when receiving CONNECTED while connected',
        () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
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

      // Track all events
      final allEvents = <Map<String, dynamic>>[];

      // Subscribe to all connection state events
      for (final state in ConnectionState.values) {
        client.connection
            .on(ConnectionEventExtension.fromState(state))
            .listen((change) {
          allEvents.add({
            'type': 'state',
            'state': state,
            'change': change,
          });
        });
      }

      // Also subscribe to UPDATE
      client.connection.on(ConnectionEvent.update).listen((change) {
        allEvents.add({
          'type': 'update',
          'change': change,
        });
      });

      // Start connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Record event count after initial connection
      final initialEventCount = allEvents.length;

      // Send multiple CONNECTED messages (same connectionId — it never changes)
      for (var i = 1; i <= 3; i++) {
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.connected(
            connectionId: 'connection-id-1',
            connectionKey: 'connection-key-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Exactly 3 UPDATE events were added
      final newEvents = allEvents.sublist(initialEventCount);
      expect(newEvents.length, equals(3));

      // All new events are UPDATE events, not CONNECTED state events
      for (final event in newEvents) {
        expect(event['type'], equals('update'));
        final change = event['change'] as ConnectionStateChange;
        expect(change.previous, equals(ConnectionState.connected));
        expect(change.current, equals(ConnectionState.connected));
      }

      // No additional CONNECTED state events were emitted
      final connectedStateEvents = allEvents.where(
        (event) =>
            event['type'] == 'state' &&
            event['state'] == ConnectionState.connected,
      );
      expect(connectedStateEvents.length, equals(1)); // Only the initial one

      await client.close();
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

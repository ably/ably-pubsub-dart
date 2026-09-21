import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Integration test to verify WebSocket client injection works correctly.
///
/// This test verifies that the new WebSocketClient interface pattern works
/// exactly like the HTTP mock pattern.
void main() {
  group('WebSocket Mock Injection', () {
    // UTS: realtime/unit/RTC17/client-id-attribute-0.5
    test('can inject MockWebSocketClient into PubSubClient', () async {
      // Create mock
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Verify the connection URL is correct
          expect(conn.url.host, contains('main.realtime.ably.net'));
          expect(conn.url.queryParameters['key'], equals('test.key:secret'));

          // Respond with success
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
      );

      // Inject directly into client (same as HTTP pattern!)
      final client = PubSubClient.forTesting(
        options: ClientOptions(key: 'test.key:secret'),
        webSocketClient: mockWs,
      );

      // Wait for connection
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 5),
      );

      // Verify connection state
      expect(client.connection.state, equals(ConnectionState.connected));
      expect(client.connection.id, equals('test-connection-id'));
      expect(client.connection.key, equals('test-connection-key'));
      expect(client.connection.errorReason, isNull);

      // Clean up
      await client.close();
    });

    // UTS: realtime/unit/RTN2e/token-before-websocket-0.1
    test('can use awaitable pattern', () async {
      // Create mock without handler
      final mockWs = MockWebSocketClient();

      // Set up awaitable pattern BEFORE connection
      final connFuture = mockWs.awaitConnectionAttempt();

      // Create client
      final client = PubSubClient.forTesting(
        options: ClientOptions(key: 'test.key:secret'),
        webSocketClient: mockWs,
      );

      // Wait for connection attempt
      final conn = await connFuture;

      // Verify URL
      expect(conn.url.host, contains('main.realtime.ably.net'));

      // Respond to connection
      conn.respondWithSuccess(
        ProtocolMessageHelpers.connected(
          connectionId: 'awaitable-id',
          connectionKey: 'awaitable-key',
        ),
      );

      // Wait for connected state
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 5),
      );

      expect(client.connection.id, equals('awaitable-id'));

      // Clean up
      await client.close();
    });

    // UTS: realtime/unit/RTN2e/token-before-websocket-0.2
    test('can simulate connection failure', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Simulate connection refused
          conn.respondWithRefused();
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'test.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Should reach disconnected state
      await _awaitState(
        client.connection,
        ConnectionState.disconnected,
        timeout: const Duration(seconds: 5),
      );

      expect(client.connection.state, equals(ConnectionState.disconnected));
      expect(client.connection.errorReason, isNotNull);

      // Clean up
      await client.close();
    });

    // UTS: realtime/unit/RTN15h2/token-error-renew-success-0.1
    test('can simulate error response', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // WebSocket connects but server sends ERROR
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40005,
              message: 'Invalid key',
              statusCode: 400,
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

      // Start connection
      client.connect();

      // Should reach failed state
      await _awaitState(
        client.connection,
        ConnectionState.failed,
        timeout: const Duration(seconds: 5),
      );

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40005));
      expect(client.connection.errorReason!.message, equals('Invalid key'));

      // Clean up
      await client.close();
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitState(
  Connection connection,
  ConnectionState targetState, {
  required Duration timeout,
}) async {
  if (connection.state == targetState) {
    return;
  }

  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

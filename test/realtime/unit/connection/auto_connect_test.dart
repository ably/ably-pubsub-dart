import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for Connection auto-connect behavior (RTN3).
///
/// Tests that autoConnect option controls whether a connection is initiated
/// immediately on client creation or only on explicit connect() call.
///
/// Spec: uts/test/realtime/unit/connection/auto_connect_test.md
void main() {
  group('RTN3 - autoConnect true initiates connection immediately', () {
    // UTS: realtime/unit/RTN3/auto-connect-true-0
    test('connection is established without calling connect()', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      // Create client with default autoConnect (true)
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          // autoConnect defaults to true
        ),
        webSocketClient: mockWs,
      );

      // Wait for connection to complete without calling connect()
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      expect(client.connection.state, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN3 - autoConnect false does not initiate connection', () {
    // UTS: realtime/unit/RTN3/auto-connect-false-1
    test('no connection attempt is made on client creation', () async {
      var connectionAttempted = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempted = true;
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      // Create client with autoConnect: false
      PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Wait briefly to confirm no connection attempt is made
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectionAttempted, isFalse);

      mockWs.dispose();
    });
  });

  group('RTN3 - explicit connect after autoConnect false', () {
    // UTS: realtime/unit/RTN3/explicit-connect-after-false-2
    test('calling connect() initiates the connection', () async {
      var connectionAttempted = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempted = true;
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Verify no connection yet
      expect(client.connection.state, equals(ConnectionState.initialized));
      expect(connectionAttempted, isFalse);

      // Explicitly connect
      client.connect();

      // Wait for connection to complete
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      expect(connectionAttempted, isTrue);
      expect(client.connection.state, equals(ConnectionState.connected));

      await client.close();
      mockWs.dispose();
    });
  });
}

Future<void> _awaitConnectionState(
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

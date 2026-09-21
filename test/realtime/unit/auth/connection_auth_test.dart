import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for realtime connection authentication (RTN2e, RTN27b, RSA4, RSA8d).
///
/// These tests verify realtime-specific authentication behavior for establishing
/// WebSocket connections. They focus on how token authentication integrates with
/// the realtime connection lifecycle.
///
/// Key behaviors tested:
/// - Token acquisition occurs before WebSocket connection attempts
/// - Token is included in WebSocket URL query parameters
/// - Token caching and expiry handling for connection attempts
/// - authCallback integration with connection state machine
///
/// Spec: uts/test/realtime/unit/auth/connection_auth_test.md
void main() {
  group('RTN2e/RTN27b - Token obtained before WebSocket connection', () {
    // UTS: realtime/unit/RTN2e/callback-params-include-clientid-2
    test('authCallback invoked before WebSocket connection attempt', () async {
      var callbackInvoked = false;
      var callbackInvokedFirst = false;
      var connectionAttempted = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Check if callback was invoked before this connection attempt
          callbackInvokedFirst = callbackInvoked && !connectionAttempted;
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
            callbackInvoked = true;
            return TokenDetails(
              token: 'callback-provided-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // authCallback was invoked
      expect(callbackInvoked, isTrue);

      // authCallback was invoked BEFORE WebSocket connection attempt
      expect(callbackInvokedFirst, isTrue);

      // Connection succeeded
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN2e/token-before-websocket-0
    test('WebSocket URL contains token from authCallback', () async {
      Uri? capturedUrl;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          capturedUrl = conn.url;

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
            return TokenDetails(
              token: 'my-auth-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // WebSocket URL contains the token from authCallback
      expect(capturedUrl, isNotNull);
      expect(
        capturedUrl!.queryParameters['accessToken'],
        equals('my-auth-token'),
      );

      // WebSocket URL does NOT contain a key parameter (using token auth)
      expect(capturedUrl!.queryParameters['key'], isNull);

      mockWs.dispose();
    });
  });

  group('RTN2e/RTN27b - authCallback error handling', () {
    // UTS: realtime/unit/RTN2e/callback-error-prevents-connect-1
    test('authCallback error prevents WebSocket connection attempt', () async {
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
              message: 'Auth callback failed',
              errorInfo: ErrorInfo(
                code: 40170,
                statusCode: 401,
                message: 'Auth callback failed',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      // Wait for DISCONNECTED or FAILED state
      await _awaitState(
        client.connection,
        ConnectionState.disconnected,
        orState: ConnectionState.failed,
      );

      // No WebSocket connection was attempted
      expect(connectionAttempted, isFalse);

      // Error reason is set
      expect(client.connection.errorReason, isNotNull);

      mockWs.dispose();
    });
  });

  group('RSA12a - authCallback receives TokenParams', () {
    // UTS: realtime/unit/RSA4d/callback-403-causes-failed-0
    test('clientId passed to authCallback in TokenParams', () async {
      TokenParams? receivedParams;

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
            receivedParams = params;
            return TokenDetails(
              token: 'token-for-client',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'my-client-id',
            );
          },
          clientId: 'my-client-id',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // authCallback received TokenParams with clientId
      expect(receivedParams, isNotNull);
      expect(receivedParams!.clientId, equals('my-client-id'));

      mockWs.dispose();
    });
  });

  group('RTN2e - Token caching', () {
    // UTS: realtime/unit/RTN2e/reuse-valid-token-3
    test('valid token reused for subsequent connections', () async {
      var callbackCount = 0;
      var connectionCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-$connectionCount',
              connectionKey: 'key-$connectionCount',
            ),
          );
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            callbackCount++;
            return TokenDetails(
              token: 'reusable-token',
              expires:
                  DateTime.now().millisecondsSinceEpoch + 3600000, // 1 hour
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // First connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(callbackCount, equals(1));

      // Close connection
      client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      // Second connection - should reuse token
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // authCallback was only invoked once (token was reused)
      expect(callbackCount, equals(1));
      expect(connectionCount, equals(2));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RSA4d/callback-403-reauth-causes-failed-1
    test('expired token triggers new authCallback invocation', () async {
      var callbackCount = 0;

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
            callbackCount++;
            return TokenDetails(
              token: 'token-$callbackCount',
              // Token expires immediately (in the past)
              expires: DateTime.now().millisecondsSinceEpoch - 1000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // First connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(callbackCount, equals(1));

      // Close connection
      client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      // Second connection - token expired, should get new one
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // authCallback was invoked twice (token expired)
      expect(callbackCount, equals(2));

      mockWs.dispose();
    });
  });

  group('RSA4 - Auth method selection', () {
    // UTS: realtime/unit/RSA4c2/callback-error-causes-disconnected-0
    test('authCallback takes precedence over key', () async {
      Uri? capturedUrl;
      var callbackInvoked = false;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          capturedUrl = conn.url;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      // Both key and authCallback provided - authCallback should take precedence
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          authCallback: (params) async {
            callbackInvoked = true;
            return TokenDetails(
              token: 'callback-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // authCallback was used
      expect(callbackInvoked, isTrue);

      // URL contains accessToken (not key)
      expect(capturedUrl, isNotNull);
      expect(
        capturedUrl!.queryParameters['accessToken'],
        equals('callback-token'),
      );
      expect(capturedUrl!.queryParameters['key'], isNull);

      mockWs.dispose();
    });

    // UTS: realtime/unit/RSA4c3/callback-error-stays-connected-0
    test('key used for basic auth when no authCallback', () async {
      Uri? capturedUrl;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          capturedUrl = conn.url;
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

      // URL contains key (basic auth)
      expect(capturedUrl, isNotNull);
      expect(
        capturedUrl!.queryParameters['key'],
        equals('appId.keyId:keySecret'),
      );
      expect(capturedUrl!.queryParameters['accessToken'], isNull);

      mockWs.dispose();
    });
  });
}

/// Waits for the connection to reach the target state.
Future<void> _awaitState(
  Connection connection,
  ConnectionState targetState, {
  ConnectionState? orState,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState ||
      (orState != null && connection.state == orState)) {
    return;
  }

  await connection
      .on()
      .firstWhere(
        (change) =>
            change.current == targetState ||
            (orState != null && change.current == orState),
      )
      .timeout(timeout);
}

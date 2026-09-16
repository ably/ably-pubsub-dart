import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for token expiry with non-renewable tokens (RSA4a, RSA4a1,
/// RSA4a2).
///
/// These tests verify the behaviour when a token or tokenDetails is used to
/// instantiate the library without any means to renew the token (no API key,
/// authCallback, or authUrl). The library should treat subsequent token errors
/// as fatal (no retry, transition to FAILED).
///
/// Spec: uts/test/realtime/unit/auth/token_expiry_non_renewable_test.md
void main() {
  group(
      'RSA4a2 - Server token error with non-renewable token transitions to '
      'FAILED', () {
    // UTS: realtime/unit/RSA4a2/token-error-non-renewable-failed-0
    test(
        'token error 40142 with no renewal mechanism causes FAILED with '
        'code 40171', () async {
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

      // Client with token only -- no means to renew
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          tokenDetails: TokenDetails(
            token: 'expired-token',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          ),
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();

      await _awaitState(client.connection, ConnectionState.failed);

      // Connection transitioned to FAILED (not DISCONNECTED -- no retry)
      expect(client.connection.state, equals(ConnectionState.failed));

      // Error reason has code 40171 (non-renewable token error)
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40171));

      // State change event also carries the error
      final failedChanges =
          stateChanges.where((c) => c.current == ConnectionState.failed);
      expect(failedChanges.length, equals(1));
      expect(failedChanges.first.reason, isNotNull);
      expect(failedChanges.first.reason!.code, equals(40171));

      await client.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RSA4a2/token-error-non-renewable-no-retry-1
    test(
        'token error 40140 with no renewal mechanism causes FAILED with '
        'code 40171', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40140,
              statusCode: 401,
              message: 'Token error',
            ),
          );
        },
      );

      // Client with token string only -- no means to renew
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          token: 'non-renewable-token',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      client.connect();

      await _awaitState(client.connection, ConnectionState.failed);

      // Connection transitioned to FAILED
      expect(client.connection.state, equals(ConnectionState.failed));

      // Error reason has code 40171
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40171));

      // State change event also carries the error
      final failedChanges =
          stateChanges.where((c) => c.current == ConnectionState.failed);
      expect(failedChanges.length, equals(1));
      expect(failedChanges.first.reason, isNotNull);
      expect(failedChanges.first.reason!.code, equals(40171));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RSA4a2 - Server token error with non-renewable token does not retry',
      () {
    // UTS: realtime/unit/RSA4a2/token-error-non-renewable-no-retry-1.1
    test('only one connection attempt is made (no retry)', () async {
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40140,
              statusCode: 401,
              message: 'Token error',
            ),
          );
        },
      );

      // Client with token only -- no means to renew
      final client = PubSubClient.forTesting(
        options: ClientOptions(
          token: 'non-renewable-token',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      await _awaitState(client.connection, ConnectionState.failed);

      // Only one connection attempt was made (no retry)
      expect(connectionAttemptCount, equals(1));

      // Connection is in FAILED state
      expect(client.connection.state, equals(ConnectionState.failed));

      // Error code is 40171
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40171));

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RSA4a2 - Token errors in range 40140-40149 are treated as token '
      'errors', () {
    for (final tokenErrorCode in [40140, 40142, 40144, 40149]) {
      // UTS: realtime/unit/RSA4a1/non-renewable-token-logs-warning-0
      test('token error $tokenErrorCode causes FAILED with code 40171',
          () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithError(
              ProtocolMessageHelpers.error(
                code: tokenErrorCode,
                statusCode: 401,
                message: 'Token error $tokenErrorCode',
              ),
            );
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            token: 'non-renewable-token',
            autoConnect: false,
          ),
          webSocketClient: mockWs,
        );

        client.connect();

        await _awaitState(client.connection, ConnectionState.failed);

        expect(client.connection.state, equals(ConnectionState.failed));
        expect(client.connection.errorReason, isNotNull);
        expect(client.connection.errorReason!.code, equals(40171));

        await client.close();
        mockWs.dispose();
      });
    }
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

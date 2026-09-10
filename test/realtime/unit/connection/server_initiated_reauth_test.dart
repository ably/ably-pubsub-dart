import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Server-Initiated Re-authentication Tests
///
/// Spec points: RTN22, RTN22a
///
/// Tests that when Ably sends an AUTH protocol message to a connected client,
/// the client obtains a new token via the configured auth mechanism and sends
/// an AUTH protocol message back containing the new token.
///
/// RTN22a covers the fallback: if the client does not re-authenticate within
/// an acceptable period, Ably forcibly disconnects via a DISCONNECTED message
/// with a token error code (40140-40149), triggering RTN15h token-error
/// recovery.
///
/// Spec: uts/test/realtime/unit/connection/server_initiated_reauth_test.md
void main() {
  group('RTN22 - Server sends AUTH, client re-authenticates', () {
    // UTS: realtime/unit/RTN22/stays-connected-during-reauth-1
    test('receives AUTH from server, obtains new token, sends AUTH back',
        () async {
      var authCallbackCount = 0;
      final capturedAuthMessages = <ProtocolMessage>[];

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.auth) {
            capturedAuthMessages.add(msg);
            // Respond with CONNECTED (update) after receiving AUTH
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key-2',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            return TokenDetails(
              token: 'token-$authCallbackCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Record state changes during reauth
      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      // Server requests re-authentication
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(action: ProtocolAction.auth),
      );

      // Wait for the UPDATE event that signals reauth completion
      await _awaitCondition(
        () => stateChanges.any((c) => c.event == ConnectionEvent.update),
      );

      // authCallback was called twice: once for initial connect, once for reauth
      expect(authCallbackCount, equals(2));

      // Client sent AUTH message back with new token
      expect(capturedAuthMessages.length, equals(1));
      expect(capturedAuthMessages[0].auth, isNotNull);
      expect(
        (capturedAuthMessages[0].auth as Map)['accessToken'],
        equals('token-2'),
      );

      // Connection stayed CONNECTED throughout (no state transitions, only
      // UPDATE)
      final connectedToOther =
          stateChanges.where((c) => c.current != ConnectionState.connected);
      expect(connectedToOther, isEmpty);

      // UPDATE event was emitted (RTN24)
      final updateEvents =
          stateChanges.where((c) => c.event == ConnectionEvent.update).toList();
      expect(updateEvents.length, equals(1));

      mockWs.dispose();
    });
  });

  group('RTN22 - Connection remains CONNECTED during server-initiated reauth',
      () {
    // UTS: realtime/unit/RTN22/server-auth-triggers-reauth-0
    test('connection state does not change during server-initiated reauth',
        () async {
      var authCallbackCount = 0;

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          // Auto-respond to AUTH with CONNECTED
          if (msg.action == ProtocolAction.auth) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.connected(
                connectionId: 'conn-1',
                connectionKey: 'key-1-updated',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            return TokenDetails(
              token: 'reauth-token-$authCallbackCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      // Server sends AUTH
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(action: ProtocolAction.auth),
      );

      // Wait for UPDATE event
      await _awaitCondition(() => stateChanges.isNotEmpty);

      // Connection never left CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // Only an UPDATE event, no state change events
      expect(stateChanges.length, equals(1));
      expect(stateChanges[0].event, equals(ConnectionEvent.update));
      expect(stateChanges[0].current, equals(ConnectionState.connected));
      expect(stateChanges[0].previous, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTN22a - Forced disconnect on reauth failure', () {
    // UTS: realtime/unit/RTN22a/forced-disconnect-reauth-failure-0
    test('auth fails during server-initiated reauth, server force disconnects',
        () async {
      var authCallbackCount = 0;

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          // Do NOT auto-respond to AUTH — simulating reauth failure
          // (the client sends AUTH but it doesn't succeed in time)
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            if (authCallbackCount == 1) {
              // Initial auth succeeds
              return TokenDetails(
                token: 'initial-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            }
            // Reauth fails
            throw const AblyException(
              message: 'Auth provider unavailable',
              errorInfo: ErrorInfo(
                code: 40170,
                statusCode: 401,
                message: 'Auth provider unavailable',
              ),
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      // Server sends AUTH requesting reauth (which will fail in authCallback)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(action: ProtocolAction.auth),
      );

      // Give time for the async reauth to fail
      await _awaitCondition(
        () => authCallbackCount >= 2,
      );

      // Since reauth failed (RSA4c3), the client stays CONNECTED with
      // existing token. But the server will eventually force disconnect.
      // Simulate the server sending a DISCONNECTED with token error
      // (RTN22a: server force disconnects after reauth timeout).
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(
            message: 'Token expired, reauth timed out',
            code: 40142,
            statusCode: 401,
          ),
        ),
      );

      // Wait for DISCONNECTED state
      await _awaitState(client.connection, ConnectionState.disconnected);

      // Verify the DISCONNECTED transition has the token error
      final disconnectedChange = stateChanges.firstWhere(
        (c) => c.current == ConnectionState.disconnected,
      );
      expect(disconnectedChange.reason, isNotNull);
      expect(disconnectedChange.reason!.code, equals(40142));

      mockWs.dispose();
    });

    test(
        'server DISCONNECTED with token error code triggers DISCONNECTED state',
        () async {
      var authCallbackCount = 0;

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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            return TokenDetails(
              token: 'recovery-token-$authCallbackCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          },
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      // Server forcibly disconnects with token error (simulating reauth
      // timeout)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(
            message: 'Token expired',
            code: 40142,
            statusCode: 401,
          ),
        ),
      );

      // Wait for client to transition to DISCONNECTED
      await _awaitState(client.connection, ConnectionState.disconnected);

      // Client transitioned to DISCONNECTED with the token error
      final disconnectedChange = stateChanges.firstWhere(
        (c) => c.current == ConnectionState.disconnected,
      );
      expect(disconnectedChange.reason, isNotNull);
      expect(disconnectedChange.reason!.code, equals(40142));

      // The client should attempt to reconnect (RTN15h token-error recovery
      // will obtain a new token and reconnect)
      mockWs.dispose();
    });
  });
}

/// Waits for the connection to reach the target state.
Future<void> _awaitState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) return;
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

/// Waits for a condition to become true, polling with microtask yields.
Future<void> _awaitCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Realtime Authorize Tests
///
/// Spec points: RTC8, RTC8a, RTC8a1, RTC8a2, RTC8a3, RTC8b, RTC8b1, RTC8c
///
/// Tests in-band reauthorization via `auth.authorize()` on a realtime client.
///
/// Spec: uts/test/realtime/unit/auth/realtime_authorize.md
void main() {
  group('RTC8a - authorize() on CONNECTED sends AUTH protocol message', () {
    // UTS: realtime/unit/RTC8a/authorize-connected-sends-auth-0
    test('sends AUTH with new token and resolves with TokenDetails', () async {
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
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key-2',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Track state changes during reauth
      final stateChanges = <ConnectionStateChange>[];
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      final tokenDetails = await client.auth.authorize();

      // authCallback was called twice (initial connect + authorize)
      expect(authCallbackCount, equals(2));

      // An AUTH protocol message was sent
      expect(capturedAuthMessages.length, equals(1));

      // AUTH message contains the new token
      expect(capturedAuthMessages[0].auth, isNotNull);

      // authorize() resolved with the new token
      expect(tokenDetails!.token, equals('token-2'));

      // No state transitions occurred — connection stayed CONNECTED throughout
      // (UPDATE events are expected but are not state transitions)
      final stateTransitions =
          stateChanges.where((c) => c.current != c.previous).toList();
      expect(stateTransitions, isEmpty);
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTC8a1 - Successful reauth emits UPDATE event', () {
    // UTS: realtime/unit/RTC8a1/successful-reauth-update-event-0
    test('emits UPDATE (not CONNECTED state change) and updates details',
        () async {
      var authCallbackCount = 0;

      late MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-1',
              connectionKey: 'connection-key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.auth) {
            // Server responds with CONNECTED after reauth (RTN24) —
            // same connectionId, connectionDetails may be updated.
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id-1',
                connectionKey: 'connection-key-1',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Track events
      final updateEvents = <ConnectionStateChange>[];
      final connectedEvents = <ConnectionStateChange>[];
      final stateChanges = <ConnectionStateChange>[];

      client.connection.on(ConnectionEvent.update).listen((change) {
        updateEvents.add(change);
      });
      client.connection.on(ConnectionEvent.connected).listen((change) {
        connectedEvents.add(change);
      });
      client.connection.on().listen((change) {
        stateChanges.add(change);
      });

      await client.auth.authorize();

      // UPDATE event was emitted
      expect(updateEvents.length, equals(1));
      expect(updateEvents[0].previous, equals(ConnectionState.connected));
      expect(updateEvents[0].current, equals(ConnectionState.connected));

      // No additional CONNECTED state event was emitted
      expect(connectedEvents, isEmpty);

      // No state transitions occurred (stayed CONNECTED throughout)
      // (UPDATE events appear in the stream but are not state transitions)
      final stateTransitions =
          stateChanges.where((c) => c.current != c.previous).toList();
      expect(stateTransitions, isEmpty);

      // Connection identity unchanged — RTN24 only overrides
      // connectionDetails, not the top-level connectionId
      expect(client.connection.id, equals('connection-id-1'));
      expect(client.connection.key, equals('connection-key-1'));

      mockWs.dispose();
    });
  });

  group('RTC8a1 - Capability downgrade causes channel FAILED', () {
    // UTS: realtime/unit/RTC8a1/capability-downgrade-channel-failed-1
    test('channel enters FAILED on channel-level ERROR after reauth', () async {
      var authCallbackCount = 0;

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
          if (msg.action == ProtocolAction.attach &&
              msg.channel == 'private-channel') {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: 'private-channel'),
            );
          } else if (msg.action == ProtocolAction.auth) {
            // Reauth succeeds at connection level
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key-2',
              ),
            );
            // Then server sends channel-level ERROR (capability downgrade)
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.error(
                code: 40160,
                statusCode: 401,
                message: 'Channel denied access based on given capability',
                channel: 'private-channel',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Attach a channel
      final channel = client.channels.get('private-channel');
      channel.attach();
      await _awaitChannelState(channel, ChannelState.attached);

      // Track channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen((change) {
        channelStateChanges.add(change);
      });

      // Call authorize (to downgrade capabilities)
      await client.auth.authorize();
      await _awaitChannelState(channel, ChannelState.failed);

      // Channel entered FAILED state
      expect(channel.state, equals(ChannelState.failed));

      // Channel state change event includes the error reason
      final failedChanges =
          channelStateChanges.where((c) => c.current == ChannelState.failed);
      expect(failedChanges.length, equals(1));
      expect(failedChanges.first.reason, isNotNull);
      expect(failedChanges.first.reason!.code, equals(40160));
      expect(failedChanges.first.reason!.statusCode, equals(401));

      // Connection remains CONNECTED (channel-level ERROR doesn't close it)
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTC8a2 - Failed reauth transitions connection to FAILED', () {
    // UTS: realtime/unit/RTC8a2/failed-reauth-connection-failed-0
    test('incompatible clientId causes FAILED state', () async {
      var authCallbackCount = 0;

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
            mockWs.activeConnection!.sendToClientAndClose(
              ProtocolMessageHelpers.error(
                code: 40012,
                statusCode: 400,
                message: 'Incompatible clientId',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Track state changes
      final stateChanges = <ConnectionState>[];
      client.connection.on().listen((change) {
        stateChanges.add(change.current);
      });

      try {
        await client.auth.authorize();
        fail('Expected authorize to fail');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).code, equals(40012));
      }

      // Connection transitioned to FAILED
      expect(client.connection.state, equals(ConnectionState.failed));

      // Error reason is set on the connection
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40012));

      mockWs.dispose();
    });
  });

  group('RTC8a3 - authorize() completes only after server response', () {
    // UTS: realtime/unit/RTC8a3/authorize-completes-after-response-0
    test('future does not resolve until server responds', () async {
      var authCallbackCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
        // No onMessageFromClient — we'll respond manually via await pattern
      );

      final client = PubSubClient.forTesting(
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

      // Start authorize — do NOT await
      var authorizeCompleted = false;
      final authorizeFuture = client.auth.authorize();
      // ignore: unawaited_futures
      authorizeFuture.then((_) {
        authorizeCompleted = true;
      });

      // Wait for the client to send the AUTH message
      final authMsg = await mockWs.awaitNextMessageFromClient();
      expect(authMsg.action, equals(ProtocolAction.auth));

      // authorize() should NOT have completed yet (server hasn't responded)
      expect(authorizeCompleted, isFalse);

      // Now send the server response
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.connected(
          connectionId: 'connection-id',
          connectionKey: 'connection-key-2',
        ),
      );

      // Now await completion
      final tokenDetails = await authorizeFuture;

      expect(authorizeCompleted, isTrue);
      expect(tokenDetails!.token, equals('token-2'));

      mockWs.dispose();
    });
  });

  group('RTC8b - authorize() while CONNECTING halts current attempt', () {
    // UTS: realtime/unit/RTC8b/authorize-connecting-halts-attempt-0
    test('cancels current attempt and reconnects with new token', () async {
      var authCallbackCount = 0;
      final capturedWsUrls = <Uri>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          capturedWsUrls.add(conn.url);

          if (connectionAttemptCount == 1) {
            // First attempt: accept WebSocket but don't send CONNECTED
            // (client stays in CONNECTING)
            conn.respondWithSilence();
          } else {
            // Second attempt (after authorize): complete normally
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Start connection — will enter CONNECTING
      client.connect();
      await _awaitState(client.connection, ConnectionState.connecting);

      // Call authorize while CONNECTING
      final tokenDetails = await client.auth.authorize();

      // authorize() completed successfully
      expect(tokenDetails!.token, equals('token-2'));

      // Connection is now CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // authCallback was called twice (initial + authorize)
      expect(authCallbackCount, equals(2));

      // Two connection attempts were made
      expect(connectionAttemptCount, equals(2));

      // Second attempt used the new token
      expect(
        capturedWsUrls[1].queryParameters['accessToken'],
        equals('token-2'),
      );

      mockWs.dispose();
    });
  });

  group('RTC8b1 - authorize() while CONNECTING fails on FAILED state', () {
    // UTS: realtime/unit/RTC8b1/authorize-connecting-fails-on-failed-0
    test('authorize future completes with error if connection enters FAILED',
        () async {
      var authCallbackCount = 0;
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // First attempt: keep in CONNECTING
            conn.respondWithSilence();
          } else {
            // Second attempt (after authorize): fail with fatal error
            conn.respondWithError(
              ProtocolMessageHelpers.error(
                code: 40101,
                statusCode: 401,
                message: 'Invalid credentials',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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
      await _awaitState(client.connection, ConnectionState.connecting);

      // Call authorize while CONNECTING — should fail
      try {
        await client.auth.authorize();
        fail('Expected authorize to fail');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).code, equals(40101));
      }

      // Connection is in FAILED state
      expect(client.connection.state, equals(ConnectionState.failed));

      mockWs.dispose();
    });
  });

  group('RTC8c - authorize() from non-connected states', () {
    // UTS: realtime/unit/RTC8c/authorize-disconnected-initiates-connection-0
    test('authorize() from INITIALIZED initiates connection', () async {
      var authCallbackCount = 0;
      final capturedWsUrls = <Uri>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          capturedWsUrls.add(conn.url);
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      // Client starts in INITIALIZED (autoConnect: false, connect() not called)
      final client = PubSubClient.forTesting(
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

      // Verify client is not connected
      expect(client.connection.state, equals(ConnectionState.initialized));

      // Track state changes
      final stateChanges = <ConnectionState>[];
      client.connection.on().listen((change) {
        stateChanges.add(change.current);
      });

      // Call authorize from non-connected state
      final tokenDetails = await client.auth.authorize();

      // authorize() completed successfully
      expect(tokenDetails!.token, equals('token-1'));

      // Connection is now CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // State transitions included CONNECTING
      expect(stateChanges, contains(ConnectionState.connecting));
      expect(stateChanges, contains(ConnectionState.connected));

      // Connection used the token from authorize
      expect(
        capturedWsUrls[0].queryParameters['accessToken'],
        equals('token-1'),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC8c/authorize-failed-initiates-connection-1
    test('authorize() from FAILED recovers connection', () async {
      var authCallbackCount = 0;
      final capturedWsUrls = <Uri>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          capturedWsUrls.add(conn.url);

          if (connectionAttemptCount == 1) {
            // First attempt: fail with fatal error
            conn.respondWithError(
              ProtocolMessageHelpers.error(
                code: 40101,
                statusCode: 401,
                message: 'Invalid credentials',
              ),
            );
          } else {
            // Second attempt (after authorize): succeed
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Connect — will fail
      client.connect();
      await _awaitState(client.connection, ConnectionState.failed);

      // Track state changes from FAILED onwards
      final stateChanges = <ConnectionState>[];
      client.connection.on().listen((change) {
        stateChanges.add(change.current);
      });

      // Call authorize from FAILED state
      final tokenDetails = await client.auth.authorize();

      // authorize() completed successfully
      expect(tokenDetails!.token, equals('token-2'));

      // Connection recovered to CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // State transitions went through CONNECTING
      expect(stateChanges, contains(ConnectionState.connecting));
      expect(stateChanges, contains(ConnectionState.connected));

      // Second connection used the new token
      expect(
        capturedWsUrls[1].queryParameters['accessToken'],
        equals('token-2'),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC8c/authorize-closed-initiates-connection-2
    test('authorize() from CLOSED initiates connection', () async {
      var authCallbackCount = 0;
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id-$connectionAttemptCount',
              connectionKey: 'connection-key-$connectionAttemptCount',
            ),
          );
        },
      );

      final client = PubSubClient.forTesting(
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

      // Connect, then close
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      client.close();
      await _awaitState(client.connection, ConnectionState.closed);

      // Call authorize from CLOSED state
      final tokenDetails = await client.auth.authorize();

      // authorize() completed successfully
      expect(tokenDetails!.token, equals('token-2'));

      // Connection is now CONNECTED again
      expect(client.connection.state, equals(ConnectionState.connected));

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

/// Waits for the channel to reach the target state.
Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (channel.state == targetState) return;
  await channel
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

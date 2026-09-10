import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel subscribe/unsubscribe
/// (RTL7, RTL8, RTL17, RTL22, MFI1, MFI2).
///
/// These tests use mocked WebSocket to verify message subscription,
/// unsubscription, implicit attach, echoMessages filtering,
/// the RTL17 rule that messages are only delivered when ATTACHED, and
/// RTL22 MessageFilter-based subscriptions.
///
/// Spec: specification/uts/realtime/unit/channels/channel_subscribe.md
void main() {
  // ---------------------------------------------------------------------------
  // RTL7a - Subscribe with no name receives all messages
  // ---------------------------------------------------------------------------

  group('RTL7a - Subscribe with no name receives all messages', () {
    // UTS: realtime/unit/RTL7a/multiple-messages-per-protocol-1
    test('delivers all messages regardless of name', () async {
      final channelName = testChannelName('RTL7a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      // Send messages with different names
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'event1', data: 'data1')],
        ),
      );
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'event2', data: 'data2')],
        ),
      );
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(data: 'data3')],
        ),
      );

      expect(received, hasLength(3));
      expect(received[0].name, equals('event1'));
      expect(received[0].data, equals('data1'));
      expect(received[1].name, equals('event2'));
      expect(received[1].data, equals('data2'));
      expect(received[2].name, isNull);
      expect(received[2].data, equals('data3'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7a/subscribe-all-messages-0
    test('receives multiple messages from a single ProtocolMessage', () async {
      final channelName = testChannelName('RTL7a-multi');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'batch1', data: 'first'),
            const Message(name: 'batch2', data: 'second'),
            const Message(name: 'batch3', data: 'third'),
          ],
        ),
      );

      expect(received, hasLength(3));
      expect(received[0].name, equals('batch1'));
      expect(received[1].name, equals('batch2'));
      expect(received[2].name, equals('batch3'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL7b - Subscribe with name only receives matching messages
  // ---------------------------------------------------------------------------

  group('RTL7b - Subscribe with name only receives matching messages', () {
    // UTS: realtime/unit/RTL7b/name-filtered-subscribe-0
    test('filters messages by name', () async {
      final channelName = testChannelName('RTL7b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      channel.subscribe((message) => received.add(message), name: 'target');

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'other', data: 'should-not-receive')],
        ),
      );
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'target', data: 'should-receive')],
        ),
      );
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(data: 'no-name-should-not-receive')],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].name, equals('target'));
      expect(received[0].data, equals('should-receive'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7b/multiple-name-subscriptions-1
    test('multiple name-specific subscriptions are independent', () async {
      final channelName = testChannelName('RTL7b-multi');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final alphaMessages = <Message>[];
      final betaMessages = <Message>[];

      channel.subscribe(
        (message) => alphaMessages.add(message),
        name: 'alpha',
      );
      channel.subscribe(
        (message) => betaMessages.add(message),
        name: 'beta',
      );

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'alpha', data: 'a1'),
            const Message(name: 'beta', data: 'b1'),
            const Message(name: 'alpha', data: 'a2'),
            const Message(name: 'gamma', data: 'g1'),
          ],
        ),
      );

      expect(alphaMessages, hasLength(2));
      expect(alphaMessages[0].data, equals('a1'));
      expect(alphaMessages[1].data, equals('a2'));

      expect(betaMessages, hasLength(1));
      expect(betaMessages[0].data, equals('b1'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL7g - Subscribe triggers implicit attach
  // ---------------------------------------------------------------------------

  group('RTL7g - Subscribe triggers implicit attach', () {
    // UTS: realtime/unit/RTL7g/implicit-attach-initialized-0
    test('from INITIALIZED state', () async {
      final channelName = testChannelName('RTL7g');
      var attachMessageCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessageCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Default attachOnSubscribe is true
      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      expect(channel.state, equals(ChannelState.initialized));

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      await _awaitChannelState(channel, ChannelState.attached);

      expect(channel.state, equals(ChannelState.attached));
      expect(attachMessageCount, equals(1));

      // Verify the listener was registered by sending a message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'test',
          data: 'hello',
        ),
      );

      expect(received, hasLength(1));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7g/implicit-attach-detached-1
    test('from DETACHED state', () async {
      final channelName = testChannelName('RTL7g-detached');
      var attachMessageCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessageCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      await channel.attach();
      await channel.detach();
      expect(channel.state, equals(ChannelState.detached));
      expect(attachMessageCount, equals(1));

      // Subscribe should trigger implicit attach from DETACHED
      channel.subscribe((message) {});

      await _awaitChannelState(channel, ChannelState.attached);

      expect(channel.state, equals(ChannelState.attached));
      expect(attachMessageCount, equals(2));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7g/listener-registered-attach-fails-2
    test('listener registered even if implicit attach fails', () async {
      final channelName = testChannelName('RTL7g-fail');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            if (attachCount == 1) {
              // First attach fails
              mockWs.activeConnection!.sendToClient(
                ProtocolMessage(
                  action: ProtocolAction.error,
                  channel: channelName,
                  error: const ErrorInfo(
                    code: 40160,
                    statusCode: 401,
                    message: 'Not permitted',
                  ),
                ),
              );
            } else {
              // Subsequent attaches succeed
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      // Wait for channel to enter FAILED from the rejected attach
      await _awaitChannelState(channel, ChannelState.failed);

      // Re-attach — the listener should still be registered
      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'test',
          data: 'after-reattach',
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].data, equals('after-reattach'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7g/no-attach-when-attached-3
    test('does not attach when already attached', () async {
      final channelName = testChannelName('RTL7g-already');
      var attachMessageCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessageCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      await channel.attach();
      expect(attachMessageCount, equals(1));

      // Subscribe on already-attached channel — no additional attach
      channel.subscribe((message) {});

      expect(channel.state, equals(ChannelState.attached));
      expect(attachMessageCount, equals(1));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL7g/no-attach-when-attaching-4
    test('does not attach when already attaching', () async {
      final channelName = testChannelName('RTL7g-attaching');
      var attachMessageCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessageCount++;
            // Don't respond — leave channel in ATTACHING
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Start attach but don't complete it
      unawaited(channel.attach());
      await _awaitChannelState(channel, ChannelState.attaching);
      expect(attachMessageCount, equals(1));

      // Subscribe while attaching — should not trigger another attach
      channel.subscribe((message) {});

      expect(channel.state, equals(ChannelState.attaching));
      expect(attachMessageCount, equals(1));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL7h - Subscribe does not attach when attachOnSubscribe is false
  // ---------------------------------------------------------------------------

  group('RTL7h - Subscribe does not attach when attachOnSubscribe is false',
      () {
    // UTS: realtime/unit/RTL7h/no-attach-on-subscribe-0
    test('channel remains INITIALIZED', () async {
      final channelName = testChannelName('RTL7h');
      var attachMessageCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessageCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      expect(channel.state, equals(ChannelState.initialized));

      channel.subscribe((message) {});

      // Channel should remain INITIALIZED — no attach triggered
      expect(channel.state, equals(ChannelState.initialized));
      expect(attachMessageCount, equals(0));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL17 - Messages not delivered when channel is not ATTACHED
  // ---------------------------------------------------------------------------

  group('RTL17 - Messages not delivered when channel is not ATTACHED', () {
    // UTS: realtime/unit/RTL17/no-delivery-when-not-attached-0
    test('messages suppressed while ATTACHING', () async {
      final channelName = testChannelName('RTL17');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Don't respond — leave channel in ATTACHING
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      // Start attach but don't complete it
      unawaited(channel.attach());
      await _awaitChannelState(channel, ChannelState.attaching);

      // Server sends a message while channel is still ATTACHING
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'premature', data: 'should-not-deliver'),
          ],
        ),
      );

      expect(received, isEmpty);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL7f - Messages not echoed when echoMessages is false
  // ---------------------------------------------------------------------------

  group('RTL7f - Messages not echoed when echoMessages is false', () {
    // UTS: realtime/unit/RTL7f/no-echo-messages-0
    test('filters messages from own connection', () async {
      final channelName = testChannelName('RTL7f');
      const connectionId = 'conn-self-123';

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: connectionId,
              connectionKey: 'key-456',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          echoMessages: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      // Server echoes back a message with this connection's connectionId
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          connectionId: connectionId,
          messages: [const Message(name: 'echo', data: 'from-self')],
        ),
      );

      // Server sends a message from a different connection
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          connectionId: 'conn-other-789',
          messages: [const Message(name: 'remote', data: 'from-other')],
        ),
      );

      // Only the message from the other connection should be delivered
      expect(received, hasLength(1));
      expect(received[0].name, equals('remote'));
      expect(received[0].data, equals('from-other'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL8a - Unsubscribe specific listener from all messages
  // ---------------------------------------------------------------------------

  group('RTL8a - Unsubscribe specific listener', () {
    // UTS: realtime/unit/RTL8a/unsubscribe-noop-not-subscribed-1
    test('stops delivering to unsubscribed listener', () async {
      final channelName = testChannelName('RTL8a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final messagesA = <Message>[];
      final messagesB = <Message>[];

      void listenerA(Message message) => messagesA.add(message);
      void listenerB(Message message) => messagesB.add(message);

      channel.subscribe(listenerA);
      channel.subscribe(listenerB);

      // Both receive first message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'msg1',
          data: 'first',
        ),
      );
      expect(messagesA, hasLength(1));
      expect(messagesB, hasLength(1));

      // Unsubscribe listener A
      channel.unsubscribe(listener: listenerA);

      // Only listener B should receive second message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'msg2',
          data: 'second',
        ),
      );

      expect(messagesA, hasLength(1)); // Did not receive second
      expect(messagesB, hasLength(2)); // Received both
      expect(messagesB[1].name, equals('msg2'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL8a/unsubscribe-specific-listener-0
    test('unsubscribing non-subscribed listener is no-op', () async {
      final channelName = testChannelName('RTL8a-noop');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      void activeListener(Message message) => received.add(message);
      void unusedListener(Message message) {}

      channel.subscribe(activeListener);

      // Unsubscribe a listener that was never subscribed — should be no-op
      channel.unsubscribe(listener: unusedListener);

      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'test',
          data: 'still-works',
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].data, equals('still-works'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL8b - Unsubscribe listener from specific name
  // ---------------------------------------------------------------------------

  group('RTL8b - Unsubscribe listener from specific name', () {
    // UTS: realtime/unit/RTL8b/unsubscribe-named-listener-0
    test('removes only the name-specific subscription', () async {
      final channelName = testChannelName('RTL8b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final received = <Message>[];
      void listener(Message message) => received.add(message);

      // Subscribe to two different names with the same listener
      channel.subscribe(listener, name: 'alpha');
      channel.subscribe(listener, name: 'beta');

      // Both subscriptions active
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'alpha', data: 'a1'),
            const Message(name: 'beta', data: 'b1'),
          ],
        ),
      );
      expect(received, hasLength(2));

      // Unsubscribe only from "alpha"
      channel.unsubscribe(listener: listener, name: 'alpha');

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'alpha', data: 'a2'),
            const Message(name: 'beta', data: 'b2'),
          ],
        ),
      );

      // "alpha" unsubscribed but "beta" still active
      expect(received, hasLength(3));
      expect(received[2].name, equals('beta'));
      expect(received[2].data, equals('b2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL8c - Unsubscribe with no arguments removes all listeners
  // ---------------------------------------------------------------------------

  group('RTL8c - Unsubscribe with no arguments removes all listeners', () {
    // UTS: realtime/unit/RTL8c/unsubscribe-all-listeners-0
    test('no listeners receive messages after unsubscribe()', () async {
      final channelName = testChannelName('RTL8c');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final messagesAll = <Message>[];
      final messagesNamed = <Message>[];

      channel.subscribe((message) => messagesAll.add(message));
      channel.subscribe(
        (message) => messagesNamed.add(message),
        name: 'specific',
      );

      // Both listeners receive
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'specific',
          data: 'first',
        ),
      );
      expect(messagesAll, hasLength(1));
      expect(messagesNamed, hasLength(1));

      // Unsubscribe all
      channel.unsubscribe();

      // No listeners should receive
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'specific', data: 'second'),
            const Message(name: 'other', data: 'third'),
          ],
        ),
      );

      expect(messagesAll, hasLength(1)); // No new messages
      expect(messagesNamed, hasLength(1)); // No new messages

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL22a - Subscribe with MessageFilter matching name
  // ---------------------------------------------------------------------------

  group('RTL22a - Subscribe with MessageFilter matching name', () {
    // UTS: realtime/unit/RTL22a/filter-matching-name-0
    test('delivers only messages whose name matches the filter', () async {
      final channelName = testChannelName('RTL22a-name');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final filteredMessages = <Message>[];
      const filter = MessageFilter(name: 'target-event');
      channel.subscribeFilter(
        filter,
        (message) => filteredMessages.add(message),
      );

      // Message with matching name
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'target-event', data: 'match-1')],
        ),
      );

      // Message with different name
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'other-event', data: 'no-match')],
        ),
      );

      // Another message with matching name
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'target-event', data: 'match-2')],
        ),
      );

      // Message with no name
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(data: 'no-name')],
        ),
      );

      expect(filteredMessages, hasLength(2));
      expect(filteredMessages[0].name, equals('target-event'));
      expect(filteredMessages[0].data, equals('match-1'));
      expect(filteredMessages[1].name, equals('target-event'));
      expect(filteredMessages[1].data, equals('match-2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL22a - Subscribe with MessageFilter matching extras.ref.timeserial
  // ---------------------------------------------------------------------------

  group('RTL22a - Subscribe with MessageFilter matching refTimeserial', () {
    // UTS: realtime/unit/RTL22a/filter-matching-ref-timeserial-1
    test('delivers only messages whose extras.ref.timeserial matches',
        () async {
      final channelName = testChannelName('RTL22a-ref-timeserial');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final filteredMessages = <Message>[];
      const filter = MessageFilter(refTimeserial: 'abc123@1700000000000-0');
      channel.subscribeFilter(
        filter,
        (message) => filteredMessages.add(message),
      );

      // Message with matching extras.ref.timeserial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'reply',
              data: 'match',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'abc123@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message with different extras.ref.timeserial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'reply',
              data: 'no-match',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'xyz789@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message with no extras.ref at all
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'plain', data: 'no-ref')],
        ),
      );

      // Another message with matching extras.ref.timeserial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'reaction',
              data: 'match-2',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'abc123@1700000000000-0',
                    'type': 'com.ably.reaction',
                  },
                },
              ),
            ),
          ],
        ),
      );

      expect(filteredMessages, hasLength(2));
      expect(filteredMessages[0].data, equals('match'));
      expect(filteredMessages[1].data, equals('match-2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL22b - Subscribe with MessageFilter isRef false
  // ---------------------------------------------------------------------------

  group(
      'RTL22b - Subscribe with MessageFilter isRef false delivers only '
      'messages without extras.ref', () {
    // UTS: realtime/unit/RTL22b/filter-isref-false-0
    test('filters out messages with extras.ref', () async {
      final channelName = testChannelName('RTL22b-isref-false');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final filteredMessages = <Message>[];
      const filter = MessageFilter(isRef: false);
      channel.subscribeFilter(
        filter,
        (message) => filteredMessages.add(message),
      );

      // Message WITHOUT extras.ref (no extras at all)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'plain', data: 'no-extras')],
        ),
      );

      // Message WITH extras.ref -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'reply',
              data: 'has-ref',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'abc123@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message with extras but no ref field -- should be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'annotated',
              data: 'extras-no-ref',
              extras: MessageExtras(
                data: {
                  'headers': {'custom-key': 'custom-value'},
                },
              ),
            ),
          ],
        ),
      );

      // Another message WITH extras.ref -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'reaction',
              data: 'also-has-ref',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'xyz789@1700000000000-0',
                    'type': 'com.ably.reaction',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Only messages without extras.ref should be delivered
      expect(filteredMessages, hasLength(2));
      expect(filteredMessages[0].name, equals('plain'));
      expect(filteredMessages[0].data, equals('no-extras'));
      expect(filteredMessages[1].name, equals('annotated'));
      expect(filteredMessages[1].data, equals('extras-no-ref'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL22c - Subscribe with MessageFilter matching multiple criteria
  // ---------------------------------------------------------------------------

  group(
      'RTL22c - Subscribe with MessageFilter matching multiple criteria '
      '(name + refType)', () {
    // UTS: realtime/unit/RTL22c/filter-multiple-criteria-0
    test('delivers only messages matching ALL criteria', () async {
      final channelName = testChannelName('RTL22c-multi');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final filteredMessages = <Message>[];
      const filter = MessageFilter(name: 'comment', refType: 'com.ably.reply');
      channel.subscribeFilter(
        filter,
        (message) => filteredMessages.add(message),
      );

      // Message matching BOTH name AND refType -- should be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'comment',
              data: 'both-match',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'abc@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message matching name but NOT refType -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'comment',
              data: 'name-only',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'def@1700000000000-0',
                    'type': 'com.ably.reaction',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message matching refType but NOT name -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'update',
              data: 'type-only',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'ghi@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Message matching NEITHER -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'update', data: 'neither')],
        ),
      );

      // Another message matching BOTH -- should be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(
              name: 'comment',
              data: 'both-match-2',
              extras: MessageExtras(
                data: {
                  'ref': {
                    'timeserial': 'jkl@1700000000000-0',
                    'type': 'com.ably.reply',
                  },
                },
              ),
            ),
          ],
        ),
      );

      // Only messages matching ALL criteria
      expect(filteredMessages, hasLength(2));
      expect(filteredMessages[0].data, equals('both-match'));
      expect(filteredMessages[1].data, equals('both-match-2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL22a, MFI2e - Subscribe with MessageFilter matching clientId
  // ---------------------------------------------------------------------------

  group('RTL22a, MFI2e - Subscribe with MessageFilter matching clientId', () {
    // UTS: realtime/unit/RTL22a/filter-matching-clientid-2
    test('delivers only messages whose clientId matches the filter', () async {
      final channelName = testChannelName('RTL22a-clientid');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final filteredMessages = <Message>[];
      const filter = MessageFilter(clientId: 'user-42');
      channel.subscribeFilter(
        filter,
        (message) => filteredMessages.add(message),
      );

      // Message with matching clientId
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'chat', data: 'hello', clientId: 'user-42'),
          ],
        ),
      );

      // Message with different clientId -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'chat', data: 'hi', clientId: 'user-99'),
          ],
        ),
      );

      // Message with no clientId -- should NOT be delivered
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [const Message(name: 'system', data: 'broadcast')],
        ),
      );

      // Another message with matching clientId
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          messages: [
            const Message(name: 'chat', data: 'world', clientId: 'user-42'),
          ],
        ),
      );

      expect(filteredMessages, hasLength(2));
      expect(filteredMessages[0].data, equals('hello'));
      expect(filteredMessages[0].clientId, equals('user-42'));
      expect(filteredMessages[1].data, equals('world'));
      expect(filteredMessages[1].clientId, equals('user-42'));

      mockWs.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Private helpers (copied per project convention)
// ---------------------------------------------------------------------------

/// Waits for connection to reach the specified state.
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

/// Waits for channel to reach the specified state.
Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (channel.state == targetState) {
    return;
  }
  await channel
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

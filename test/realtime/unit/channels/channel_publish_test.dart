import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel publish (RTL6).
///
/// These tests use mocked WebSocket to verify message publishing,
/// state-dependent queuing/rejection, wire encoding, ACK/NACK handling,
/// and the RTL6c5 rule that publish does not trigger implicit attach.
///
/// Spec: uts/test/realtime/unit/channels/channel_publish.md
void main() {
  // ---------------------------------------------------------------------------
  // RTL6i1 - Publish single message by name and data
  // ---------------------------------------------------------------------------

  group('RTL6i1 - Publish single message by name and data', () {
    // UTS: realtime/unit/RTL6i1/publish-name-and-data-0
    test('sends a MESSAGE ProtocolMessage with one message entry', () async {
      final channelName = testChannelName('RTL6i1');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s1']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      await channel.publish(name: 'greeting', data: 'hello');

      expect(capturedMessages, hasLength(1));
      expect(capturedMessages[0].action, equals(ProtocolAction.message));
      expect(capturedMessages[0].channel, equals(channelName));
      expect(capturedMessages[0].messages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('greeting'));
      expect(msg['data'], equals('hello'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6i1/publish-message-object-1
    test('publishes a Message object directly', () async {
      final channelName = testChannelName('RTL6i1-obj');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s1']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      await channel.publish(
        message: const Message(name: 'custom', data: 'value'),
      );

      expect(capturedMessages, hasLength(1));
      expect(capturedMessages[0].messages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('custom'));
      expect(msg['data'], equals('value'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6i2 - Publish array of Message objects
  // ---------------------------------------------------------------------------

  group('RTL6i2 - Publish array of Message objects', () {
    // UTS: realtime/unit/RTL6i2/publish-message-array-0
    test('sends all messages in a single ProtocolMessage', () async {
      final channelName = testChannelName('RTL6i2');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(
                    serials: ['s1', 's2', 's3'],
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      await channel.publish(
        messages: const [
          Message(name: 'event1', data: 'data1'),
          Message(name: 'event2', data: 'data2'),
          Message(name: 'event3', data: 'data3'),
        ],
      );

      // Single ProtocolMessage with 3 messages
      expect(capturedMessages, hasLength(1));
      expect(capturedMessages[0].messages, hasLength(3));

      final msgs = capturedMessages[0].messages!.cast<Map<String, dynamic>>();
      expect(msgs[0]['name'], equals('event1'));
      expect(msgs[1]['name'], equals('event2'));
      expect(msgs[2]['name'], equals('event3'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6i3 - Null fields omitted from JSON wire encoding
  // ---------------------------------------------------------------------------

  group('RTL6i3 - Null fields omitted from JSON wire encoding', () {
    // UTS: realtime/unit/RTL6i3/null-fields-json-0
    test('name-only publish omits data key from wire JSON', () async {
      final channelName = testChannelName('RTL6i3-json');
      final capturedFrames = <Map<String, dynamic>>[];

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
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
        onTextDataFrame: (text) {
          final decoded = jsonDecode(text) as Map<String, dynamic>;
          // action 15 = MESSAGE
          if (decoded['action'] == 15) {
            capturedFrames.add(decoded);
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish with name only (null data)
      await channel.publish(name: 'click');

      // Publish with data only (null name)
      await channel.publish(data: 'payload');

      // Publish with both null
      await channel.publish();

      expect(capturedFrames, hasLength(3));

      // First: name present, data key absent
      final msg0 =
          (capturedFrames[0]['messages'] as List)[0] as Map<String, dynamic>;
      expect(msg0['name'], equals('click'));
      expect(msg0.containsKey('data'), isFalse);

      // Second: data present, name key absent
      final msg1 =
          (capturedFrames[1]['messages'] as List)[0] as Map<String, dynamic>;
      expect(msg1.containsKey('name'), isFalse);
      expect(msg1['data'], equals('payload'));

      // Third: both keys absent
      final msg2 =
          (capturedFrames[2]['messages'] as List)[0] as Map<String, dynamic>;
      expect(msg2.containsKey('name'), isFalse);
      expect(msg2.containsKey('data'), isFalse);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6i3 - Null fields in msgpack (skipped - Dart SDK does not support msgpack)
  // ---------------------------------------------------------------------------

  group('RTL6i3 - Null fields in msgpack', () {
    // UTS: realtime/unit/RTL6i3/null-fields-msgpack-1
    test(
      'RTL6i3 - null fields in msgpack',
      () {},
      skip: 'Not yet implemented: msgpack encoding support',
    );
  });

  // ---------------------------------------------------------------------------
  // RTL19b - JSON wire form of base message fields
  // ---------------------------------------------------------------------------

  group('RTL19b - JSON wire form of base message fields', () {
    // UTS: realtime/unit/RTL19b/json-wire-form-base-1
    test('base message fields are correctly serialized in JSON wire format',
        () async {
      final channelName = testChannelName('RTL19b-json');
      final capturedFrames = <Map<String, dynamic>>[];

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
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
        onTextDataFrame: (text) {
          final decoded = jsonDecode(text) as Map<String, dynamic>;
          // action 15 = MESSAGE
          if (decoded['action'] == 15) {
            capturedFrames.add(decoded);
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish with name and data
      await channel.publish(name: 'greeting', data: 'hello');

      expect(capturedFrames, hasLength(1));

      // Verify JSON wire format of base message fields
      final frame = capturedFrames[0];
      expect(frame['action'], equals(15)); // MESSAGE action
      expect(frame['channel'], equals(channelName));
      expect(frame['msgSerial'], isA<int>());

      final msg = (frame['messages'] as List)[0] as Map<String, dynamic>;
      expect(msg['name'], equals('greeting'));
      expect(msg['data'], equals('hello'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6c1 - Publish immediately when CONNECTED and channel ATTACHED
  // ---------------------------------------------------------------------------

  group('RTL6c1 - Publish immediately when CONNECTED', () {
    // UTS: realtime/unit/RTL6c1/publish-when-attached-0
    test('sends immediately when channel is ATTACHED', () async {
      final channelName = testChannelName('RTL6c1-attached');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      expect(client.connection.state, equals(ConnectionState.connected));
      expect(channel.state, equals(ChannelState.attached));

      await channel.publish(name: 'test', data: 'immediate');

      // Sent synchronously (captured by mock)
      expect(capturedMessages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('test'));
      expect(msg['data'], equals('immediate'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6c1/publish-when-attaching-1
    test('sends immediately when channel is ATTACHING', () async {
      final channelName = testChannelName('RTL6c1-attaching');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Don't respond — leave channel in ATTACHING
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            // Send ACK so the publish future resolves
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Start attach but don't complete it — swallow the eventual timeout
      unawaited(channel.attach().catchError((_) {}));
      await _awaitChannelState(channel, ChannelState.attaching);

      await channel.publish(name: 'while-attaching', data: 'data');

      // ATTACHING is neither SUSPENDED nor FAILED → sent immediately
      expect(capturedMessages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('while-attaching'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6c1/publish-when-initialized-2
    test('sends immediately when channel is INITIALIZED', () async {
      final channelName = testChannelName('RTL6c1-init');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      await channel.publish(name: 'before-attach', data: 'data');

      // INITIALIZED is neither SUSPENDED nor FAILED → sent immediately
      expect(capturedMessages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('before-attach'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6c2 - Publish queued when connection is CONNECTING
  // ---------------------------------------------------------------------------

  group('RTL6c2 - Publish queued when connection not CONNECTED', () {
    // UTS: realtime/unit/RTL6c2/queued-when-connecting-0
    test('queues and sends after CONNECTING → CONNECTED', () async {
      final channelName = testChannelName('RTL6c2-connecting');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Set up await BEFORE triggering connect
      final connAttemptFuture = mockWs.awaitConnectionAttempt();

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connecting,
      );

      // Publish while CONNECTING — should be queued.
      // Don't await yet — it won't resolve until ACK arrives after connection.
      final publishFuture = channel.publish(name: 'queued', data: 'waiting');

      // Not sent yet
      expect(capturedMessages, isEmpty);

      // Complete the connection
      final pendingConn = await connAttemptFuture;
      pendingConn.respondWithSuccess(ProtocolMessageHelpers.connected());
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Now await the publish — ACK will have been sent by onMessageFromClient
      await publishFuture;

      // Queued message now sent
      expect(capturedMessages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('queued'));
      expect(msg['data'], equals('waiting'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6c2/queued-when-initialized-2
    test('queues when connection is INITIALIZED', () async {
      final channelName = testChannelName('RTL6c2-init');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      expect(client.connection.state, equals(ConnectionState.initialized));

      // Publish before connecting — should be queued.
      // Don't await yet — resolves after connection + ACK.
      final publishFuture = channel.publish(name: 'pre-connect', data: 'early');
      expect(capturedMessages, isEmpty);

      // Now connect
      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Await publish — ACK will have arrived
      await publishFuture;

      // Queued message now sent
      expect(capturedMessages, hasLength(1));

      final msg = capturedMessages[0].messages![0] as Map<String, dynamic>;
      expect(msg['name'], equals('pre-connect'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6c2/queued-messages-order-4
    test('multiple queued messages sent in order', () async {
      final channelName = testChannelName('RTL6c2-order');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Set up await BEFORE triggering connect
      final connAttemptFuture = mockWs.awaitConnectionAttempt();

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connecting,
      );

      // Queue multiple messages — don't await yet
      final f1 = channel.publish(name: 'first', data: '1');
      final f2 = channel.publish(name: 'second', data: '2');
      final f3 = channel.publish(name: 'third', data: '3');

      expect(capturedMessages, isEmpty);

      // Complete the connection
      final pendingConn = await connAttemptFuture;
      pendingConn.respondWithSuccess(ProtocolMessageHelpers.connected());
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Await all publishes
      await Future.wait([f1, f2, f3]);

      // All messages sent in order
      expect(capturedMessages, hasLength(3));

      final names = capturedMessages
          .map(
            (m) => (m.messages![0] as Map<String, dynamic>)['name'],
          )
          .toList();
      expect(names, equals(['first', 'second', 'third']));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6c2/fails-no-queue-messages-3
    test('fails when queueMessages is false and not CONNECTED', () async {
      final channelName = testChannelName('RTL6c2-noqueue');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Don't respond — stay CONNECTING
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          queueMessages: false,
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
        ConnectionState.connecting,
      );

      try {
        await channel.publish(name: 'fail', data: 'should-error');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      await client.close();
      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6c4 - Publish fails in error states
  // ---------------------------------------------------------------------------

  group('RTL6c4 - Publish fails when connection is CLOSED', () {
    // UTS: realtime/unit/RTL6c4/fails-conn-closed-1
    test('throws error after close()', () async {
      final channelName = testChannelName('RTL6c4-closed');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      await client.close();
      expect(client.connection.state, equals(ConnectionState.closed));

      try {
        await channel.publish(name: 'fail', data: 'should-error');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      mockWs.dispose();
    });
  });

  group('RTL6c4 - Publish fails when connection is FAILED', () {
    // UTS: realtime/unit/RTL6c4/fails-conn-failed-2
    test('throws error when connection failed', () async {
      final channelName = testChannelName('RTL6c4-failed');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 80000,
              message: 'Fatal error',
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.failed,
      );

      try {
        await channel.publish(name: 'fail', data: 'should-error');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      mockWs.dispose();
    });
  });

  group('RTL6c4 - Publish fails when connection is SUSPENDED', () {
    // UTS: realtime/unit/RTL6c4/fails-conn-suspended-0
    test('throws error when connection suspended', () async {
      final channelName = testChannelName('RTL6c4-suspended');

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithRefused();
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final channel = client.channels.get(
          channelName,
          const RealtimeChannelOptions(attachOnSubscribe: false),
        );

        client.connect();

        // Wait for DISCONNECTED, then advance past connectionStateTtl
        // (default 120s) to reach SUSPENDED
        await _awaitConnectionState(
          client.connection,
          ConnectionState.disconnected,
        );

        fakeTimers.elapseTime(const Duration(seconds: 121));
        await _pumpEventQueue();

        await _awaitConnectionState(
          client.connection,
          ConnectionState.suspended,
        );

        try {
          await channel.publish(name: 'fail', data: 'should-error');
          fail('Expected AblyException');
        } catch (e) {
          expect(e, isA<AblyException>());
        }

        mockWs.dispose();
      });
    });
  });

  group('RTL6c4 - Publish fails when channel is FAILED', () {
    // UTS: realtime/unit/RTL6c4/fails-channel-failed-4
    test('throws error when channel is FAILED', () async {
      final channelName = testChannelName('RTL6c4-ch-failed');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Attach fails → channel enters FAILED
      try {
        await channel.attach();
      } catch (_) {}

      expect(channel.state, equals(ChannelState.failed));

      // Publish should fail because channel is FAILED
      try {
        await channel.publish(name: 'fail', data: 'should-error');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      // No MESSAGE sent to server
      expect(capturedMessages, isEmpty);

      mockWs.dispose();
    });
  });

  group('RTL6c4 - Publish fails when channel is SUSPENDED', () {
    // UTS: realtime/unit/RTL6c4/fails-channel-suspended-3
    test('throws error when channel is SUSPENDED', () async {
      final channelName = testChannelName('RTL6c4-ch-suspended');
      final capturedMessages = <ProtocolMessage>[];

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              // Don't respond — will timeout to SUSPENDED
            } else if (msg.action == ProtocolAction.message) {
              capturedMessages.add(msg);
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Start attach — will timeout and channel enters SUSPENDED
        Object? attachError;
        final attachFuture =
            channel.attach().catchError((Object e) => attachError = e);
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        await attachFuture;

        expect(attachError, isNotNull);
        expect(channel.state, equals(ChannelState.suspended));

        // Publish should fail because channel is SUSPENDED
        try {
          await channel.publish(name: 'fail', data: 'should-error');
          fail('Expected AblyException');
        } catch (e) {
          expect(e, isA<AblyException>());
        }

        // No MESSAGE sent to server
        expect(capturedMessages, isEmpty);

        mockWs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6c5 - Publish does not trigger implicit attach
  // ---------------------------------------------------------------------------

  group('RTL6c5 - Publish does not trigger implicit attach', () {
    // UTS: realtime/unit/RTL6c5/no-implicit-attach-0
    test('channel remains INITIALIZED after publish', () async {
      final channelName = testChannelName('RTL6c5');
      var attachMessageCount = 0;
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['s']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      await channel.publish(name: 'no-attach', data: 'test');

      // Message was sent (RTL6c1 — CONNECTED, channel not SUSPENDED/FAILED)
      expect(capturedMessages, hasLength(1));

      // Channel remains INITIALIZED — no implicit attach
      expect(channel.state, equals(ChannelState.initialized));
      expect(attachMessageCount, equals(0));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL6j - Publish returns PublishResult with serials from ACK
  // ---------------------------------------------------------------------------

  group('RTL6j - Publish returns PublishResult', () {
    // UTS: realtime/unit/RTL6j/publish-result-serials-0
    test('returns PublishResult with serials from ACK', () async {
      final channelName = testChannelName('RTL6j');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['abc123']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      final result = await channel.publish(name: 'greeting', data: 'hello');

      // Publish should have been sent with msgSerial
      expect(capturedMessages, hasLength(1));
      expect(capturedMessages[0].msgSerial, equals(0));

      // Result should be a PublishResult with serials from ACK
      expect(result, isA<PublishResult>());
      expect(result.serials, hasLength(1));
      expect(result.serials[0], equals('abc123'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6j/batch-publish-serials-1
    test('returns PublishResult with multiple serials for batch', () async {
      final channelName = testChannelName('RTL6j-batch');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['serial-1', null, 'serial-3']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      final result = await channel.publish(
        messages: const [
          Message(name: 'event1', data: 'data1'),
          Message(name: 'event2', data: 'data2'),
          Message(name: 'event3', data: 'data3'),
        ],
      );

      // Single ProtocolMessage with 3 messages
      expect(capturedMessages, hasLength(1));
      expect(capturedMessages[0].messages, hasLength(3));

      // Result has serials 1:1 with published messages
      expect(result.serials, hasLength(3));
      expect(result.serials[0], equals('serial-1'));
      expect(result.serials[1], isNull); // Conflated message
      expect(result.serials[2], equals('serial-3'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6j/incrementing-msg-serial-2
    test('sequential publishes get incrementing msgSerial', () async {
      final channelName = testChannelName('RTL6j-serial');
      final capturedMessages = <ProtocolMessage>[];

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
          } else if (msg.action == ProtocolAction.message) {
            capturedMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  PublishResult(serials: ['serial-${msg.msgSerial}']),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      final result1 = await channel.publish(name: 'first', data: '1');
      final result2 = await channel.publish(name: 'second', data: '2');
      final result3 = await channel.publish(name: 'third', data: '3');

      // Each outgoing MESSAGE should have incrementing msgSerial
      expect(capturedMessages, hasLength(3));
      expect(capturedMessages[0].msgSerial, equals(0));
      expect(capturedMessages[1].msgSerial, equals(1));
      expect(capturedMessages[2].msgSerial, equals(2));

      // Each publish resolves with the correct PublishResult
      expect(result1.serials[0], equals('serial-0'));
      expect(result2.serials[0], equals('serial-1'));
      expect(result3.serials[0], equals('serial-2'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL6j/nack-results-error-3
    test('NACK results in error', () async {
      final channelName = testChannelName('RTL6j-nack');

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
          } else if (msg.action == ProtocolAction.message) {
            // Respond with NACK
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.nack,
                msgSerial: msg.msgSerial,
                count: 1,
                error: const ErrorInfo(
                  code: 40160,
                  statusCode: 401,
                  message: 'Publish rejected',
                ),
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      try {
        await channel.publish(name: 'rejected', data: 'data');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final ablyError = e as AblyException;
        expect(ablyError.errorInfo?.code, equals(40160));
        expect(ablyError.errorInfo?.message, equals('Publish rejected'));
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTN7e - Pending publishes fail on SUSPENDED/CLOSED/FAILED
  // ---------------------------------------------------------------------------

  group('RTN7e - Pending publishes fail when connection enters CLOSED', () {
    // UTS: realtime/unit/RTN7e/pending-fail-closed-1
    test('pending publish fails when client.close() is called', () async {
      final channelName = testChannelName('RTN7e-closed');

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
          // Do NOT send ACK for MESSAGE — leave pending
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish but don't ACK — message stays pending
      final publishFuture = channel.publish(name: 'pending', data: 'data');

      // Close the connection
      await client.close();
      expect(client.connection.state, equals(ConnectionState.closed));

      // The pending publish should now fail
      try {
        await publishFuture;
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      mockWs.dispose();
    });
  });

  group('RTN7e - Pending publishes fail when connection enters FAILED', () {
    // UTS: realtime/unit/RTN7e/pending-fail-failed-2
    test('pending publish fails when server sends fatal ERROR', () async {
      final channelName = testChannelName('RTN7e-failed');

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
          } else if (msg.action == ProtocolAction.message) {
            // Respond with fatal ERROR instead of ACK
            // Schedule asynchronously so the publish future is returned first
            scheduleMicrotask(() {
              mockWs.activeConnection?.sendToClientAndClose(
                ProtocolMessage(
                  action: ProtocolAction.error,
                  error: const ErrorInfo(
                    code: 80000,
                    message: 'Fatal error',
                  ),
                ),
              );
            });
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish — server will respond with fatal ERROR asynchronously
      try {
        await channel.publish(name: 'pending', data: 'data');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      expect(client.connection.state, equals(ConnectionState.failed));

      mockWs.dispose();
    });
  });

  group('RTN7e - Pending publishes fail when connection enters SUSPENDED', () {
    // UTS: realtime/unit/RTN7e/pending-fail-suspended-0
    test('pending publish fails when connection becomes SUSPENDED', () async {
      final channelName = testChannelName('RTN7e-suspended');

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var isFirstConnection = true;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            if (isFirstConnection) {
              isFirstConnection = false;
              conn.respondWithSuccess(ProtocolMessageHelpers.connected());
            } else {
              // Refuse all reconnection attempts
              conn.respondWithRefused();
            }
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
            // Do NOT send ACK for MESSAGE — leave pending
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Publish but don't ACK — message stays pending.
        // Capture error eagerly to prevent unhandled error in test zone.
        Object? publishError;
        unawaited(
          channel
              .publish(name: 'pending', data: 'data')
              .then((_) => null)
              .catchError((Object e) {
            publishError = e;
            return null;
          }),
        );

        // Disconnect — reconnection attempts will be refused
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Wait for DISCONNECTED state
        await _awaitConnectionState(
          client.connection,
          ConnectionState.disconnected,
        );

        // Advance time past connectionStateTtl (120s default) to reach SUSPENDED
        fakeTimers.elapseTime(const Duration(seconds: 121));
        await _pumpEventQueue();

        await _awaitConnectionState(
          client.connection,
          ConnectionState.suspended,
        );

        // Give time for the error to propagate
        await _pumpEventQueue();

        // The pending publish should have failed
        expect(publishError, isA<AblyException>());

        mockWs.dispose();
      });
    });
  });

  group('RTN7e - Multiple pending publishes all fail on state change', () {
    // UTS: realtime/unit/RTN7e/multiple-pending-fail-3
    test('all pending publishes fail when connection closes', () async {
      final channelName = testChannelName('RTN7e-multi');

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
          // Do NOT send ACK for MESSAGE — leave all pending
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish multiple messages, none will be ACK'd
      final future1 = channel.publish(name: 'msg1', data: 'data1');
      final future2 = channel.publish(name: 'msg2', data: 'data2');
      final future3 = channel.publish(name: 'msg3', data: 'data3');

      // Close the connection
      await client.close();

      // All pending publishes should fail
      for (final future in [future1, future2, future3]) {
        try {
          await future;
          fail('Expected AblyException');
        } catch (e) {
          expect(e, isA<AblyException>());
        }
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTN7d - queueMessages=false fails pending on DISCONNECTED
  // ---------------------------------------------------------------------------

  group(
      'RTN7d - Pending publishes fail on DISCONNECTED when queueMessages=false',
      () {
    // UTS: realtime/unit/RTN7d/fail-disconnected-no-queue-0
    test('pending publish fails immediately on DISCONNECTED', () async {
      final channelName = testChannelName('RTN7d');

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
          // Do NOT send ACK for MESSAGE — leave pending
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          queueMessages: false,
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

      // Publish but don't ACK — message stays pending.
      // Capture error eagerly to prevent unhandled error in test zone.
      Object? publishError;
      unawaited(
        channel
            .publish(name: 'pending', data: 'data')
            .then((_) => null)
            .catchError((Object e) {
          publishError = e;
          return null;
        }),
      );

      // Disconnect — triggers DISCONNECTED state
      mockWs.activeConnection!.simulateDisconnect();
      await _pumpEventQueue();

      // The pending publish should have failed on DISCONNECTED
      expect(publishError, isA<AblyException>());

      mockWs.dispose();
    });
  });

  group(
      'RTN7d - Pending publishes survive DISCONNECTED when queueMessages=true',
      () {
    // UTS: realtime/unit/RTN7d/survive-disconnected-queue-1
    test('pending publish succeeds after reconnect', () async {
      final channelName = testChannelName('RTN7d-default');

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else if (msg.action == ProtocolAction.message) {
              if (connectionCount >= 2) {
                // ACK on reconnection
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.ack(
                    msgSerial: msg.msgSerial!,
                    res: [
                      const PublishResult(serials: ['serial-ack']),
                    ],
                  ),
                );
              }
              // First connection: do NOT ACK — leave pending
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Publish but don't ACK — message stays pending
        final publishFuture = channel.publish(name: 'pending', data: 'data');

        // Disconnect
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Reconnect
        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // The publish should eventually succeed (resent and ACK'd)
        final result = await publishFuture;

        expect(result, isA<PublishResult>());
        expect(result.serials[0], equals('serial-ack'));

        mockWs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // RTN19a - Pending messages resent on new transport after disconnect
  // ---------------------------------------------------------------------------

  group('RTN19a - Pending messages resent on new transport', () {
    // UTS: realtime/unit/RTN19a/resent-on-new-transport-0
    test('message is resent on second transport after disconnect', () async {
      final channelName = testChannelName('RTN19a');
      final capturedMessages = <({ProtocolMessage msg, int connection})>[];

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else if (msg.action == ProtocolAction.message) {
              capturedMessages.add(
                (msg: msg, connection: connectionCount),
              );
              if (connectionCount >= 2) {
                // ACK on second connection
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.ack(
                    msgSerial: msg.msgSerial!,
                    res: [
                      const PublishResult(serials: ['serial-resent']),
                    ],
                  ),
                );
              }
              // First connection: do NOT ACK
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Publish — sent on first transport, no ACK
        final publishFuture = channel.publish(
          name: 'resend-me',
          data: 'data',
        );

        // Verify sent on first transport
        final firstTransportMsgs =
            capturedMessages.where((m) => m.connection == 1).toList();
        expect(firstTransportMsgs, hasLength(1));

        // Disconnect
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Reconnect
        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // The publish should succeed (resent and ACK'd on new transport)
        final result = await publishFuture;

        // Message should have been sent on both transports
        final secondTransportMsgs = capturedMessages
            .where(
              (m) =>
                  m.connection == 2 && m.msg.action == ProtocolAction.message,
            )
            .toList();
        expect(secondTransportMsgs, isNotEmpty);

        // The resent message should have the same content
        final resentMsgs = secondTransportMsgs[0].msg.messages!;
        final resentMsg = resentMsgs[0] as Map<String, dynamic>;
        expect(resentMsg['name'], equals('resend-me'));

        // Publish resolved successfully
        expect(result.serials[0], equals('serial-resent'));

        mockWs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // RTN19a2 - msgSerial handling on resume vs failed resume
  // ---------------------------------------------------------------------------

  group('RTN19a2 - Resent messages keep same msgSerial on successful resume',
      () {
    // UTS: realtime/unit/RTN19a2/same-serial-on-resume-0
    test('msgSerial is preserved when connectionId stays the same', () async {
      final channelName = testChannelName('RTN19a2-resume');
      final capturedMessages = <({ProtocolMessage msg, int connection})>[];
      const originalConnectionId = 'connection-abc';

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            // Both connections use same connectionId = successful resume
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: originalConnectionId,
                connectionKey: 'key-$connectionCount',
              ),
            );
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else if (msg.action == ProtocolAction.message) {
              capturedMessages.add(
                (msg: msg, connection: connectionCount),
              );
              if (connectionCount >= 2) {
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.ack(
                    msgSerial: msg.msgSerial!,
                    res: [
                      const PublishResult(serials: ['serial-resumed']),
                    ],
                  ),
                );
              }
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Publish two messages — neither will be ACK'd
        final future1 = channel.publish(name: 'msg1', data: 'data1');
        final future2 = channel.publish(name: 'msg2', data: 'data2');

        // Capture original msgSerials
        final firstTransportMsgs = capturedMessages
            .where(
              (m) =>
                  m.connection == 1 && m.msg.action == ProtocolAction.message,
            )
            .toList();
        final originalSerial1 = firstTransportMsgs[0].msg.msgSerial!;
        final originalSerial2 = firstTransportMsgs[1].msg.msgSerial!;

        // Disconnect and reconnect (successful resume — same connectionId)
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        await future1;
        await future2;

        // Messages resent on second transport should have the SAME msgSerials
        final secondTransportMsgs = capturedMessages
            .where(
              (m) =>
                  m.connection == 2 && m.msg.action == ProtocolAction.message,
            )
            .toList();
        expect(secondTransportMsgs, hasLength(2));
        expect(secondTransportMsgs[0].msg.msgSerial, equals(originalSerial1));
        expect(secondTransportMsgs[1].msg.msgSerial, equals(originalSerial2));

        mockWs.dispose();
      });
    });
  });

  group('RTN19a2 - Resent messages get new msgSerial on failed resume', () {
    // UTS: realtime/unit/RTN19a2/new-serial-failed-resume-1
    test('msgSerial resets to 0 when connectionId changes', () async {
      final channelName = testChannelName('RTN19a2-failed');
      final capturedMessages = <({ProtocolMessage msg, int connection})>[];

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            if (connectionCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-first',
                  connectionKey: 'key-first',
                ),
              );
            } else {
              // Failed resume — different connectionId + error (RTN15c7)
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-new',
                  connectionKey: 'key-new',
                  error: const ErrorInfo(
                    code: 80018,
                    message: 'Connection not resumable',
                  ),
                ),
              );
            }
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else if (msg.action == ProtocolAction.message) {
              capturedMessages.add(
                (msg: msg, connection: connectionCount),
              );
              if (connectionCount >= 2) {
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.ack(
                    msgSerial: msg.msgSerial!,
                    res: [
                      const PublishResult(serials: ['serial-new']),
                    ],
                  ),
                );
              }
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Publish two messages with msgSerials 0 and 1 — neither ACK'd
        final future1 = channel.publish(name: 'msg1', data: 'data1');
        final future2 = channel.publish(name: 'msg2', data: 'data2');

        // Verify original serials
        final firstTransportMsgs = capturedMessages
            .where(
              (m) =>
                  m.connection == 1 && m.msg.action == ProtocolAction.message,
            )
            .toList();
        expect(firstTransportMsgs[0].msg.msgSerial, equals(0));
        expect(firstTransportMsgs[1].msg.msgSerial, equals(1));

        // Disconnect and reconnect (failed resume — different connectionId)
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        await future1;
        await future2;

        // Messages resent on second transport should have NEW msgSerials
        // starting from 0 (RTN15c7 resets the internal counter)
        final secondTransportMsgs = capturedMessages
            .where(
              (m) =>
                  m.connection == 2 && m.msg.action == ProtocolAction.message,
            )
            .toList();
        expect(secondTransportMsgs, hasLength(2));
        expect(secondTransportMsgs[0].msg.msgSerial, equals(0));
        expect(secondTransportMsgs[1].msg.msgSerial, equals(1));

        mockWs.dispose();
      });
    });
  });

  // ---------------------------------------------------------------------------
  // RTN19b - Pending ATTACH/DETACH resent on new transport
  // ---------------------------------------------------------------------------

  group('RTN19b - Pending ATTACH resent on new transport', () {
    // UTS: realtime/unit/RTN19b/attach-resent-on-reconnect-0
    test('ATTACH is resent after disconnect and reconnect', () async {
      final channelName = testChannelName('RTN19b-attach');
      final capturedAttachMessages =
          <({ProtocolMessage msg, int connection})>[];

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              capturedAttachMessages.add(
                (msg: msg, connection: connectionCount),
              );
              if (connectionCount >= 2) {
                // Respond with ATTACHED on second connection
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: msg.channel!),
                );
              }
              // First connection: don't respond — leave channel ATTACHING
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 60000, // Long timeout to avoid timeout
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Start attach but don't respond — channel stays ATTACHING
        final attachFuture = channel.attach();
        await _awaitChannelState(channel, ChannelState.attaching);

        // Verify ATTACH was sent on first transport
        final firstTransportAttaches =
            capturedAttachMessages.where((m) => m.connection == 1).toList();
        expect(firstTransportAttaches, hasLength(1));
        expect(firstTransportAttaches[0].msg.channel, equals(channelName));

        // Disconnect and reconnect
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // Attach should complete (resent and responded to on new transport)
        await attachFuture;

        expect(channel.state, equals(ChannelState.attached));

        // ATTACH should have been resent on second transport
        final secondTransportAttaches =
            capturedAttachMessages.where((m) => m.connection == 2).toList();
        expect(secondTransportAttaches, isNotEmpty);
        expect(
          secondTransportAttaches[0].msg.channel,
          equals(channelName),
        );

        mockWs.dispose();
      });
    });
  });

  group('RTN19b - Pending DETACH resent on new transport', () {
    // UTS: realtime/unit/RTN19b/detach-resent-on-reconnect-1
    test('DETACH is resent after disconnect and reconnect', () async {
      final channelName = testChannelName('RTN19b-detach');
      final capturedDetachMessages =
          <({ProtocolMessage msg, int connection})>[];

      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: msg.channel!),
              );
            } else if (msg.action == ProtocolAction.detach) {
              capturedDetachMessages.add(
                (msg: msg, connection: connectionCount),
              );
              if (connectionCount >= 2) {
                // Respond with DETACHED on second connection
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.detached(channel: msg.channel!),
                );
              }
              // First connection: don't respond — leave channel DETACHING
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 60000, // Long timeout to avoid timeout
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
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

        // Start detach but don't respond — channel stays DETACHING
        final detachFuture = channel.detach();
        await _awaitChannelState(channel, ChannelState.detaching);

        // Verify DETACH was sent on first transport
        final firstTransportDetaches =
            capturedDetachMessages.where((m) => m.connection == 1).toList();
        expect(firstTransportDetaches, hasLength(1));

        // Disconnect and reconnect
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        fakeTimers.elapseTime(const Duration(seconds: 2));
        await _pumpEventQueue();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // Detach should complete (resent and responded to on new transport)
        await detachFuture;

        expect(channel.state, equals(ChannelState.detached));

        // DETACH should have been resent on second transport
        final secondTransportDetaches =
            capturedDetachMessages.where((m) => m.connection == 2).toList();
        expect(secondTransportDetaches, isNotEmpty);
        expect(
          secondTransportDetaches[0].msg.channel,
          equals(channelName),
        );

        mockWs.dispose();
      });
    });
  });

  group(
      'RTN7e - Error passed to publish callback represents state change reason',
      () {
    // UTS: realtime/unit/RTN7e/error-represents-reason-4
    test('publish callback error matches the connection failure reason',
        () async {
      final channelName = testChannelName('RTN7e');

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
          } else if (msg.action == ProtocolAction.message) {
            // Don't ACK — send fatal error to force FAILED state
            mockWs.activeConnection!.sendToClientAndClose(
              ProtocolMessage(
                action: ProtocolAction.error,
                error: const ErrorInfo(
                  code: 80019,
                  statusCode: 400,
                  message: 'Connection closed due to admin action',
                ),
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Publish without waiting for ACK — will be rejected with error
      Object? publishError;
      try {
        await channel.publish(name: 'test', data: 'hello');
      } catch (e) {
        publishError = e;
      }

      // The publish error should match the connection failure reason
      expect(publishError, isNotNull);
      expect(publishError, isA<AblyException>());
      final error = (publishError! as AblyException).errorInfo;
      expect(error, isNotNull);
      expect(error!.code, equals(80019));

      mockWs.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Private helpers (copied per project convention)
// ---------------------------------------------------------------------------

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

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

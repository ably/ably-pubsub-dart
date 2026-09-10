import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel updateMessage/deleteMessage/appendMessage
/// (RTL32).
///
/// These tests use mocked WebSocket to verify that mutation operations
/// send correctly formatted MESSAGE ProtocolMessages with the right
/// action, serial, data encoding, and operation fields.
///
/// Spec: uts/test/realtime/unit/channels/channel_update_delete_message.md
void main() {
  // Flag bits: PUBLISH = 1 << 17 = 131072
  const publishFlag = 131072;

  // ---------------------------------------------------------------------------
  // RTL32b, RTL32b1 — updateMessage sends MESSAGE with MESSAGE_UPDATE
  // ---------------------------------------------------------------------------

  group('RTL32b, RTL32b1 - updateMessage sends MESSAGE_UPDATE', () {
    // UTS: realtime/unit/RTL32b/update-message-action-0
    test('sends MESSAGE ProtocolMessage with action MESSAGE_UPDATE', () async {
      final channelName = testChannelName('RTL32-update');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      await channel.updateMessage(
        const Message(
          serial: 'msg-serial-1',
          name: 'updated',
          data: 'new-data',
        ),
      );

      // Find the MESSAGE ProtocolMessage (not the ATTACH)
      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      expect(messagePms, hasLength(1));

      final pm = messagePms[0];
      expect(pm.channel, equals(channelName));
      expect(pm.messages, hasLength(1));

      final msg = pm.messages![0] as Map<String, dynamic>;
      expect(msg['action'], equals(1)); // MESSAGE_UPDATE
      expect(msg['serial'], equals('msg-serial-1'));
      expect(msg['name'], equals('updated'));
      expect(msg['data'], equals('new-data'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32b, RTL32b1 — deleteMessage sends MESSAGE with MESSAGE_DELETE
  // ---------------------------------------------------------------------------

  group('RTL32b, RTL32b1 - deleteMessage sends MESSAGE_DELETE', () {
    // UTS: realtime/unit/RTL32b/delete-message-action-1
    test('sends MESSAGE ProtocolMessage with action MESSAGE_DELETE', () async {
      final channelName = testChannelName('RTL32-delete');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      await channel.deleteMessage(
        const Message(serial: 'msg-serial-1'),
      );

      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      expect(messagePms, hasLength(1));

      final msg = messagePms[0].messages![0] as Map<String, dynamic>;
      expect(msg['action'], equals(2)); // MESSAGE_DELETE
      expect(msg['serial'], equals('msg-serial-1'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32b, RTL32b1 — appendMessage sends MESSAGE with MESSAGE_APPEND
  // ---------------------------------------------------------------------------

  group('RTL32b, RTL32b1 - appendMessage sends MESSAGE_APPEND', () {
    // UTS: realtime/unit/RTL32b/append-message-action-2
    test('sends MESSAGE ProtocolMessage with action MESSAGE_APPEND', () async {
      final channelName = testChannelName('RTL32-append');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      await channel.appendMessage(
        const Message(serial: 'msg-serial-1', data: 'appended-data'),
        operation: const MessageOperation(description: 'appended content'),
      );

      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      expect(messagePms, hasLength(1));

      final msg = messagePms[0].messages![0] as Map<String, dynamic>;
      expect(msg['action'], equals(5)); // MESSAGE_APPEND
      expect(msg['serial'], equals('msg-serial-1'));
      expect(msg['data'], equals('appended-data'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32b2 — version field set from MessageOperation
  // ---------------------------------------------------------------------------

  group('RTL32b2 - version field set from MessageOperation', () {
    // UTS: realtime/unit/RTL32b2/version-from-operation-0
    test('version present when operation provided, absent when not', () async {
      final channelName = testChannelName('RTL32b2');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      // With operation
      await channel.updateMessage(
        const Message(serial: 'msg-serial-1', data: 'v2'),
        operation: const MessageOperation(
          description: 'edited content',
          metadata: {'reason': 'typo'},
        ),
      );

      // Without operation
      await channel.updateMessage(
        const Message(serial: 'msg-serial-2', data: 'v2'),
      );

      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      expect(messagePms, hasLength(2));

      // With operation: version field present
      final msgWithOp = messagePms[0].messages![0] as Map<String, dynamic>;
      expect(msgWithOp['version'], isNotNull);
      final version = msgWithOp['version'] as Map<String, dynamic>;
      expect(version['description'], equals('edited content'));
      expect((version['metadata'] as Map)['reason'], equals('typo'));

      // Without operation: version field absent
      final msgWithoutOp = messagePms[1].messages![0] as Map<String, dynamic>;
      expect(msgWithoutOp.containsKey('version'), isFalse);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32c — does not mutate user-supplied Message
  // ---------------------------------------------------------------------------

  group('RTL32c - does not mutate user-supplied Message', () {
    // UTS: realtime/unit/RTL32c/no-message-mutation-0
    test('original message unchanged after updateMessage', () async {
      final channelName = testChannelName('RTL32c');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      const originalMessage = Message(
        serial: 'msg-serial-1',
        name: 'original',
        data: 'original-data',
      );
      await channel.updateMessage(originalMessage);

      // Original message unchanged
      expect(originalMessage.name, equals('original'));
      expect(originalMessage.data, equals('original-data'));
      expect(originalMessage.serial, equals('msg-serial-1'));
      expect(originalMessage.action, isNull);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32d — returns UpdateDeleteResult from ACK
  // ---------------------------------------------------------------------------

  group('RTL32d - returns UpdateDeleteResult from ACK', () {
    // UTS: realtime/unit/RTL32d/ack-returns-result-0
    test('result contains versionSerial from ACK response', () async {
      final channelName = testChannelName('RTL32d');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(
                    serials: ['01770000000000-000@abcdef:000'],
                  ),
                ],
              ),
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

      final result = await channel.updateMessage(
        const Message(serial: 'msg-serial-1', data: 'updated'),
      );

      expect(result, isA<UpdateDeleteResult>());
      expect(result.versionSerial, equals('01770000000000-000@abcdef:000'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32d — NACK returns error
  // ---------------------------------------------------------------------------

  group('RTL32d - NACK returns error', () {
    // UTS: realtime/unit/RTL32d/nack-returns-error-1
    test('NACK results in AblyException with server error code', () async {
      final channelName = testChannelName('RTL32d-nack');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.nack,
                msgSerial: msg.msgSerial,
                count: 1,
                error: const ErrorInfo(
                  code: 40160,
                  message: 'Not permitted',
                ),
              ),
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

      try {
        await channel.updateMessage(
          const Message(serial: 'msg-serial-1', data: 'updated'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40160));
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32e — params sent in ProtocolMessage.params
  // ---------------------------------------------------------------------------

  group('RTL32e - params sent in ProtocolMessage.params', () {
    // UTS: realtime/unit/RTL32e/params-in-protocol-message-0
    test('optional params forwarded in ProtocolMessage', () async {
      final channelName = testChannelName('RTL32e');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      await channel.updateMessage(
        const Message(serial: 'msg-serial-1', data: 'v2'),
        params: {'key1': 'value1', 'key2': 'value2'},
      );

      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      expect(messagePms, hasLength(1));

      expect(messagePms[0].params!['key1'], equals('value1'));
      expect(messagePms[0].params!['key2'], equals('value2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32a — serial validation
  // ---------------------------------------------------------------------------

  group('RTL32a - serial validation', () {
    // UTS: realtime/unit/RTL32a/serial-validation-required-0
    test('empty serial throws AblyException with code 40003', () async {
      final channelName = testChannelName('RTL32a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
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

      // Empty serial
      try {
        await channel.updateMessage(
          const Message(serial: '', data: 'v2'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      // Null serial (Message without serial)
      try {
        await channel.deleteMessage(
          const Message(data: 'v2'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL32b / RSL15d — JSON data encoding
  // ---------------------------------------------------------------------------

  group('RTL32b, RSL15d - JSON data encoded per RSL4', () {
    // UTS: realtime/unit/RTL32b/update-message-action-0.1
    test('Map data is JSON-encoded with encoding field', () async {
      final channelName = testChannelName('RTL32-encode');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag,
              ),
            );
          } else if (msg.action == ProtocolAction.message) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
                res: [
                  const PublishResult(serials: ['version-serial-1']),
                ],
              ),
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

      await channel.updateMessage(
        const Message(
          serial: 'msg-serial-1',
          data: {
            'key': 'value',
            'nested': {'a': 1},
          },
        ),
      );

      final messagePms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.message)
          .toList();
      final msg = messagePms[0].messages![0] as Map<String, dynamic>;

      expect(msg['data'], isA<String>());
      expect(msg['encoding'], equals('json'));
      expect(
        json.decode(msg['data'] as String),
        equals({
          'key': 'value',
          'nested': {'a': 1},
        }),
      );

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

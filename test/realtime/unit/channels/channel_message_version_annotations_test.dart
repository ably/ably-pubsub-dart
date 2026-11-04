import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for `version` (TM2s, TM2s1, TM2s2) and `annotations` (TM2u,
/// TM8a) on realtime-delivered messages (RTL7).
void main() {
  group('TM2s1, TM2s2 - version defaults on the realtime path', () {
    test('version.serial and version.timestamp default from the message',
        () async {
      final received = await _deliver(
        prefix: 'TM2s1',
        wireMessage: {
          'name': 'chat.message',
          'data': 'hello',
          'serial': '01826232498871-001@abcdefghij:001',
          'timestamp': 1700000000000,
          'action': 0,
        },
      );

      expect(received, hasLength(1));
      expect(received[0].version, isNotNull);
      expect(
        received[0].version!.serial,
        equals('01826232498871-001@abcdefghij:001'),
      );
      expect(received[0].version!.timestamp, equals(1700000000000));
    });
  });

  group('TM2s - explicit wire version is preserved', () {
    test('version fields are decoded from the wire map', () async {
      final received = await _deliver(
        prefix: 'TM2s',
        wireMessage: {
          'name': 'chat.message',
          'data': 'edited',
          'serial': '01826232498871-001@abcdefghij:001',
          'timestamp': 1700000000000,
          'action': 1,
          'version': {
            'serial': '01826232498999-002@abcdefghij:001',
            'timestamp': 1700000005000,
            'clientId': 'alice',
            'description': 'typo',
          },
        },
      );

      expect(received, hasLength(1));
      expect(received[0].action, equals(MessageAction.messageUpdate));
      expect(
        received[0].version!.serial,
        equals('01826232498999-002@abcdefghij:001'),
      );
      expect(received[0].version!.timestamp, equals(1700000005000));
      expect(received[0].version!.clientId, equals('alice'));
      expect(received[0].version!.description, equals('typo'));
    });
  });

  group('TM2u, TM8a - annotations.summary on MESSAGE_SUMMARY', () {
    test('action 4 carries annotations.summary through to subscribers',
        () async {
      final received = await _deliver(
        prefix: 'TM2u-summary',
        wireMessage: {
          'serial': '01826232498871-001@abcdefghij:001',
          'timestamp': 1700000000000,
          'action': 4,
          'annotations': {
            'summary': {
              'reaction:distinct.v1': {
                'like': {
                  'total': 2,
                  'clientIds': ['alice', 'bob'],
                },
              },
            },
          },
        },
      );

      expect(received, hasLength(1));
      expect(received[0].action, equals(MessageAction.messageSummary));
      expect(received[0].annotations, isNotNull);
      final summary = received[0].annotations!.summary;
      expect(summary.keys, contains('reaction:distinct.v1'));
      final distinct = summary['reaction:distinct.v1']! as Map<String, dynamic>;
      final like = distinct['like']! as Map<String, dynamic>;
      expect(like['total'], equals(2));
      expect(like['clientIds'], equals(['alice', 'bob']));
    });
  });

  group('TM2u - missing annotations means an empty summary', () {
    test('annotations is non-null with an empty summary', () async {
      final received = await _deliver(
        prefix: 'TM2u-empty',
        wireMessage: {
          'name': 'chat.message',
          'data': 'hello',
          'serial': '01826232498871-001@abcdefghij:001',
          'action': 0,
        },
      );

      expect(received, hasLength(1));
      expect(received[0].annotations, isNotNull);
      expect(received[0].annotations!.summary, isEmpty);
    });
  });
}

/// Connects, attaches, injects one raw wire message and returns whatever
/// reached the `channel.subscribe` listener.
///
/// The message is passed as a raw `Map<String, dynamic>` rather than a
/// `Message`, because `Message.toMap()` never serialises `annotations`
/// (it is read-only from the wire) and so could not exercise TM2u.
Future<List<Message>> _deliver({
  required String prefix,
  required Map<String, dynamic> wireMessage,
}) async {
  final channelName = testChannelName(prefix);

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
    options: ClientOptions(key: 'appId.keyId:keySecret', autoConnect: false),
    webSocketClient: mockWs,
  );

  final channel = client.channels.get(
    channelName,
    const RealtimeChannelOptions(attachOnSubscribe: false),
  );

  final received = <Message>[];
  channel.subscribe(received.add);

  client.connect();
  await client.connection
      .on()
      .firstWhere((change) => change.current == ConnectionState.connected)
      .timeout(const Duration(seconds: 5));
  await channel.attach();

  mockWs.activeConnection!.sendToClient(
    ProtocolMessage(
      action: ProtocolAction.message,
      channel: channelName,
      id: 'proto:0',
      messages: [wireMessage],
    ),
  );

  mockWs.dispose();
  return received;
}

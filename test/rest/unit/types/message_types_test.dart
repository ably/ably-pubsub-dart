import 'dart:convert';
import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// Message Types Tests
///
/// Spec points: TM1, TM2, TM3, TM4, TM2a, TM2b, TM2c, TM2d, TM2e,
///              TM2f, TM2g, TM2h, TM2i
void main() {
  group('Message', () {
    group('TM2a-TM2i - Message attributes', () {
      // UTS: rest/unit/TM2a/message-attributes-0
      test('TM2a - id attribute', () {
        const message = Message(id: 'unique-id');
        expect(message.id, equals('unique-id'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.1
      test('TM2b - name attribute', () {
        const message = Message(name: 'event-name');
        expect(message.name, equals('event-name'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.2
      test('TM2c - data attribute (string)', () {
        const message = Message(data: 'string-data');
        expect(message.data, equals('string-data'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.3
      test('TM2c - data attribute (map)', () {
        const message = Message(data: {'key': 'value'});
        expect(message.data, equals({'key': 'value'}));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.4
      test('TM2c - data attribute (binary)', () {
        final bytes = Uint8List.fromList([0x01, 0x02]);
        final message = Message(data: bytes);
        expect(message.data, equals(bytes));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.5
      test('TM2d - clientId attribute', () {
        const message = Message(clientId: 'message-client');
        expect(message.clientId, equals('message-client'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.6
      test('TM2e - connectionId attribute', () {
        const message = Message(connectionId: 'conn-id');
        expect(message.connectionId, equals('conn-id'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.7
      test('TM2f - timestamp attribute', () {
        const message = Message(timestamp: 1234567890000);
        expect(message.timestamp, equals(1234567890000));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.8
      test('TM2g - encoding attribute', () {
        const message = Message(encoding: 'json/base64');
        expect(message.encoding, equals('json/base64'));
      });

      // UTS: rest/unit/TM2a/message-attributes-0.9
      test('TM2h - extras attribute', () {
        const message = Message(
          extras: MessageExtras(
            data: {
              'push': {
                'notification': {'title': 'Hello'},
              },
            },
          ),
        );
        expect(
          message.extras?.data['push']['notification']['title'],
          equals('Hello'),
        );
      });
    });

    group('TM3 - fromEncoded / fromEncodedArray', () {
      // UTS: rest/unit/TM3/from-encoded-deserialization-0
      test('fromEncoded deserializes wire format', () {
        final jsonData = {
          'id': 'msg-123',
          'name': 'test-event',
          'data': 'hello world',
          'clientId': 'sender-client',
          'connectionId': 'conn-456',
          'timestamp': 1234567890000,
          'encoding': null,
          'extras': {
            'headers': {'x-custom': 'value'},
          },
        };

        final message = Message.fromJson(jsonData);

        expect(message.id, equals('msg-123'));
        expect(message.name, equals('test-event'));
        expect(message.data, equals('hello world'));
        expect(message.clientId, equals('sender-client'));
        expect(message.connectionId, equals('conn-456'));
        expect(message.timestamp, equals(1234567890000));
        expect(message.extras?.data['headers']['x-custom'], equals('value'));
      });

      // UTS: rest/unit/TM3/from-encoded-decodes-encoding-1
      test('fromEncoded decodes null encoding (plain text)', () {
        final message = Message.fromJson({
          'id': 'msg',
          'name': 'event',
          'data': 'plain text',
          'encoding': null,
        });
        expect(message.data, equals('plain text'));
      });

      // UTS: rest/unit/TM3/from-encoded-decodes-encoding-1.1
      test('fromEncoded decodes json encoding', () {
        final message = Message.fromJson({
          'id': 'msg',
          'name': 'event',
          'data': '{"key":"value"}',
          'encoding': 'json',
        });
        expect(message.data, equals({'key': 'value'}));
      });

      // UTS: rest/unit/TM3/from-encoded-decodes-encoding-1.2
      test('fromEncoded decodes base64 encoding', () {
        final message = Message.fromJson({
          'id': 'msg',
          'name': 'event',
          'data': base64.encode(utf8.encode('Hello')),
          'encoding': 'base64',
        });
        expect(message.data, isA<Uint8List>());
        expect(utf8.decode(message.data as Uint8List), equals('Hello'));
      });

      // UTS: rest/unit/TM3/from-encoded-decodes-encoding-1.3
      test('fromEncoded decodes json/base64 compound encoding', () {
        final message = Message.fromJson({
          'id': 'msg',
          'name': 'event',
          'data': base64.encode(utf8.encode('{"k":"v"}')),
          'encoding': 'json/base64',
        });
        expect(message.data, equals({'k': 'v'}));
      });

      // UTS: rest/unit/TM3/from-encoded-deserialization-0.1
      test('fromEncodedArray deserializes array of messages', () {
        final messages = Message.fromEncodedArray([
          {'name': 'event1', 'data': 'data1'},
          {'name': 'event2', 'data': 'data2'},
        ]);
        expect(messages.length, equals(2));
        expect(messages[0].name, equals('event1'));
        expect(messages[1].name, equals('event2'));
      });
    });

    group('TM4 - Message constructors', () {
      // UTS: rest/unit/TM4/message-constructors-0
      test('constructor(name, data)', () {
        const message = Message(name: 'event-name', data: 'payload');
        expect(message.name, equals('event-name'));
        expect(message.data, equals('payload'));
        expect(message.clientId, isNull);
      });

      // UTS: rest/unit/TM4/message-constructors-0.1
      test('constructor(name, data, clientId)', () {
        const message = Message(
          name: 'event-name',
          data: 'payload',
          clientId: 'client-1',
        );
        expect(message.name, equals('event-name'));
        expect(message.data, equals('payload'));
        expect(message.clientId, equals('client-1'));
      });

      // UTS: rest/unit/TM4/message-constructors-0.2
      test('name and data are nullable', () {
        const message = Message();
        expect(message.name, isNull);
        expect(message.data, isNull);
      });
    });

    group('TM - Null/missing attributes', () {
      // UTS: rest/unit/TM/null-missing-attributes-0
      test('null or missing attributes are handled correctly', () {
        const message = Message();

        expect(message.id, isNull);
        expect(message.name, isNull);
        expect(message.data, isNull);
        expect(message.clientId, isNull);
        expect(message.timestamp, isNull);
      });
    });

    group('TM - Message with extras', () {
      // UTS: rest/unit/TM/message-with-extras-1
      test('push notification extras are handled correctly', () {
        const message = Message(
          name: 'push-event',
          data: 'payload',
          extras: MessageExtras(
            data: {
              'push': {
                'notification': {
                  'title': 'New Message',
                  'body': 'You have a new notification',
                },
                'data': {
                  'customKey': 'customValue',
                },
              },
            },
          ),
        );

        expect(
          message.extras?.data['push']['notification']['title'],
          equals('New Message'),
        );
        expect(
          message.extras?.data['push']['data']['customKey'],
          equals('customValue'),
        );
      });
    });
  });
}

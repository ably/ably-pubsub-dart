import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// PresenceMessage Types Tests
///
/// Spec points: TP1, TP2, TP3, TP3a, TP3b, TP3c, TP3d, TP3e, TP3f, TP3g,
///              TP3h, TP3i, TP4, TP5
void main() {
  group('PresenceMessage', () {
    group('TP2 - PresenceAction enum values', () {
      // UTS: rest/unit/TP5/presence-message-size-0
      test(
          'TP2 - enum values are ordered from zero: '
          'absent, present, enter, leave, update', () {
        expect(PresenceAction.absent.index, equals(0));
        expect(PresenceAction.present.index, equals(1));
        expect(PresenceAction.enter.index, equals(2));
        expect(PresenceAction.leave.index, equals(3));
        expect(PresenceAction.update.index, equals(4));
      });

      // UTS: rest/unit/TP2/presence-action-enum-values-0.1
      test('TP2 - numeric wire values match enum indices', () {
        expect(PresenceAction.absent.toInt(), equals(0));
        expect(PresenceAction.present.toInt(), equals(1));
        expect(PresenceAction.enter.toInt(), equals(2));
        expect(PresenceAction.leave.toInt(), equals(3));
        expect(PresenceAction.update.toInt(), equals(4));
      });

      // UTS: rest/unit/TP2/presence-action-enum-values-0
      test('TP2 - string representations match action names', () {
        expect(PresenceAction.absent.toAblyString(), equals('absent'));
        expect(PresenceAction.present.toAblyString(), equals('present'));
        expect(PresenceAction.enter.toAblyString(), equals('enter'));
        expect(PresenceAction.leave.toAblyString(), equals('leave'));
        expect(PresenceAction.update.toAblyString(), equals('update'));
      });
    });

    group('TP3a-TP3i - PresenceMessage attributes', () {
      // UTS: rest/unit/TP3a/presence-message-attributes-0
      test('TP3a - id attribute', () {
        const msg = PresenceMessage(id: 'presence-123');
        expect(msg.id, equals('presence-123'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.1
      test('TP3b - action attribute', () {
        const msg = PresenceMessage(action: PresenceAction.enter);
        expect(msg.action, equals(PresenceAction.enter));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.2
      test('TP3c - clientId attribute', () {
        const msg = PresenceMessage(clientId: 'user-1');
        expect(msg.clientId, equals('user-1'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.3
      test('TP3d - connectionId attribute', () {
        const msg = PresenceMessage(connectionId: 'conn-1');
        expect(msg.connectionId, equals('conn-1'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.4
      test('TP3e - data attribute (string)', () {
        const msg = PresenceMessage(data: 'hello');
        expect(msg.data, equals('hello'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.5
      test('TP3e - data attribute (object)', () {
        const msg = PresenceMessage(data: {'status': 'online'});
        expect(msg.data, equals({'status': 'online'}));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.6
      test('TP3e - data attribute (binary)', () {
        final bytes = Uint8List.fromList([0x01, 0x02, 0x03]);
        final msg = PresenceMessage(data: bytes);
        expect(msg.data, equals(bytes));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.7
      test('TP3f - encoding attribute', () {
        const msg = PresenceMessage(encoding: 'json');
        expect(msg.encoding, equals('json'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.8
      test('TP3g - timestamp attribute', () {
        final msg = PresenceMessage(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1234567890000),
        );
        expect(msg.timestamp?.millisecondsSinceEpoch, equals(1234567890000));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.9
      test('TP3i - extras attribute', () {
        const msg = PresenceMessage(
          extras: MessageExtras(
            data: {
              'headers': {'x-custom': 'value'},
            },
          ),
        );
        expect(msg.extras?.data['headers']['x-custom'], equals('value'));
      });
    });

    group('TP3h - memberKey combines connectionId and clientId', () {
      // UTS: rest/unit/TP3h/member-key-combines-ids-0
      test('TP3h - memberKey format is connectionId:clientId', () {
        const msg = PresenceMessage(
          connectionId: 'conn-1',
          clientId: 'user-1',
        );
        expect(msg.memberKey, equals('conn-1:user-1'));
      });

      // UTS: rest/unit/TP3d/connectionid-from-protocol-message-0
      test('TP3h - different connectionId produces different memberKey', () {
        const msg1 = PresenceMessage(
          connectionId: 'conn-1',
          clientId: 'user-1',
        );
        const msg2 = PresenceMessage(
          connectionId: 'conn-2',
          clientId: 'user-1',
        );

        expect(msg1.memberKey, equals('conn-1:user-1'));
        expect(msg2.memberKey, equals('conn-2:user-1'));
        expect(msg1.memberKey, isNot(equals(msg2.memberKey)));
      });
    });

    group('TP3 - PresenceMessage from JSON (wire format)', () {
      // UTS: rest/unit/TP3/presence-from-json-0
      test('deserializes all fields from JSON wire format', () {
        final jsonData = <String, dynamic>{
          'id': 'pm-123',
          'action': 2, // enter as numeric wire value
          'clientId': 'user-1',
          'connectionId': 'conn-1',
          'data': 'hello',
          'encoding': null,
          'timestamp': 1234567890000,
          'extras': {
            'headers': {'x-key': 'x-value'},
          },
        };

        final msg = PresenceMessage.fromMap(jsonData);

        expect(msg.id, equals('pm-123'));
        expect(msg.action, equals(PresenceAction.enter));
        expect(msg.clientId, equals('user-1'));
        expect(msg.connectionId, equals('conn-1'));
        expect(msg.data, equals('hello'));
        expect(
          msg.timestamp?.millisecondsSinceEpoch,
          equals(1234567890000),
        );
        expect(msg.extras?.data['headers']['x-key'], equals('x-value'));
      });

      // UTS: rest/unit/TP3/presence-to-json-2
      test('deserializes action from string representation', () {
        final jsonData = <String, dynamic>{
          'action': 'enter',
          'clientId': 'user-1',
        };

        final msg = PresenceMessage.fromMap(jsonData);
        expect(msg.action, equals(PresenceAction.enter));
      });

      // UTS: rest/unit/TP3/presence-encoded-data-from-json-1
      test('deserializes action from numeric wire value', () {
        final jsonData = <String, dynamic>{
          'action': 3, // leave
          'clientId': 'user-1',
        };

        final msg = PresenceMessage.fromMap(jsonData);
        expect(msg.action, equals(PresenceAction.leave));
      });
    });

    group('TP3 - PresenceMessage to JSON (wire format)', () {
      // UTS: rest/unit/TP3a/presence-message-attributes-0.10
      test('serializes correctly for transmission', () {
        const msg = PresenceMessage(
          action: PresenceAction.enter,
          clientId: 'user-1',
          data: 'hello',
          extras: MessageExtras(
            data: {
              'headers': {'x-key': 'x-value'},
            },
          ),
        );

        final jsonData = msg.toMap();

        // Action is serialized as numeric wire value
        expect(jsonData['action'], equals(2));
        expect(jsonData['clientId'], equals('user-1'));
        expect(jsonData['data'], equals('hello'));
        expect(jsonData['extras']['headers']['x-key'], equals('x-value'));
      });

      // UTS: rest/unit/TP3a/presence-message-attributes-0.11
      test('serializes all action values to correct numeric wire values', () {
        for (final action in PresenceAction.values) {
          final msg = PresenceMessage(action: action, clientId: 'u');
          final jsonData = msg.toMap();
          expect(jsonData['action'], equals(action.index));
        }
      });
    });

    group('TP3 - Null/missing attributes omitted from serialization', () {
      // UTS: rest/unit/TP3/null-attributes-omitted-3
      test('null or missing optional attributes are omitted', () {
        const msg = PresenceMessage(
          action: PresenceAction.enter,
          clientId: 'user-1',
        );

        final jsonData = msg.toMap();

        expect(jsonData['action'], equals(2));
        expect(jsonData['clientId'], equals('user-1'));
        expect(jsonData.containsKey('data'), isFalse);
        expect(jsonData.containsKey('encoding'), isFalse);
        expect(jsonData.containsKey('extras'), isFalse);
        expect(jsonData.containsKey('id'), isFalse);
        expect(jsonData.containsKey('timestamp'), isFalse);
        expect(jsonData.containsKey('connectionId'), isFalse);
      });
    });

    group('TP4 - fromEncodedArray', () {
      // UTS: rest/unit/TP4/from-encoded-presence-0
      test('TP4 - fromEncodedArray deserializes array of presence messages',
          () {
        final rawArray = <Map<String, dynamic>>[
          {
            'action': 2,
            'clientId': 'alice',
            'data': 'hello',
          },
          {
            'action': 2,
            'clientId': 'bob',
            'data': 'world',
          },
        ];

        final messages = PresenceMessage.fromEncodedArray(rawArray);

        expect(messages.length, equals(2));
        expect(messages[0].clientId, equals('alice'));
        expect(messages[0].data, equals('hello'));
        expect(messages[0].action, equals(PresenceAction.enter));
        expect(messages[1].clientId, equals('bob'));
        expect(messages[1].data, equals('world'));
        expect(messages[1].action, equals(PresenceAction.enter));
      });

      // UTS: rest/unit/TP4/from-encoded-presence-0.1
      test('TP4 - fromEncodedArray handles empty array', () {
        final messages =
            PresenceMessage.fromEncodedArray(<Map<String, dynamic>>[]);
        expect(messages, isEmpty);
      });
    });

    group('TP3 - Round-trip serialization', () {
      // UTS: rest/unit/TP3g/timestamp-from-protocol-message-0
      test('PresenceMessage survives round-trip through toMap/fromMap', () {
        final original = PresenceMessage(
          id: 'round-trip-id',
          action: PresenceAction.update,
          clientId: 'user-42',
          connectionId: 'conn-42',
          data: 'round-trip-data',
          encoding: 'utf-8',
          timestamp: DateTime.fromMillisecondsSinceEpoch(9999999),
          extras: const MessageExtras(
            data: {
              'headers': {'x-round': 'trip'},
            },
          ),
        );

        final jsonData = original.toMap();
        final restored = PresenceMessage.fromMap(jsonData);

        expect(restored.id, equals(original.id));
        expect(restored.action, equals(original.action));
        expect(restored.clientId, equals(original.clientId));
        expect(restored.connectionId, equals(original.connectionId));
        expect(restored.data, equals(original.data));
        expect(restored.encoding, isNull);
        expect(
          restored.timestamp?.millisecondsSinceEpoch,
          equals(original.timestamp?.millisecondsSinceEpoch),
        );
        expect(
          restored.extras?.data['headers']['x-round'],
          equals('trip'),
        );
      });
    });

    group('TP - PresenceMessage equality', () {
      // UTS: rest/unit/TP3a/id-from-protocol-message-1
      test('messages with same id/action/clientId/connectionId are equal', () {
        const msg1 = PresenceMessage(
          id: 'same-id',
          action: PresenceAction.enter,
          clientId: 'user-1',
          connectionId: 'conn-1',
        );
        const msg2 = PresenceMessage(
          id: 'same-id',
          action: PresenceAction.enter,
          clientId: 'user-1',
          connectionId: 'conn-1',
        );
        const msg3 = PresenceMessage(
          id: 'different-id',
          action: PresenceAction.enter,
          clientId: 'user-1',
          connectionId: 'conn-1',
        );

        expect(msg1, equals(msg2));
        expect(msg1, isNot(equals(msg3)));
      });
    });
  });
}

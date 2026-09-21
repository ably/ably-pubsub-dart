import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

/// Unit tests for mutable message types (TM2j, TM2r, TM2s, TM5, TM8, MOP2, UDR2, TAN2).
///
/// These tests verify type construction and wire serialization for
/// mutable message types.
///
/// Spec: uts/test/rest/unit/types/mutable_message_types.md
void main() {
  group('TM5 - MessageAction enum values', () {
    // UTS: rest/unit/TM5/message-action-enum-values-0
    test('has correct numeric wire values', () {
      expect(MessageAction.messageCreate.toInt(), equals(0));
      expect(MessageAction.messageUpdate.toInt(), equals(1));
      expect(MessageAction.messageDelete.toInt(), equals(2));
      expect(MessageAction.meta.toInt(), equals(3));
      expect(MessageAction.messageSummary.toInt(), equals(4));
      expect(MessageAction.messageAppend.toInt(), equals(5));
    });

    // UTS: rest/unit/TM5/message-action-enum-values-0.1
    test('round-trips from int', () {
      expect(
        MessageActionExtension.fromInt(0),
        equals(MessageAction.messageCreate),
      );
      expect(
        MessageActionExtension.fromInt(1),
        equals(MessageAction.messageUpdate),
      );
      expect(
        MessageActionExtension.fromInt(2),
        equals(MessageAction.messageDelete),
      );
      expect(MessageActionExtension.fromInt(3), equals(MessageAction.meta));
      expect(
        MessageActionExtension.fromInt(4),
        equals(MessageAction.messageSummary),
      );
      expect(
        MessageActionExtension.fromInt(5),
        equals(MessageAction.messageAppend),
      );
    });
  });

  group('TM2j, TM2r - Message action and serial fields', () {
    // UTS: rest/unit/TM2j/action-and-serial-fields-0
    test('supports action and serial with correct wire serialization', () {
      const msg = Message(
        name: 'test',
        data: 'hello',
        serial: 'serial-1',
        action: MessageAction.messageUpdate,
      );

      expect(msg.serial, equals('serial-1'));
      expect(msg.action, equals(MessageAction.messageUpdate));

      final json = msg.toJson();
      expect(json['serial'], equals('serial-1'));
      expect(json['action'], equals(1));
      expect(json['name'], equals('test'));
      expect(json['data'], equals('hello'));
    });
  });

  group('TM2s - Message.version populated from wire', () {
    // UTS: rest/unit/TM2s/version-populated-from-wire-0
    test('parses version object with all fields', () {
      final msg = Message.fromJson({
        'serial': 'msg-serial-1',
        'name': 'test',
        'data': 'hello',
        'version': {
          'serial': 'version-serial-1',
          'timestamp': 1700000001000,
          'clientId': 'editor-1',
          'description': 'fixed typo',
          'metadata': {'reason': 'typo', 'tool': 'editor'},
        },
      });

      expect(msg.version, isNotNull);
      expect(msg.version, isA<MessageVersion>());
      expect(msg.version!.serial, equals('version-serial-1'));
      expect(msg.version!.timestamp, equals(1700000001000));
      expect(msg.version!.clientId, equals('editor-1'));
      expect(msg.version!.description, equals('fixed typo'));
      expect(msg.version!.metadata!['reason'], equals('typo'));
      expect(msg.version!.metadata!['tool'], equals('editor'));
    });
  });

  group('TM2s1, TM2s2 - Message.version defaults when not on wire', () {
    // UTS: rest/unit/TM2s1/version-defaults-from-message-0
    test('initializes version from serial and timestamp', () {
      final msg = Message.fromJson({
        'serial': 'msg-serial-1',
        'timestamp': 1700000000000,
        'name': 'test',
        'data': 'hello',
      });

      expect(msg.version, isNotNull);
      expect(msg.version, isA<MessageVersion>());
      expect(msg.version!.serial, equals('msg-serial-1'));
      expect(msg.version!.timestamp, equals(1700000000000));
      expect(msg.version!.clientId, isNull);
      expect(msg.version!.description, isNull);
      expect(msg.version!.metadata, isNull);
    });
  });

  group('TM2u, TM8a - Message.annotations defaults to empty', () {
    // UTS: rest/unit/TM2u/annotations-defaults-empty-0
    test('initializes empty annotations when not on wire', () {
      final msg = Message.fromJson({
        'serial': 'msg-serial-1',
        'name': 'test',
      });

      expect(msg.annotations, isNotNull);
      expect(msg.annotations, isA<MessageAnnotations>());
      expect(msg.annotations!.summary, isNotNull);
      expect(msg.annotations!.summary, isEmpty);
    });
  });

  group('MOP2a-c - MessageOperation fields', () {
    // UTS: rest/unit/MOP2a/message-operation-fields-0
    test('constructs with all fields and serializes correctly', () {
      const op = MessageOperation(
        clientId: 'user-1',
        description: 'edit description',
        metadata: {'reason': 'typo', 'tool': 'editor'},
      );

      expect(op.clientId, equals('user-1'));
      expect(op.description, equals('edit description'));
      expect(op.metadata!['reason'], equals('typo'));
      expect(op.metadata!['tool'], equals('editor'));

      final json = op.toMap();
      expect(json['clientId'], equals('user-1'));
      expect(json['description'], equals('edit description'));
      expect((json['metadata'] as Map)['reason'], equals('typo'));
    });

    // UTS: rest/unit/MOP2a/message-operation-fields-0.1
    test('omits null fields from serialization', () {
      const emptyOp = MessageOperation();

      expect(emptyOp.clientId, isNull);
      expect(emptyOp.description, isNull);
      expect(emptyOp.metadata, isNull);

      final json = emptyOp.toMap();
      expect(json.containsKey('clientId'), isFalse);
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });
  });

  group('UDR2a - UpdateDeleteResult fields', () {
    // UTS: rest/unit/UDR2a/update-delete-result-fields-0
    test('parses versionSerial from response map', () {
      final result1 = UpdateDeleteResult.fromMap(
        {'versionSerial': 'version-serial-abc'},
      );
      expect(result1, isA<UpdateDeleteResult>());
      expect(result1.versionSerial, equals('version-serial-abc'));

      final result2 = UpdateDeleteResult.fromMap(
        {'versionSerial': null},
      );
      expect(result2.versionSerial, isNull);

      final result3 = UpdateDeleteResult.fromMap({});
      expect(result3.versionSerial, isNull);
    });
  });

  group('TAN2 - Annotation type and action encoding', () {
    // UTS: rest/unit/TAN2/annotation-attributes-and-action-0
    test('fromMap decodes all fields correctly', () {
      final ann = Annotation.fromMap({
        'id': 'ann-id-1',
        'action': 0,
        'clientId': 'user-1',
        'name': 'like',
        'count': 5,
        'data': 'thumbs-up',
        'encoding': null,
        'timestamp': 1700000000000,
        'serial': 'ann-serial-1',
        'messageSerial': 'msg-serial-1',
        'type': 'com.example.reaction',
        'extras': {'custom': 'metadata'},
      });

      expect(ann, isA<Annotation>());
      expect(ann.id, equals('ann-id-1'));
      expect(ann.action, equals(AnnotationAction.annotationCreate));
      expect(ann.clientId, equals('user-1'));
      expect(ann.name, equals('like'));
      expect(ann.count, equals(5));
      expect(ann.data, equals('thumbs-up'));
      expect(ann.timestamp, equals(1700000000000));
      expect(ann.serial, equals('ann-serial-1'));
      expect(ann.messageSerial, equals('msg-serial-1'));
      expect(ann.type, equals('com.example.reaction'));
    });

    // UTS: rest/unit/TAN2/annotation-attributes-and-action-0.1
    test('AnnotationAction has correct numeric values', () {
      expect(AnnotationAction.annotationCreate.toInt(), equals(0));
      expect(AnnotationAction.annotationDelete.toInt(), equals(1));
      expect(
        AnnotationActionExtension.fromInt(0),
        equals(AnnotationAction.annotationCreate),
      );
      expect(
        AnnotationActionExtension.fromInt(1),
        equals(AnnotationAction.annotationDelete),
      );
    });
  });
}

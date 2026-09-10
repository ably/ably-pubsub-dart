import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ably_pubsub_device/src/message/message.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:test/test.dart';

/// RSL6a3 - MessagePack interoperability tests using ably-common fixtures.
///
/// UTS: rest/unit/RSL6a3/msgpack-interop
void main() {
  late List<dynamic> fixtures;

  setUpAll(() {
    final fixtureFile = File(
      'submodules/ably-common/test-resources/msgpack_test_fixtures.json',
    );
    fixtures = json.decode(fixtureFile.readAsStringSync()) as List<dynamic>;
  });

  group('RSL6a3 - msgpack interoperability fixtures', () {
    test('fixtures file is loaded with expected entries', () {
      expect(fixtures, isNotEmpty);
      expect(fixtures.length, equals(8));
    });

    for (final fixtureName in [
      'json array',
      'short string',
      '200 character string',
      '2000 character string',
      'short binary',
      '200 byte binary',
      '2000 byte binary',
      'an object',
    ]) {
      // UTS: rest/unit/RSL6a3/msgpack-interop-decode
      test('decodes "$fixtureName" fixture correctly', () {
        final fixture = fixtures.firstWhere(
          (f) => (f as Map<String, dynamic>)['name'] == fixtureName,
        ) as Map<String, dynamic>;

        final msgpackBytes = base64.decode(fixture['msgpack'] as String);
        final protocolMessage =
            _deepCast(msgpack.deserialize(Uint8List.fromList(msgpackBytes)))
                as Map<String, dynamic>;

        final messages = protocolMessage['messages'] as List;
        expect(messages, hasLength(1));

        final wireMessage = _deepCast(messages[0]) as Map<String, dynamic>;
        final message = Message.fromMap(wireMessage);

        expect(message.encoding, isNull);

        final expected = _buildExpected(fixture);
        final type = fixture['type'] as String;

        if (type == 'binary') {
          expect(message.data, isA<Uint8List>());
          expect(
            (message.data! as Uint8List).toList(),
            equals((expected as Uint8List).toList()),
          );
        } else if (type == 'jsonArray') {
          expect(message.data, isA<List>());
          expect(message.data, equals(expected));
        } else if (type == 'jsonObject') {
          expect(message.data, isA<Map>());
          expect(message.data, equals(expected));
        } else {
          expect(message.data, isA<String>());
          expect(message.data, equals(expected));
        }
      });
    }

    for (final fixtureName in [
      'json array',
      'short string',
      '200 character string',
      '2000 character string',
      'short binary',
      '200 byte binary',
      '2000 byte binary',
      'an object',
    ]) {
      // UTS: rest/unit/RSL6a3/msgpack-interop-roundtrip
      test('round-trips "$fixtureName" fixture through encode/decode', () {
        final fixture = fixtures.firstWhere(
          (f) => (f as Map<String, dynamic>)['name'] == fixtureName,
        ) as Map<String, dynamic>;

        final msgpackBytes = base64.decode(fixture['msgpack'] as String);
        final protocolMessage =
            _deepCast(msgpack.deserialize(Uint8List.fromList(msgpackBytes)))
                as Map<String, dynamic>;

        final wireMessage =
            _deepCast(protocolMessage['messages']![0]) as Map<String, dynamic>;
        final message = Message.fromMap(wireMessage);

        final reEncoded = message.toMap(useBinaryProtocol: true);
        final reProtocolMessage = <String, dynamic>{
          'messages': [reEncoded],
          'msgSerial': 0,
        };

        final reBytes = msgpack.serialize(reProtocolMessage);
        final reParsed =
            _deepCast(msgpack.deserialize(reBytes)) as Map<String, dynamic>;
        final reWireMessage =
            _deepCast(reParsed['messages']![0]) as Map<String, dynamic>;
        final reMessage = Message.fromMap(reWireMessage);

        expect(reMessage.encoding, isNull);

        final type = fixture['type'] as String;
        if (type == 'binary') {
          expect(
            (reMessage.data! as Uint8List).toList(),
            equals((message.data! as Uint8List).toList()),
          );
        } else {
          expect(reMessage.data, equals(message.data));
        }
      });
    }
  });
}

Object _buildExpected(Map<String, dynamic> fixture) {
  final type = fixture['type'] as String;
  final numRepeat = fixture['numRepeat'] as int;

  if (type == 'string') {
    final base = fixture['data'] as String;
    if (numRepeat <= 0) return base;
    return base * numRepeat;
  } else if (type == 'binary') {
    final base = fixture['data'] as String;
    final repeated = base * numRepeat;
    return Uint8List.fromList(utf8.encode(repeated));
  } else {
    return fixture['data'];
  }
}

dynamic _deepCast(dynamic value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (k, v) => MapEntry(k.toString(), _deepCast(v)),
    );
  }
  if (value is Uint8List) return value;
  if (value is List) return value.map(_deepCast).toList();
  return value;
}

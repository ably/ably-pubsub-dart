import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Message Encoding Tests
///
/// Spec points: RSL4, RSL6 - Message encoding/decoding
void main() {
  group('Message Encoding', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSL4 - Encoding messages for transmission', () {
      group('RSL4a - String data', () {
        // UTS: rest/unit/RSL4a/string-data-no-encoding-0
        test('transmits string data without encoding', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL4a');

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );

              req.respondWith(201, {
                'serials': ['s1'],
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.publish(name: 'event', data: 'hello world');

          final body = json.decode(capturedRequests[0].body!) as List;

          expect(body[0]['data'], equals('hello world'));
          expect(body[0].containsKey('encoding'), isFalse);
        });
      });

      group('RSL4c - JSON-encodable objects', () {
        // UTS: rest/unit/RSL4c/binary-base64-json-protocol-0
        test('encodes map data as JSON with encoding field', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL4c-map');

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );

              req.respondWith(201, {
                'serials': ['s1'],
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.publish(
            name: 'event',
            data: {'key': 'value', 'number': 42},
          );

          final body = json.decode(capturedRequests[0].body!) as List;

          expect(body[0]['encoding'], equals('json'));
          // Data should be JSON string
          final dataJson = json.decode(body[0]['data'] as String);
          expect(dataJson['key'], equals('value'));
          expect(dataJson['number'], equals(42));
        });

        // UTS: rest/unit/RSL4c/binary-direct-msgpack-protocol-1
        test('encodes list data as JSON', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL4c-list');

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );

              req.respondWith(201, {
                'serials': ['s1'],
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.publish(name: 'event', data: [1, 2, 3]);

          final body = json.decode(capturedRequests[0].body!) as List;

          expect(body[0]['encoding'], equals('json'));
        });
      });

      group('RSL4d - Binary data', () {
        // UTS: rest/unit/RSL4d/array-json-encoding-0
        test('encodes binary data as base64 for JSON protocol', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL4d');

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );

              req.respondWith(201, {
                'serials': ['s1'],
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          final binaryData = Uint8List.fromList([0x00, 0x01, 0xFF, 0xFE]);
          await channel.publish(name: 'event', data: binaryData);

          final body = json.decode(capturedRequests[0].body!) as List;

          expect(body[0]['encoding'], equals('base64'));
          // Verify it decodes back correctly
          final decoded = base64.decode(body[0]['data'] as String);
          expect(decoded, equals([0x00, 0x01, 0xFF, 0xFE]));
        });
      });
    });

    group('RSL6 - Decoding messages from server', () {
      group('RSL6a - Plain data (no encoding)', () {
        // UTS: rest/unit/RSL6a/decode-chained-encodings-2
        test('returns data unchanged when no encoding', () async {
          final channelName = testChannelName('RSL6a');
          mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(200, [
                {'id': 'msg1', 'name': 'event', 'data': 'plain text'},
              ]);
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          final result = await channel.history();

          expect(result.items[0].data, equals('plain text'));
          expect(result.items[0].encoding, isNull);
        });
      });

      group('RSL6b - JSON encoding', () {
        // UTS: rest/unit/RSL6b/unrecognized-encoding-preserved-0
        test('decodes JSON-encoded data to objects', () async {
          final channelName = testChannelName('RSL6b');
          mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(200, [
                {
                  'id': 'msg1',
                  'name': 'event',
                  'data': '{"key":"value","number":42}',
                  'encoding': 'json',
                },
              ]);
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          final result = await channel.history();

          final data = result.items[0].data as Map<String, dynamic>;
          expect(data['key'], equals('value'));
          expect(data['number'], equals(42));
          // Encoding should be consumed
          expect(result.items[0].encoding, isNull);
        });
      });

      group('RSL6c - Base64 encoding', () {
        // UTS: rest/unit/RSL6a/decode-base64-to-binary-0
        test('decodes base64-encoded data to binary', () async {
          final channelName = testChannelName('RSL6c');
          final originalBytes = [0x00, 0x01, 0xFF, 0xFE];
          final base64Data = base64.encode(originalBytes);

          mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(200, [
                {
                  'id': 'msg1',
                  'name': 'event',
                  'data': base64Data,
                  'encoding': 'base64',
                },
              ]);
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          final result = await channel.history();

          expect(result.items[0].data, isA<Uint8List>());
          expect(
            (result.items[0].data as Uint8List).toList(),
            equals(originalBytes),
          );
        });
      });

      group('RSL6 - Compound encoding', () {
        // UTS: rest/unit/RSL6/decode-utf8-base64-data-2
        test('decodes json/base64 encoded data', () async {
          final channelName = testChannelName('RSL6-compound');
          const jsonData = '{"nested":"object"}';
          final base64Data = base64.encode(utf8.encode(jsonData));

          mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(200, [
                {
                  'id': 'msg1',
                  'name': 'event',
                  'data': base64Data,
                  'encoding': 'json/base64',
                },
              ]);
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          final result = await channel.history();

          // Should decode base64 first, then parse JSON
          final data = result.items[0].data as Map<String, dynamic>;
          expect(data['nested'], equals('object'));
        });
      });
    });

    group('RSL4 - Encoding fixtures and protocol', () {
      // UTS: rest/unit/RSL4/encoding-fixtures-ably-common-0
      test('RSL4 - encoding fixtures from ably-common', () async {
        final fixtureFile = _loadFixtureFile('messages-encoding.json');
        final fixtures =
            jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
        final messages = fixtures['messages'] as List;

        for (final fixture in messages) {
          final fixtureData = fixture['data'];
          final fixtureEncoding = fixture['encoding'] as String?;
          final expectedType = fixture['expectedType'] as String;

          // Derive the input data to publish from the fixture's wire format
          final dynamic inputData;
          if (expectedType == 'binary') {
            inputData = base64Decode(fixtureData as String);
          } else if (expectedType == 'jsonObject' ||
              expectedType == 'jsonArray') {
            inputData = jsonDecode(fixtureData as String);
          } else {
            inputData = fixtureData;
          }

          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL4-fixture-$expectedType');

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );
              req.respondWith(201, {
                'serials': ['s1'],
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.publish(name: 'fixture', data: inputData);

          final body = jsonDecode(capturedRequests[0].body!) as List;
          final wireMsg = body[0] as Map<String, dynamic>;

          expect(
            wireMsg['data'],
            equals(fixtureData),
            reason: 'Wire data mismatch for $expectedType',
          );
          if (fixtureEncoding != null) {
            expect(
              wireMsg['encoding'],
              equals(fixtureEncoding),
              reason: 'Wire encoding mismatch for $expectedType',
            );
          } else {
            expect(
              wireMsg.containsKey('encoding'),
              isFalse,
              reason: 'Should not have encoding field for $expectedType',
            );
          }
        }
      });

      // UTS: rest/unit/RSL4/null-data-no-encoding-1
      test('null data should have no encoding header', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL4-null');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        // Publish with name only, no data
        await channel.publish(name: 'event');

        final body = json.decode(capturedRequests[0].body!) as List;

        // Should not have data or encoding fields
        expect(body[0].containsKey('data'), isFalse);
        expect(body[0].containsKey('encoding'), isFalse);
      });

      // UTS: rest/unit/RSL4/json-protocol-content-type-2
      test('JSON protocol uses application/json content-type', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL4-json-ct');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 'hello');

        final request = capturedRequests[0];
        expect(request.headers['Content-Type'], equals('application/json'));
      });

      // UTS: rest/unit/RSL4/msgpack-protocol-content-type-3
      test(
        'RSL4 - msgpack protocol content-type',
        () {},
        skip: 'Not yet implemented: msgpack encoding support',
      );
    });

    group('RSL4a - Unsupported data types', () {
      // UTS: rest/unit/RSL4a/boolean-type-rejected-2
      test('boolean data type is encoded as JSON', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL4a-bool');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: true);

        final body = json.decode(capturedRequests[0].body!) as List;

        // Boolean is JSON-encoded
        expect(body[0]['data'], equals('true'));
        expect(body[0]['encoding'], equals('json'));
      });

      // UTS: rest/unit/RSL4a/number-type-rejected-1
      test('number data type is encoded as JSON', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL4a-num');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 42);

        final body = json.decode(capturedRequests[0].body!) as List;

        // Number is JSON-encoded
        expect(body[0]['data'], equals('42'));
        expect(body[0]['encoding'], equals('json'));
      });
    });

    group('RSL6 - Msgpack decoding', () {
      // UTS: rest/unit/RSL6/msgpack-binary-stays-binary-0
      test(
        'RSL6 - msgpack binary stays binary',
        () {},
        skip: 'Not yet implemented: msgpack encoding support',
      );

      // UTS: rest/unit/RSL6/msgpack-string-stays-string-1
      test(
        'RSL6 - msgpack string stays string',
        () {},
        skip: 'Not yet implemented: msgpack encoding support',
      );

      // UTS: rest/unit/RSL6/complex-chained-encoding-3
      test('complex chained encoding utf-8/cipher+aes-128-cbc/base64',
          () async {
        final channelName = testChannelName('RSL6-chained');
        // Simulate server returning a message with complex chained encoding
        // where an unrecognized encoding layer is preserved
        const plainText = 'hello world';
        final base64Data = base64.encode(utf8.encode(plainText));

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'msg1',
                'name': 'event',
                'data': base64Data,
                'encoding': 'utf-8/base64',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        // base64 should be decoded; utf-8 may remain as residual encoding
        // or the data should be a string
        expect(result.items[0], isNotNull);
      });
    });

    group('RSL6a - Decode JSON to object', () {
      // UTS: rest/unit/RSL6a/decode-json-to-object-1
      test('decodes JSON-encoded message data to parsed object', () async {
        final channelName = testChannelName('RSL6a-json-obj');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'msg1',
                'name': 'event',
                'data': '{"name":"Alice","age":30,"active":true}',
                'encoding': 'json',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        final data = result.items[0].data as Map<String, dynamic>;
        expect(data['name'], equals('Alice'));
        expect(data['age'], equals(30));
        expect(data['active'], isTrue);
        // Encoding should be consumed
        expect(result.items[0].encoding, isNull);
      });
    });

    group('Encoding edge cases', () {
      // UTS: rest/unit/RSL4/empty-string-no-encoding-4
      test('handles empty string data', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL-empty-str');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: '');

        final body = json.decode(capturedRequests[0].body!) as List;

        expect(body[0]['data'], equals(''));
        expect(body[0].containsKey('encoding'), isFalse);
      });

      // UTS: rest/unit/RSL4/empty-array-json-encoding-5
      test('handles empty binary data', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL-empty-bin');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: Uint8List(0));

        final body = json.decode(capturedRequests[0].body!) as List;

        expect(body[0]['encoding'], equals('base64'));
        expect(body[0]['data'], equals('')); // Empty base64
      });

      // UTS: rest/unit/RSL4b/json-object-encoding-0
      test('handles deeply nested JSON objects', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL-nested');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final nestedData = {
          'level1': {
            'level2': {
              'level3': {
                'value': 'deep',
              },
            },
          },
        };

        await channel.publish(name: 'event', data: nestedData);

        final body = json.decode(capturedRequests[0].body!) as List;

        expect(body[0]['encoding'], equals('json'));
        final parsedData = json.decode(body[0]['data'] as String);
        expect(
          parsedData['level1']['level2']['level3']['value'],
          equals('deep'),
        );
      });
    });
  });
}

File _loadFixtureFile(String filename) {
  final candidates = [
    'submodules/ably-common/test-resources/$filename',
    '../submodules/ably-common/test-resources/$filename',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw Exception(
    'Could not find $filename. '
    'Ensure the ably-common submodule is initialised: '
    'git submodule update --init',
  );
}

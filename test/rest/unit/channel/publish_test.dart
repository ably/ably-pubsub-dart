import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// REST Channel Publish Tests
///
/// Spec points: RSL1, RSL1a, RSL1b, RSL1c, RSL1d, RSL1e, RSL1h, RSL1i, RSL1j,
///              RSL1l, RSL1m
void main() {
  group('Channel Publish', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSL1a, RSL1b - Publish with name and data', () {
      // UTS: rest/unit/RSL1a/publish-name-and-data-0
      test('sends a single message', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1a');

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
              'serials': ['serial1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'greeting', data: 'hello');

        final request = capturedRequests[0];

        // RSL1b - single message published
        expect(request.method, equals('POST'));
        expect(
          request.url.path,
          equals('/channels/${Uri.encodeComponent(channelName)}/messages'),
        );

        final body = json.decode(request.body!) as List;
        expect(body.length, equals(1));
        expect(body[0]['name'], equals('greeting'));
        expect(body[0]['data'], equals('hello'));
      });
    });

    group('RSL1a, RSL1c - Publish with Message array', () {
      // UTS: rest/unit/RSL1a/publish-message-array-1
      test('sends all messages in a single request', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1c');

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
              'serials': ['s1', 's2', 's3'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final messages = [
          const Message(name: 'event1', data: 'data1'),
          const Message(name: 'event2', data: {'key': 'value'}),
          const Message(name: 'event3', data: 'data3'),
        ];
        await channel.publish(messages: messages);

        // RSL1c - single request for array
        expect(capturedRequests.length, equals(1));

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        expect(body.length, equals(3));
        expect(body[0]['name'], equals('event1'));
        expect(body[0]['data'], equals('data1'));
        expect(body[1]['name'], equals('event2'));
      });
    });

    group('RSL1e - Null name and data', () {
      final testCases = [
        (
          name: null as String?,
          data: 'hello',
          description: 'null name',
        ),
        (
          name: 'event',
          data: null as Object?,
          description: 'null data',
        ),
        (
          name: null as String?,
          data: null as Object?,
          description: 'both null',
        ),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/RSL1e/null-name-and-data-0
        test('handles ${testCase.description}', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL1e');

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
            options: ClientOptions.fromKey(
              'appId.keyId:keySecret',
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.publish(name: testCase.name, data: testCase.data);

          final body = json.decode(capturedRequests[0].body!) as List;

          if (testCase.name == null) {
            expect(body[0].containsKey('name'), isFalse);
          } else {
            expect(body[0]['name'], equals(testCase.name));
          }

          if (testCase.data == null) {
            expect(body[0].containsKey('data'), isFalse);
          } else {
            expect(body[0]['data'], equals(testCase.data));
          }
        });
      }
    });

    group('RSL1h - publish(name, data) signature', () {
      // UTS: rest/unit/RSL1h/publish-signature-0
      test('accepts name and data arguments', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1h');

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
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 'payload');

        expect(capturedRequests.length, equals(1));
        final body = json.decode(capturedRequests[0].body!) as List;
        expect(body[0]['name'], equals('event'));
        expect(body[0]['data'], equals('payload'));
      });
    });

    group('RSL1i - Message size limit', () {
      // UTS: rest/unit/RSL1i/message-size-limit-0
      test('rejects messages exceeding maxMessageSize', () async {
        final channelName = testChannelName('RSL1i-reject');
        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            maxMessageSize: 1024, // 1KB limit for testing
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        // Create data exceeding limit
        final largeData = 'x' * 2000;

        expect(
          () => channel.publish(name: 'event', data: largeData),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40009),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSL1i/message-size-limit-0.1
      test('accepts messages at or under maxMessageSize', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1i-accept');

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
            maxMessageSize: 1024,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        // Create data under limit
        final smallData = 'x' * 500;

        await channel.publish(name: 'event', data: smallData);
        expect(capturedRequests.length, equals(1));
      });
    });

    group('RSL1j - All Message attributes transmitted', () {
      // UTS: rest/unit/RSL1j/all-attributes-transmitted-0
      test('includes all valid Message attributes', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1j');

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
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        const message = Message(
          name: 'test-event',
          data: 'test-data',
          id: 'custom-message-id',
          extras: MessageExtras(
            data: {
              'push': {
                'notification': {'title': 'Test'},
              },
            },
          ),
        );

        await channel.publish(message: message);

        final body = json.decode(capturedRequests[0].body!) as List;

        expect(body[0]['name'], equals('test-event'));
        expect(body[0]['data'], equals('test-data'));
        expect(body[0]['id'], equals('custom-message-id'));
        expect(
          body[0]['extras']['push']['notification']['title'],
          equals('Test'),
        );
      });
    });

    group('RSL1l - Publish params as querystring', () {
      // UTS: rest/unit/RSL1l/params-as-querystring-0
      test('sends additional params as querystring', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1l');

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
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(
          message: const Message(name: 'event', data: 'data'),
          params: {
            'customParam': 'customValue',
            'anotherParam': '123',
          },
        );

        final request = capturedRequests[0];

        expect(
          request.url.queryParameters['customParam'],
          equals('customValue'),
        );
        expect(
          request.url.queryParameters['anotherParam'],
          equals('123'),
        );
      });
    });

    group('RSL1m - ClientId not set from library clientId', () {
      // UTS: rest/unit/RSL1m/clientid-not-injected-0
      test('RSL1m1 - message with no clientId, library has clientId', () async {
        final capturedRequests = <CapturedRequest>[];

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

            if (req.url.path.contains('requestToken')) {
              // Token request (RSA4b: key + clientId triggers token auth)
              req.respondWith(200, {
                'token': 'test-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
              });
            } else {
              // Publish response
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final clientWithId = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            clientId: 'lib-client',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await clientWithId.channels.get('ch').publish(name: 'e', data: 'd');

        // First request is token request, second is publish
        final publishRequest = capturedRequests.firstWhere(
          (req) => req.url.path.contains('/messages'),
        );
        final body = json.decode(publishRequest.body!) as List;
        // Library should not inject its clientId
        expect(body[0].containsKey('clientId'), isFalse);
      });

      // UTS: rest/unit/RSL1m/clientid-not-injected-0.1
      test('RSL1m2 - message clientId matches library clientId', () async {
        final capturedRequests = <CapturedRequest>[];

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

            if (req.url.path.contains('requestToken')) {
              // Token request (RSA4b: key + clientId triggers token auth)
              req.respondWith(200, {
                'token': 'test-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
              });
            } else {
              // Publish response
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final clientWithId = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            clientId: 'lib-client',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await clientWithId.channels.get('ch').publish(
              message:
                  const Message(name: 'e', data: 'd', clientId: 'lib-client'),
            );

        // First request is token request, second is publish
        final publishRequest = capturedRequests.firstWhere(
          (req) => req.url.path.contains('/messages'),
        );
        final body = json.decode(publishRequest.body!) as List;
        // Explicit clientId preserved
        expect(body[0]['clientId'], equals('lib-client'));
      });

      // UTS: rest/unit/RSL1m/clientid-not-injected-0.2
      test('RSL1m3 - unidentified client with message clientId', () async {
        final capturedRequests = <CapturedRequest>[];

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

        final clientNoId = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await clientNoId.channels.get('ch').publish(
              message:
                  const Message(name: 'e', data: 'd', clientId: 'msg-client'),
            );

        final body = json.decode(capturedRequests[0].body!) as List;
        expect(body[0]['clientId'], equals('msg-client'));
      });
    });
  });
}

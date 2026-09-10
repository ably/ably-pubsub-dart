import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_client.dart';

/// Client request() Tests
///
/// Tests the shared request() implementation in BaseClientImpl via TestClient.
///
/// Spec points: RSC19, RTC9, HP1-HP8
void main() {
  group('REST Client request()', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSC19f - Method and parameters', () {
      // UTS: rest/unit/RSC19f/supports-http-methods-0
      test('supports GET method', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.method, equals('GET'));
      });

      // UTS: rest/unit/RSC19f/supports-http-methods-0.1
      test('supports POST method', () async {
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

            req.respondWith(201, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('POST', '/test', body: {'data': 'value'});

        final request = capturedRequests[0];
        expect(request.method, equals('POST'));
      });

      // UTS: rest/unit/RSC19f/supports-http-methods-0.2
      test('supports PUT method', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('PUT', '/test', body: {'data': 'value'});

        final request = capturedRequests[0];
        expect(request.method, equals('PUT'));
      });

      // UTS: rest/unit/RSC19f/supports-http-methods-0.3
      test('supports PATCH method', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('PATCH', '/test', body: {'data': 'value'});

        final request = capturedRequests[0];
        expect(request.method, equals('PATCH'));
      });

      // UTS: rest/unit/RSC19f/supports-http-methods-0.4
      test('supports DELETE method', () async {
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

            req.respondWith(204, '');
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('DELETE', '/test');

        final request = capturedRequests[0];
        expect(request.method, equals('DELETE'));
      });

      // UTS: rest/unit/RSC19f/query-params-passed-1
      test('query parameters passed correctly', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request(
          'GET',
          '/test',
          params: {'foo': 'bar', 'baz': '123'},
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['foo'], equals('bar'));
        expect(request.url.queryParameters['baz'], equals('123'));
      });

      // UTS: rest/unit/RSC19f/custom-headers-passed-2
      test('custom headers passed correctly', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request(
          'GET',
          '/test',
          headers: {'X-Custom-Header': 'custom-value'},
        );

        final request = capturedRequests[0];
        expect(request.headers['X-Custom-Header'], equals('custom-value'));
      });

      // UTS: rest/unit/RSC19f/request-body-sent-3
      test('request body sent correctly', () async {
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

            req.respondWith(201, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request(
          'POST',
          '/test',
          body: {'name': 'test', 'value': 42},
        );

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as Map;
        expect(body['name'], equals('test'));
        expect(body['value'], equals(42));
      });
    });

    group('RSC19f1 - Version parameter', () {
      // UTS: rest/unit/RSC19f1/version-param-sets-header-0
      test('uses explicit version parameter when provided', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test', version: 3);

        final request = capturedRequests[0];
        expect(request.headers['X-Ably-Version'], equals('3'));
      });

      // UTS: rest/unit/RSC19f1/version-param-sets-header-0.1
      test('uses default version when not provided', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['X-Ably-Version'], equals('5'));
      });
    });

    group('RSC19b - Authentication', () {
      // UTS: rest/unit/RSC19b/uses-configured-auth-0
      test('uses configured Basic authentication', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['Authorization'], startsWith('Basic '));
      });

      // UTS: rest/unit/RSC19b/uses-configured-auth-0.1
      test('uses configured Token authentication', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions(token: 'test-token', useBinaryProtocol: false),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['Authorization'], equals('Bearer test-token'));
      });

      // UTS: rest/unit/RSC19b/cannot-override-auth-1
      test('cannot override authentication header', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request(
          'GET',
          '/test',
          headers: {'Authorization': 'Bearer malicious-token'},
        );

        final request = capturedRequests[0];
        // Should still use Basic auth, not the custom header
        expect(request.headers['Authorization'], startsWith('Basic '));
      });
    });

    group('RSC19c - Protocol handling', () {
      // UTS: rest/unit/RSC19c/protocol-headers-json-0
      test('JSON protocol sets correct headers', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['Accept'], equals('application/json'));
      });

      // UTS: rest/unit/RSC19c/protocol-headers-msgpack-1
      test('MsgPack protocol sets correct headers', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['Accept'], equals('application/x-msgpack'));
      });

      // UTS: rest/unit/RSC19c/body-encoded-per-protocol-2
      test('request body encoded according to protocol', () async {
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

            req.respondWith(201, []);
          },
        );

        final client = TestClient(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('POST', '/test', body: {'data': 'value'});

        final request = capturedRequests[0];
        expect(request.headers['Content-Type'], equals('application/json'));
        expect(request.body, equals('{"data":"value"}'));
      });
    });

    group('RSC19d, HP - HttpPaginatedResponse', () {
      // UTS: rest/unit/RSC19d/response-status-code-0
      test('HP4 - provides status code', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(201, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('POST', '/test');

        expect(response.statusCode, equals(201));
      });

      // UTS: rest/unit/RSC19d/response-success-indicator-1
      test('HP5 - provides success indicator', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.success, isTrue);
      });

      // UTS: rest/unit/RSC19d/response-error-code-header-2
      test('HP6 - error code from header when error response', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            // 4xx errors throw AblyException
            req.respondWith(
              400,
              {
                'error': {'message': 'Bad request', 'code': 40000},
              },
              headers: {'X-Ably-Errorcode': '40000'},
            );
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        try {
          await client.request('GET', '/test');
          fail('Expected AblyException');
        } on AblyException catch (e) {
          expect(e.code, equals(40000));
        }
      });

      // UTS: rest/unit/RSC19d/response-error-message-header-3
      test('HP7 - error message from header when error response', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              400,
              {
                'error': {'message': 'Invalid request', 'code': 40000},
              },
              headers: {'X-Ably-Errormessage': 'Invalid request'},
            );
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await expectLater(
          client.request('GET', '/test'),
          throwsA(
            isA<AblyException>().having(
              (e) => e.message,
              'message',
              contains('Invalid request'),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSC19d/response-headers-accessible-4
      test('HP8 - provides all response headers', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [],
              headers: {
                'X-Custom-Header': 'custom-value',
                'Content-Type': 'application/json',
              },
            );
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.headers['x-custom-header'], equals('custom-value'));
        expect(response.headers['content-type'], equals('application/json'));
      });

      // UTS: rest/unit/RSC19d/response-items-decoded-5
      test('HP3 - provides response items', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {'id': '1', 'name': 'item1'},
              {'id': '2', 'name': 'item2'},
            ]);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.items.length, equals(2));
        expect(response.items[0]['id'], equals('1'));
        expect(response.items[1]['name'], equals('item2'));
      });

      // UTS: rest/unit/RSC19d/pagination-with-link-headers-6
      test('HP1 - pagination support with Link header', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': '1'},
              ],
              headers: {'Link': '</test?page=2>; rel="next"'},
            );
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.hasNext(), isTrue);
        expect(response.isLast(), isFalse);
      });

      // UTS: rest/unit/RSC19d/non-array-response-handling-7
      test('non-array response handling', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {'single': 'object'});
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        // Non-array responses are wrapped in a list
        expect(response.items.length, equals(1));
        expect(response.items[0]['single'], equals('object'));
      });

      // UTS: rest/unit/RSC19d/empty-response-handling-8
      test('empty response handling (204 No Content)', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(204, '');
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('DELETE', '/test');

        expect(response.statusCode, equals(204));
        expect(response.items, isEmpty);
      });
    });

    group('RSC19e - Error handling', () {
      // UTS: rest/unit/RSC19e/network-error-propagated-0
      test('network error handling', () async {
        mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) {
            conn.respondWithRefused();
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(
          () => client.request('GET', '/test'),
          throwsA(isA<AblyException>()),
        );
      });

      // UTS: rest/unit/RSC19e/timeout-error-handling-1
      test('timeout error handling', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWithTimeout();
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(
          () => client.request('GET', '/test'),
          throwsA(isA<AblyException>()),
        );
      });
    });

    group('RSC19f - Path handling', () {
      // UTS: rest/unit/RSC19f/path-leading-slash-handling-4
      test('path with leading slash', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/channels/test/messages');

        final request = capturedRequests[0];
        expect(request.url.path, equals('/channels/test/messages'));
      });

      // UTS: rest/unit/RSC19f/path-leading-slash-handling-4.1
      test('path without leading slash', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', 'channels/test/messages');

        final request = capturedRequests[0];
        expect(request.url.path, equals('/channels/test/messages'));
      });
    });

    group('Request headers', () {
      // UTS: rest/unit/RSC19f/custom-headers-passed-2.1
      test('includes standard Ably headers', () async {
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

            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.request('GET', '/test');

        final request = capturedRequests[0];
        expect(request.headers['X-Ably-Version'], isNotNull);
        expect(request.headers['Ably-Agent'], isNotNull);
        expect(request.headers['Authorization'], isNotNull);
      });
    });

    group('RSC19c - Response decoding', () {
      // UTS: rest/unit/RSC19c/response-decoded-by-content-type-3
      test('RSC19c - response decoded based on content-type header', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'items': [
                {'name': 'item1'},
                {'name': 'item2'},
              ],
            });
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.statusCode, equals(200));
        expect(response.items, isNotEmpty);
      });
    });

    group('RSC19e - Fallback on server error', () {
      // UTS: rest/unit/RSC19e/fallback-on-server-error-3
      test('RSC19e - server error triggers fallback', () async {
        var requestCount = 0;
        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              req.respondWith(500, {
                'error': {
                  'message': 'Server error',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else {
              req.respondWith(200, {'items': []});
            }
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final response = await client.request('GET', '/test');

        expect(response.statusCode, equals(200));
        expect(requestCount, equals(2));
      });

      // UTS: rest/unit/RSC19e/http-error-no-fallback-2
      test('RSC19e - HTTP 4xx error does not trigger fallback', () async {
        var requestCount = 0;
        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            req.respondWith(404, {
              'error': {
                'message': 'Not found',
                'code': 40400,
                'statusCode': 404,
              },
            });
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        try {
          await client.request('GET', '/test');
          fail('Expected AblyException');
        } on AblyException catch (e) {
          expect(e.errorInfo?.statusCode, equals(404));
        }

        expect(requestCount, equals(1));
      });
    });
  });
}

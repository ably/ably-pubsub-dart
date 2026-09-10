import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// REST Client Tests
///
/// Spec points: RSC5, RSC7, RSC7b, RSC7c, RSC7d, RSC7e, RSC8, RSC8a, RSC8b,
///              RSC8c, RSC8d, RSC8e, RSC13, RSC17, RSC18
void main() {
  group('REST Client', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    // UTS: rest/unit/RSC5/auth-attribute-accessible-0
    test('RSC5 - auth attribute exists', () {
      final rest = RestClient(
        options:
            ClientOptions(key: 'fake.key:secret', useBinaryProtocol: false),
      );

      expect(rest.auth, isNotNull);
      expect(rest.auth, isA<Auth>());
    });

    // UTS: rest/unit/RSC17/client-id-from-options-0
    test('RSC17 - clientId from options is set on auth', () {
      final rest = RestClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          clientId: 'explicit-client-id',
          useBinaryProtocol: false,
        ),
      );

      expect(rest.auth.clientId, equals('explicit-client-id'));
    });

    group('RSC7e - X-Ably-Version header', () {
      // UTS: rest/unit/RSC7e/ably-version-header-0
      test('includes X-Ably-Version header in all requests', () async {
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

            req.respondWith(200, {'time': 1234567890000});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        final request = capturedRequests[0];
        expect(request.headers.containsKey('X-Ably-Version'), isTrue);
        expect(
          request.headers['X-Ably-Version'],
          matches(RegExp(r'^[0-9.]+$')),
        );
      });
    });

    group('RSC7d - Ably-Agent header', () {
      // UTS: rest/unit/RSC7d/ably-agent-header-format-0
      test('includes Ably-Agent header with correct format', () async {
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

            req.respondWith(200, {'time': 1234567890000});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        final request = capturedRequests[0];
        expect(request.headers.containsKey('Ably-Agent'), isTrue);

        final agent = request.headers['Ably-Agent']!;
        // Format: key[/value] entries joined by spaces
        // Must include at least library name/version
        expect(
          agent,
          matches(RegExp(r'ably-[a-z]+/[0-9]+\.[0-9]+\.[0-9]+')),
        );
      });
    });

    group('RSC7c - Request ID when addRequestIds enabled', () {
      // UTS: rest/unit/RSC7c/request-id-included-0
      test('includes request_id query parameter', () async {
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

            req.respondWith(200, {'time': 1234567890000});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            addRequestIds: true,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        final request = capturedRequests[0];
        expect(request.url.queryParameters.containsKey('request_id'), isTrue);

        final requestId = request.url.queryParameters['request_id']!;
        // Should be url-safe base64 encoded, at least 12 characters
        expect(requestId.length, greaterThanOrEqualTo(12));
        expect(requestId, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      });

      // UTS: rest/unit/RSC7c/request-id-preserved-fallback-1
      test('preserves same request_id on fallback retry', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;

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

            requestCount++;
            if (requestCount == 1) {
              // First request fails with 500
              req.respondWith(500, {
                'error': {'code': 50000},
              });
            } else {
              // Retry succeeds
              req.respondWith(200, {'time': 1234567890000});
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            addRequestIds: true,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        expect(capturedRequests.length, equals(2));

        final requestId1 =
            capturedRequests[0].url.queryParameters['request_id'];
        final requestId2 =
            capturedRequests[1].url.queryParameters['request_id'];

        // Same ID for retry
        expect(requestId1, equals(requestId2));
      });
    });

    group('RSC8a, RSC8b - Protocol selection', () {
      // UTS: rest/unit/RSC8a/protocol-selection-0
      test('uses JSON by default (useBinaryProtocol: false)', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC8a');

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

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(
          request.headers['Content-Type'],
          equals('application/json'),
        );
        expect(
          request.headers['Accept'],
          equals('application/json'),
        );
      });

      test('uses msgpack when useBinaryProtocol is true', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC8a-msgpack');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                bodyBytes: req.body,
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
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(
          request.headers['Content-Type'],
          equals('application/x-msgpack'),
        );
        expect(
          request.headers['Accept'],
          equals('application/x-msgpack'),
        );
      });

      // UTS: rest/unit/RSC8/error-decoded-from-msgpack-0
      test('uses JSON when useBinaryProtocol is false', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC8b');

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

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(
          request.headers['Content-Type'],
          equals('application/json'),
        );
        expect(
          request.headers['Accept'],
          equals('application/json'),
        );
      });
    });

    group('RSC8c - Accept and Content-Type headers', () {
      // UTS: rest/unit/RSC8c/accept-content-type-headers-0
      test('includes both Accept and Content-Type headers', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC8c');

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

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(request.headers['Accept'], equals('application/json'));
        expect(request.headers['Content-Type'], equals('application/json'));
      });
    });

    group('RSC8e - Unsupported Content-Type handling', () {
      // UTS: rest/unit/RSC8e/unsupported-content-type-0
      test('handles error status with unsupported Content-Type', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              500,
              '<html>Server Error</html>',
              headers: {'Content-Type': 'text/html'},
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(
          () => client.time(),
          throwsA(
            isA<AblyException>().having(
              (e) => e.statusCode,
              'statusCode',
              equals(500),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSC8d/mismatched-response-content-type-0
      test('handles success status with unsupported Content-Type', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              '<html>OK</html>',
              headers: {'Content-Type': 'text/html'},
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(
          () => client.time(),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40013),
            ),
          ),
        );
      });
    });

    group('RSC18 - TLS configuration', () {
      // UTS: rest/unit/RSC18/tls-controls-protocol-scheme-0
      test('uses https by default (tls: true)', () async {
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

            req.respondWith(200, {'time': 1234567890000});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        final request = capturedRequests[0];
        expect(request.url.scheme, equals('https'));
      });

      // UTS: rest/unit/RSC18/tls-controls-protocol-scheme-0.1
      test('uses http when tls is false', () async {
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

            req.respondWith(200, {'time': 1234567890000});
          },
        );

        // Note: API key over non-TLS should be rejected, use token auth
        final client = RestClient.forTesting(
          options: ClientOptions(
            token: 'some-token',
            tls: false,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        final request = capturedRequests[0];
        expect(request.url.scheme, equals('http'));
      });

      // UTS: rest/unit/RSC18/basic-auth-over-http-rejected-1
      test('rejects Basic auth over HTTP', () {
        expect(
          () => RestClient.forTesting(
            options: ClientOptions(
              key: 'appId.keyId:keySecret',
              tls: false,
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          ),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40103),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSC17/client-id-matches-auth-1
      test('allows token auth over HTTP', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC18-http');

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

            // Return channel status response
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            token: 'some-token-string',
            tls: false,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        // Use channel.status() which requires authentication
        final status = await client.channels.get(channelName).status();

        // Should succeed - token auth over HTTP is permitted
        expect(status.channelId, equals(channelName));

        // Verify request was made over HTTP with Bearer token
        final request = capturedRequests[0];
        expect(request.url.scheme, equals('http'));
        expect(
          request.headers['Authorization'],
          equals('Bearer some-token-string'),
        );
      });
    });

    group('RSC13 - Request timeout', () {
      // UTS: rest/unit/RSC13/request-timeout-enforced-0
      test('RSC13 - request timeout enforced', () async {
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWithTimeout();
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            httpRequestTimeout: 1000,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        try {
          await client.time();
          fail('Expected timeout exception');
        } catch (e) {
          expect(e, isA<AblyException>());
        }
      });
    });

    group('TO - Endpoint affects host', () {
      // UTS: rest/unit/TO/endpoint-affects-host-0
      test('TO - endpoint option affects REST request host', () async {
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [1234567890000]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'test',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.time();

        expect(mockHttp.capturedRequests, hasLength(1));
        expect(
          mockHttp.capturedRequests[0].url.host,
          equals('test.realtime.ably.net'),
        );
      });
    });
  });
}

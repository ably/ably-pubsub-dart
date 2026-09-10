import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_client.dart';

/// Time API Tests
///
/// Tests the shared time() implementation in BaseClientImpl via TestClient.
///
/// Spec points: RSC16, RTC6, RTC6a
void main() {
  group('Time API', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSC16 - time() returns server time', () {
      // UTS: rest/unit/RSC16/returns-server-time-0
      test('returns server time as DateTime', () async {
        const serverTimeMs = 1704067200000; // 2024-01-01 00:00:00 UTC

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [serverTimeMs]);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final result = await client.time();

        expect(result, isA<DateTime>());
        expect(result.millisecondsSinceEpoch, equals(serverTimeMs));

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(request.url.path, equals('/time'));
      });
    });

    group('RSC16 - time() request format', () {
      // UTS: rest/unit/RSC16/request-format-get-time-1
      test('sends correctly formatted request with standard headers', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [1704067200000]);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];

        expect(request.method, equals('GET'));
        expect(request.url.path, equals('/time'));

        expect(request.headers.containsKey('X-Ably-Version'), isTrue);
        expect(request.headers.containsKey('Ably-Agent'), isTrue);
      });
    });

    group('RSC16 - time() does not require authentication', () {
      // UTS: rest/unit/RSC16/no-auth-required-2
      test('does not send Authorization header even with credentials',
          () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [1704067200000]);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final result = await client.time();

        expect(result, isA<DateTime>());

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.url.path, equals('/time'));
        expect(
          request.headers.containsKey('Authorization'),
          isFalse,
          reason: 'time() should not send Authorization header',
        );
      });
    });

    group('RSC16 - time() works without TLS', () {
      // UTS: rest/unit/RSC16/works-without-tls-3
      test('succeeds over HTTP without sending credentials', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [1704067200000]);
          },
        );

        final client = TestClient(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            tls: false,
            useTokenAuth: true,
          ),
          httpClient: mockHttp,
        );

        final result = await client.time();

        expect(result, isA<DateTime>());

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.url.scheme, equals('http'));

        expect(
          request.headers.containsKey('Authorization'),
          isFalse,
          reason: 'time() should not send Authorization header',
        );
      });
    });

    group('RSC16 - time() error handling', () {
      // UTS: rest/unit/RSC16/error-propagated-4
      test('properly propagates errors from time endpoint', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(500, {
              'error': {
                'message': 'Internal server error',
                'code': 50000,
                'statusCode': 500,
              },
            });
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        expect(
          () => client.time(),
          throwsA(
            isA<AblyException>()
                .having((e) => e.statusCode, 'statusCode', equals(500))
                .having((e) => e.code, 'code', equals(50000)),
          ),
        );
      });
    });
  });
}

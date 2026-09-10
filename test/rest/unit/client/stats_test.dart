import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_client.dart';

/// Stats API Tests
///
/// Tests the shared stats() implementation in BaseClientImpl via TestClient.
///
/// Spec points: RSC6, RSC6a, RSC6b1, RSC6b2, RSC6b3, RSC6b4, RTC5
void main() {
  group('Stats API', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSC6a - stats() returns PaginatedResult with Stats objects', () {
      // UTS: rest/unit/RSC6a/returns-paginated-stats-0
      test('returns PaginatedResult containing Stats items', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'intervalId': '2024-01-01:00:00',
                'unit': 'hour',
                'all': {
                  'messages': {'count': 100, 'data': 5000},
                  'all': {'count': 100, 'data': 5000},
                },
              },
              {
                'intervalId': '2024-01-01:01:00',
                'unit': 'hour',
                'all': {
                  'messages': {'count': 150, 'data': 7500},
                  'all': {'count': 150, 'data': 7500},
                },
              },
            ]);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final result = await client.stats();

        expect(result, isA<PaginatedResult<Stats>>());
        expect(result.items.length, equals(2));

        expect(result.items[0].intervalId, equals('2024-01-01:00:00'));
        expect(result.items[1].intervalId, equals('2024-01-01:01:00'));

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(request.url.path, equals('/stats'));
      });
    });

    group('RSC6a - stats() sends authenticated request with standard headers',
        () {
      // UTS: rest/unit/RSC6a/authenticated-with-headers-1
      test('includes Authorization and standard Ably headers', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];

        // Stats requires authentication (unlike time)
        expect(
          request.headers.containsKey('Authorization'),
          isTrue,
          reason: 'stats() must send Authorization header',
        );

        // Standard Ably headers
        expect(request.headers.containsKey('X-Ably-Version'), isTrue);
        expect(request.headers.containsKey('Ably-Agent'), isTrue);
      });
    });

    group('RSC6b1 - start and end parameters', () {
      // UTS: rest/unit/RSC6b1/start-param-millis-0
      test('sends start as milliseconds since epoch', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final startTime = DateTime.utc(2024); // 1704067200000

        await client.stats(start: startTime);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters['start'],
          equals(startTime.millisecondsSinceEpoch.toString()),
        );
      });

      // UTS: rest/unit/RSC6b1/end-param-millis-1
      test('sends end as milliseconds since epoch', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final endTime = DateTime.utc(2024, 1, 31, 23, 59, 59);

        await client.stats(end: endTime);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters['end'],
          equals(endTime.millisecondsSinceEpoch.toString()),
        );
      });

      // UTS: rest/unit/RSC6b1/start-and-end-params-2
      test('sends both start and end together', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final startTime = DateTime.utc(2024);
        final endTime = DateTime.utc(2024, 1, 31, 23, 59, 59);

        await client.stats(start: startTime, end: endTime);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters['start'],
          equals(startTime.millisecondsSinceEpoch.toString()),
        );
        expect(
          request.url.queryParameters['end'],
          equals(endTime.millisecondsSinceEpoch.toString()),
        );
      });
    });

    group('RSC6b2 - direction parameter', () {
      // UTS: rest/unit/RSC6b2/direction-param-forwards-0
      test('sends direction=forwards when specified', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats(direction: StatsDirection.forwards);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.url.queryParameters['direction'], equals('forwards'));
      });

      // UTS: rest/unit/RSC6b2/direction-param-forwards-0.1
      test('sends direction=backwards when specified', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats(direction: StatsDirection.backwards);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.url.queryParameters['direction'], equals('backwards'));
      });

      // UTS: rest/unit/RSC6b2/direction-defaults-backwards-1
      test('omits direction when not specified (server default: backwards)',
          () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters.containsKey('direction'),
          isFalse,
          reason: 'direction should be omitted to let server apply default',
        );
      });
    });

    group('RSC6b3 - limit parameter', () {
      // UTS: rest/unit/RSC6b3/limit-param-value-0
      test('sends limit when specified', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats(limit: 10);

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.url.queryParameters['limit'], equals('10'));
      });

      // UTS: rest/unit/RSC6b3/limit-defaults-to-100-1
      test('omits limit when not specified (server default: 100)', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters.containsKey('limit'),
          isFalse,
          reason: 'limit should be omitted to let server apply default',
        );
      });
    });

    group('RSC6b4 - unit parameter', () {
      for (final unit in StatsUnit.values) {
        // UTS: rest/unit/RSC6b4/unit-param-values-0
        test('sends unit=${unit.name}', () async {
          mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(200, []);
            },
          );

          final client = TestClient(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );

          await client.stats(unit: unit);

          expect(mockHttp.capturedRequests.length, equals(1));
          final request = mockHttp.capturedRequests[0];
          expect(request.url.queryParameters['unit'], equals(unit.name));
        });
      }

      // UTS: rest/unit/RSC6b4/unit-defaults-to-minute-1
      test('omits unit when not specified (server default: minute)', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters.containsKey('unit'),
          isFalse,
          reason: 'unit should be omitted to let server apply default',
        );
      });
    });

    group('RSC6b - all parameters combined', () {
      // UTS: rest/unit/RSC6b/all-params-combined-0
      test('sends all parameters together', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final startTime = DateTime.utc(2024);
        final endTime = DateTime.utc(2024, 1, 31, 23, 59, 59);

        await client.stats(
          start: startTime,
          end: endTime,
          direction: StatsDirection.forwards,
          limit: 50,
          unit: StatsUnit.hour,
        );

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(
          request.url.queryParameters['start'],
          equals(startTime.millisecondsSinceEpoch.toString()),
        );
        expect(
          request.url.queryParameters['end'],
          equals(endTime.millisecondsSinceEpoch.toString()),
        );
        expect(request.url.queryParameters['direction'], equals('forwards'));
        expect(request.url.queryParameters['limit'], equals('50'));
        expect(request.url.queryParameters['unit'], equals('hour'));
      });
    });

    group('RSC6a - no parameters sends clean request', () {
      // UTS: rest/unit/RSC6a/no-params-clean-request-2
      test('sends GET /stats with no query parameters', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.stats();

        expect(mockHttp.capturedRequests.length, equals(1));
        final request = mockHttp.capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(request.url.path, equals('/stats'));
        expect(
          request.url.queryParameters,
          isEmpty,
          reason: 'no query parameters should be sent with default call',
        );
      });
    });

    group('RSC6a - pagination with Link headers', () {
      // UTS: rest/unit/RSC6a/pagination-link-headers-3
      test('supports pagination navigation via next()', () async {
        var requestCount = 0;

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'intervalId': '2024-01-01:01:00', 'unit': 'hour'},
                ],
                headers: {
                  'Link': '</stats?start=1704070800000&limit=1>; rel="next", '
                      '</stats?limit=1>; rel="first"',
                },
              );
            } else {
              req.respondWith(200, [
                {'intervalId': '2024-01-01:00:00', 'unit': 'hour'},
              ]);
            }
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final page1 = await client.stats(limit: 1);

        expect(page1.items.length, equals(1));
        expect(page1.items[0].intervalId, equals('2024-01-01:01:00'));
        expect(page1.hasNext(), isTrue);
        expect(page1.isLast(), isFalse);

        final page2 = await page1.next();

        expect(page2, isNotNull);
        expect(page2!.items.length, equals(1));
        expect(page2.items[0].intervalId, equals('2024-01-01:00:00'));
        expect(page2.hasNext(), isFalse);
        expect(page2.isLast(), isTrue);
      });
    });

    group('RSC6a - empty results', () {
      // UTS: rest/unit/RSC6a/empty-results-handled-4
      test('handles empty result set correctly', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        final result = await client.stats();

        expect(result, isA<PaginatedResult<Stats>>());
        expect(result.items, isEmpty);
        expect(result.hasNext(), isFalse);
        expect(result.isLast(), isTrue);
      });
    });

    group('RSC6a - error handling', () {
      // UTS: rest/unit/RSC6a/error-propagated-5
      test('propagates errors from stats endpoint', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(401, {
              'error': {
                'message': 'Unauthorized',
                'code': 40100,
                'statusCode': 401,
              },
            });
          },
        );

        final client = TestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        expect(
          () => client.stats(),
          throwsA(
            isA<AblyException>()
                .having((e) => e.statusCode, 'statusCode', equals(401))
                .having((e) => e.code, 'code', equals(40100)),
          ),
        );
      });
    });
  });
}

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// REST Channel History Tests
///
/// Spec points: RSL2, RSL2a, RSL2b, RSL2b1, RSL2b2, RSL2b3
void main() {
  group('Channel History', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSL2a - History returns PaginatedResult', () {
      // UTS: rest/unit/RSL2a/returns-paginated-result-0
      test('returns PaginatedResult containing messages', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL2a');

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

            req.respondWith(200, [
              {
                'id': 'msg1',
                'name': 'event1',
                'data': 'data1',
                'timestamp': 1000,
              },
              {
                'id': 'msg2',
                'name': 'event2',
                'data': 'data2',
                'timestamp': 2000,
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

        expect(result, isA<PaginatedResult<Message>>());
        expect(result.items, isList);
        expect(result.items.length, equals(2));

        expect(result.items[0], isA<Message>());
        expect(result.items[0].id, equals('msg1'));
        expect(result.items[0].name, equals('event1'));
        expect(result.items[0].data, equals('data1'));
      });
    });

    group('RSL2b - History query parameters', () {
      final testCases = [
        (parameter: 'start', value: '1234567890000'),
        (parameter: 'end', value: '1234567899999'),
        (parameter: 'direction', value: 'backwards'),
        (parameter: 'direction', value: 'forwards'),
        (parameter: 'limit', value: '50'),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/RSL2b/query-parameters-0
        test('sends ${testCase.parameter}=${testCase.value}', () async {
          final capturedRequests = <CapturedRequest>[];
          final channelName = testChannelName('RSL2b');

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

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(channelName);

          await channel.history(
            RestHistoryParams.fromMap({testCase.parameter: testCase.value}),
          );

          final request = capturedRequests[0];
          expect(
            request.url.queryParameters[testCase.parameter],
            equals(testCase.value),
          );
        });
      }
    });

    group('RSL2b1 - Default direction is backwards', () {
      // UTS: rest/unit/RSL2b1/default-direction-backwards-0
      test('uses backwards direction by default', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL2b1');

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

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.history();

        final request = capturedRequests[0];

        // Either direction param is absent (server default) or explicitly "backwards"
        if (request.url.queryParameters.containsKey('direction')) {
          expect(request.url.queryParameters['direction'], equals('backwards'));
        }
        // If absent, server defaults to backwards per spec
      });
    });

    group('RSL2b2 - Limit parameter', () {
      // UTS: rest/unit/RSL2b2/limit-parameter-0
      test('sends limit in query string', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL2b2');

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

            req.respondWith(200, [
              {'id': 'msg1', 'name': 'e', 'data': 'd', 'timestamp': 1000},
              {'id': 'msg2', 'name': 'e', 'data': 'd', 'timestamp': 2000},
              {'id': 'msg3', 'name': 'e', 'data': 'd', 'timestamp': 3000},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.history(const RestHistoryParams(limit: 10));

        final request = capturedRequests[0];
        expect(request.url.queryParameters['limit'], equals('10'));
      });
    });

    group('RSL2b3 - Default limit is 100', () {
      // UTS: rest/unit/RSL2b3/default-limit-hundred-0
      test('uses default limit of 100', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL2b3');

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

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.history();

        final request = capturedRequests[0];

        // Either limit param is absent (server default) or explicitly "100"
        if (request.url.queryParameters.containsKey('limit')) {
          expect(request.url.queryParameters['limit'], equals('100'));
        }
        // If absent, server defaults to 100 per spec
      });
    });

    group('RSL2 - History request URL format', () {
      final testCases = [
        (channelName: 'simple', expectedPath: '/channels/simple/messages'),
        (
          channelName: 'with:colon',
          expectedPath: '/channels/with%3Acolon/messages'
        ),
        (
          channelName: 'with/slash',
          expectedPath: '/channels/with%2Fslash/messages'
        ),
        (
          channelName: 'with space',
          expectedPath: '/channels/with%20space/messages'
        ),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/RSL2/request-url-format-0
        test('encodes channel name "${testCase.channelName}"', () async {
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

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(testCase.channelName);

          await channel.history();

          final request = capturedRequests[0];
          expect(request.method, equals('GET'));
          expect(request.url.path, equals(testCase.expectedPath));
        });
      }
    });

    group('RSL2 - History with time range', () {
      // UTS: rest/unit/RSL2/history-time-range-1
      test('sends start and end parameters', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL2-time');

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

            req.respondWith(200, [
              {'id': 'msg1', 'name': 'e', 'data': 'd', 'timestamp': 1500},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.history(
          const RestHistoryParams(start: 1000, end: 2000),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['start'], equals('1000'));
        expect(request.url.queryParameters['end'], equals('2000'));
      });
    });
  });
}

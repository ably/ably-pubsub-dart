import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Request Endpoint Tests
///
/// Spec points: RSC25
void main() {
  group('RSC25 - Requests sent to primary domain first', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    // UTS: rest/unit/RSC25/default-primary-domain-0
    test('default primary domain used for requests', () async {
      mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, {'time': 1234567890000});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      await client.time();

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(
        mockHttp.capturedRequests[0].url.host,
        equals(client.options.effectiveRestHost),
      );
    });

    // UTS: rest/unit/RSC25/custom-endpoint-domain-1
    test('custom endpoint used for requests', () async {
      mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, {'time': 1234567890000});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'test',
        ),
        httpClient: mockHttp,
      );

      await client.time();

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(
        mockHttp.capturedRequests[0].url.host,
        equals('test.realtime.ably.net'),
      );
    });

    // UTS: rest/unit/RSC25/multiple-requests-primary-domain-2
    test('multiple requests all go to primary domain', () async {
      mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, {'time': 1234567890000});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      await client.time();
      await client.time();
      await client.time();

      expect(mockHttp.capturedRequests.length, equals(3));
      final expectedHost = client.options.effectiveRestHost;
      for (final request in mockHttp.capturedRequests) {
        expect(request.url.host, equals(expectedHost));
      }
    });

    // UTS: rest/unit/RSC25/primary-tried-before-fallback-3
    test('primary domain tried first before fallback', () async {
      var requestCount = 0;

      mockHttp = MockHttpClient(
        onRequest: (req) {
          requestCount++;
          if (requestCount == 1) {
            req.respondWith(500, {
              'error': {'code': 50000},
            });
          } else {
            req.respondWith(200, {'time': 1234567890000});
          }
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      await client.time();

      expect(mockHttp.capturedRequests.length, equals(2));
      // First request was to primary domain
      expect(
        mockHttp.capturedRequests[0].url.host,
        equals(client.options.effectiveRestHost),
      );
      // Second request was to a fallback (not primary)
      expect(
        mockHttp.capturedRequests[1].url.host,
        isNot(equals(client.options.effectiveRestHost)),
      );
    });

    // UTS: rest/unit/RSC25/request-path-preserved-4
    test('request path preserved when sent to primary domain', () async {
      mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, []);
        },
      );

      final channelName = testChannelName('RSC25');
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      await client.channels.get(channelName).history();

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.url.host, equals(client.options.effectiveRestHost));
      expect(
        request.url.path,
        equals('/channels/${Uri.encodeComponent(channelName)}/messages'),
      );
      expect(request.method, equals('GET'));
    });
  });
}

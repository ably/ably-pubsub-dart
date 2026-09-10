import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Unit tests for PushChannel operations (RSH7).
///
/// These tests cover the per-channel push interface available on
/// RestChannel.push and RealtimeChannel.push.
///
/// Spec: uts/test/rest/unit/push/push_channels.md
void main() {
  group('RSH7a - subscribeDevice', () {
    // UTS: rest/unit/RSH7a2/subscribe-device-post-0
    test(
        'RSH7a2, RSH7a3 - sends POST with deviceId, channel name, and device auth',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channel': 'my-channel',
            'deviceId': 'test-device-001',
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');
      await channel.push.subscribeDevice();

      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/channelSubscriptions'));

      // RSH7a3 + RSH6a — push device authentication
      expect(
        request.headers['X-Ably-DeviceToken'],
        equals('test-device-identity-token'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH7a1/subscribe-device-no-token-fails-0
    test('RSH7a1 - fails if no deviceIdentityToken', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');

      expect(
        () => channel.push.subscribeDevice(),
        throwsA(isA<AblyException>()),
      );

      mockHttp.dispose();
    });
  });

  group('RSH7b - subscribeClient', () {
    // UTS: rest/unit/RSH7b2/subscribe-client-post-0
    test('RSH7b2 - sends POST with clientId and channel name', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channel': 'my-channel',
            'clientId': 'test-client',
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');
      await channel.push.subscribeClient();

      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/channelSubscriptions'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH7b1/subscribe-client-no-clientid-fails-0
    test('RSH7b1 - fails if no clientId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
      );

      final channel = client.channels.get('my-channel');

      expect(
        () => channel.push.subscribeClient(),
        throwsA(isA<AblyException>()),
      );

      mockHttp.dispose();
    });
  });

  group('RSH7c - unsubscribeDevice', () {
    // UTS: rest/unit/RSH7c2/unsubscribe-device-delete-0
    test(
        'RSH7c2, RSH7c3 - sends DELETE with deviceId, channel name, and device auth',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');
      await channel.push.unsubscribeDevice();

      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );
      expect(
        request.url.queryParameters['deviceId'],
        equals('test-device-001'),
      );

      // RSH7c3 + RSH6a — push device authentication
      expect(
        request.headers['X-Ably-DeviceToken'],
        equals('test-device-identity-token'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH7c1/unsubscribe-device-no-token-fails-0
    test('RSH7c1 - fails if no deviceIdentityToken', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');

      expect(
        () => channel.push.unsubscribeDevice(),
        throwsA(isA<AblyException>()),
      );

      mockHttp.dispose();
    });
  });

  group('RSH7d - unsubscribeClient', () {
    // UTS: rest/unit/RSH7d2/unsubscribe-client-delete-0
    test('RSH7d2 - sends DELETE with clientId and channel name', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');
      await channel.push.unsubscribeClient();

      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );
      expect(
        request.url.queryParameters['clientId'],
        equals('test-client'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH7d1/unsubscribe-client-no-clientid-fails-0
    test('RSH7d1 - fails if no clientId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
      );

      final channel = client.channels.get('my-channel');

      expect(
        () => channel.push.unsubscribeClient(),
        throwsA(isA<AblyException>()),
      );

      mockHttp.dispose();
    });
  });

  group('RSH7e - listSubscriptions', () {
    // UTS: rest/unit/RSH7e/list-subscriptions-with-filters-0
    test('sends GET with channel, deviceId, clientId, and concatFilters',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'channel': 'my-channel',
              'deviceId': 'test-device-001',
            },
            {
              'channel': 'my-channel',
              'clientId': 'test-client',
            },
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
        clientId: 'test-client',
      );

      final channel = client.channels.get('my-channel');
      final result = await channel.push.listSubscriptions({'limit': '10'});

      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(request.url.path, equals('/push/channelSubscriptions'));

      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );
      expect(
        request.url.queryParameters['deviceId'],
        equals('test-device-001'),
      );
      expect(
        request.url.queryParameters['clientId'],
        equals('test-client'),
      );
      expect(
        request.url.queryParameters['concatFilters'],
        equals('true'),
      );
      expect(
        request.url.queryParameters['limit'],
        equals('10'),
      );

      expect(result.items.length, equals(2));
      expect(result.items[0].channel, equals('my-channel'));
      expect(result.items[0].deviceId, equals('test-device-001'));
      expect(result.items[1].clientId, equals('test-client'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH7e/list-subscriptions-omits-clientid-1
    test('omits clientId when LocalDevice has no clientId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'channel': 'my-channel',
              'deviceId': 'test-device-001',
            },
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      client.device = LocalDevice(
        id: 'test-device-001',
        deviceIdentityToken: 'test-device-identity-token',
      );

      final channel = client.channels.get('my-channel');
      final result = await channel.push.listSubscriptions({});

      final request = mockHttp.capturedRequests[0];
      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );
      expect(
        request.url.queryParameters['deviceId'],
        equals('test-device-001'),
      );
      expect(
        request.url.queryParameters['concatFilters'],
        equals('true'),
      );
      expect(
        request.url.queryParameters.containsKey('clientId'),
        isFalse,
      );

      expect(result.items.length, equals(1));

      mockHttp.dispose();
    });
  });
}

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for PushChannelSubscriptions (RSH1c1–RSH1c5).
///
/// Spec: uts/test/rest/unit/push/push_channel_subscriptions.md
void main() {
  group('RSH1c1 - list', () {
    // UTS: rest/unit/RSH1c1/list-filtered-by-channel-0
    test('returns paginated PushChannelSubscription filtered by channel',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {'channel': 'my-channel', 'deviceId': 'device-001'},
            {'channel': 'my-channel', 'clientId': 'client-abc'},
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.push.admin.channelSubscriptions
          .list({'channel': 'my-channel'});

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );

      expect(result, isA<PaginatedResult<PushChannelSubscription>>());
      expect(result.items.length, equals(2));
      expect(result.items[0], isA<PushChannelSubscription>());
      expect(result.items[0].channel, equals('my-channel'));
      expect(result.items[0].deviceId, equals('device-001'));
      expect(result.items[1].clientId, equals('client-abc'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c1/list-filtered-by-device-client-1
    test('filters by deviceId and clientId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {'channel': 'notifications', 'deviceId': 'device-001'},
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.push.admin.channelSubscriptions.list({
        'deviceId': 'device-001',
        'clientId': 'client-abc',
      });

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['deviceId'],
        equals('device-001'),
      );
      expect(
        mockHttp.capturedRequests[0].url.queryParameters['clientId'],
        equals('client-abc'),
      );
      expect(result.items.length, equals(1));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c1/list-with-limit-param-2
    test('supports limit for pagination', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {'channel': 'ch-1', 'deviceId': 'device-001'},
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.channelSubscriptions.list({'limit': '5'});

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['limit'],
        equals('5'),
      );

      mockHttp.dispose();
    });
  });

  group('RSH1c2 - listChannels', () {
    // UTS: rest/unit/RSH1c2/list-channels-paginated-0
    test('returns paginated channel names', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, ['channel-1', 'channel-2', 'channel-3']);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result =
          await client.push.admin.channelSubscriptions.listChannels({});

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(request.url.path, equals('/push/channels'));

      expect(result, isA<PaginatedResult<String>>());
      expect(result.items.length, equals(3));
      expect(result.items[0], equals('channel-1'));
      expect(result.items[1], equals('channel-2'));
      expect(result.items[2], equals('channel-3'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c2/list-channels-with-limit-1
    test('supports limit and pagination', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, ['channel-1']);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.push.admin.channelSubscriptions
          .listChannels({'limit': '1'});

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['limit'],
        equals('1'),
      );
      expect(result.items.length, equals(1));

      mockHttp.dispose();
    });
  });

  group('RSH1c3 - save', () {
    // UTS: rest/unit/RSH1c3/save-post-subscription-0
    test('issues POST with PushChannelSubscription', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channel': 'my-channel',
            'deviceId': 'device-001',
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

      final subscription = PushChannelSubscription.forDevice(
        channel: 'my-channel',
        deviceId: 'device-001',
      );

      final result =
          await client.push.admin.channelSubscriptions.save(subscription);

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/channelSubscriptions'));

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['channel'], equals('my-channel'));
      expect(body['deviceId'], equals('device-001'));

      expect(result, isA<PushChannelSubscription>());
      expect(result.channel, equals('my-channel'));
      expect(result.deviceId, equals('device-001'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c3/save-updates-existing-1
    test('updates existing subscription', () async {
      var requestCount = 0;

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          requestCount++;
          request.respondWith(200, {
            'channel': 'my-channel',
            'clientId': 'client-abc',
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

      final subscription = PushChannelSubscription.forClientId(
        channel: 'my-channel',
        clientId: 'client-abc',
      );

      final result1 =
          await client.push.admin.channelSubscriptions.save(subscription);
      final result2 =
          await client.push.admin.channelSubscriptions.save(subscription);

      expect(requestCount, equals(2));
      expect(result1.channel, equals('my-channel'));
      expect(result2.channel, equals('my-channel'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c3/save-error-propagated-2
    test('propagates server error', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(400, {
            'error': {
              'code': 40000,
              'statusCode': 400,
              'message': 'Invalid subscription',
            },
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

      final subscription = PushChannelSubscription.forDevice(
        channel: 'my-channel',
        deviceId: 'device-001',
      );

      expect(
        () => client.push.admin.channelSubscriptions.save(subscription),
        throwsA(
          isA<AblyException>().having(
            (e) => e.errorInfo?.code,
            'code',
            40000,
          ),
        ),
      );

      mockHttp.dispose();
    });
  });

  group('RSH1c4 - remove', () {
    // UTS: rest/unit/RSH1c4/remove-delete-clientid-0
    test('issues DELETE with clientId subscription attributes', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final subscription = PushChannelSubscription.forClientId(
        channel: 'my-channel',
        clientId: 'client-abc',
      );

      await client.push.admin.channelSubscriptions.remove(subscription);

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
        equals('client-abc'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c4/remove-delete-deviceid-1
    test('issues DELETE with deviceId subscription attributes', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final subscription = PushChannelSubscription.forDevice(
        channel: 'my-channel',
        deviceId: 'device-001',
      );

      await client.push.admin.channelSubscriptions.remove(subscription);

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['channel'],
        equals('my-channel'),
      );
      expect(
        request.url.queryParameters['deviceId'],
        equals('device-001'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c4/remove-nonexistent-succeeds-2
    test('succeeds for nonexistent subscription', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final subscription = PushChannelSubscription.forClientId(
        channel: 'nonexistent-channel',
        clientId: 'nonexistent-client',
      );

      // Should not throw
      await client.push.admin.channelSubscriptions.remove(subscription);

      mockHttp.dispose();
    });
  });

  group('RSH1c5 - removeWhere', () {
    // UTS: rest/unit/RSH1c5/remove-where-clientid-0
    test('issues DELETE with clientId param', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.channelSubscriptions
          .removeWhere({'clientId': 'client-abc'});

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['clientId'],
        equals('client-abc'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c5/remove-where-deviceid-1
    test('issues DELETE with deviceId param', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.channelSubscriptions
          .removeWhere({'deviceId': 'device-001'});

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/channelSubscriptions'));
      expect(
        request.url.queryParameters['deviceId'],
        equals('device-001'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1c5/remove-where-no-match-succeeds-2
    test('succeeds with no matching subscriptions', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(204, '');
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      // Should not throw
      await client.push.admin.channelSubscriptions
          .removeWhere({'clientId': 'nonexistent-client'});

      mockHttp.dispose();
    });
  });
}

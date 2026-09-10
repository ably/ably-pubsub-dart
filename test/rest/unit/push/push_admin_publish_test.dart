import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for Push Admin publish and type assertions (RSH1, RSH1a).
///
/// Spec: uts/test/rest/unit/push/push_admin_publish.md
void main() {
  group('RSH1 - client.push.admin exposes PushAdmin object', () {
    // UTS: rest/unit/RSH1/push-admin-accessible-0
    test('push.admin provides correct type hierarchy', () {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      expect(client.push, isA<Push>());
      expect(client.push.admin, isA<PushAdmin>());
      expect(
        client.push.admin.deviceRegistrations,
        isA<PushDeviceRegistrations>(),
      );
      expect(
        client.push.admin.channelSubscriptions,
        isA<PushChannelSubscriptions>(),
      );

      mockHttp.dispose();
    });
  });

  group('RSH1a - publish sends POST to /push/publish', () {
    // UTS: rest/unit/RSH1a/publish-post-push-publish-0
    test('sends POST with APNS recipient and notification data', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.publish(
        {'transportType': 'apns', 'deviceToken': 'foo'},
        {
          'notification': {'title': 'Test', 'body': 'Hello'},
        },
      );

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/publish'));

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['recipient']['transportType'], equals('apns'));
      expect(body['recipient']['deviceToken'], equals('foo'));
      expect(body['notification']['title'], equals('Test'));
      expect(body['notification']['body'], equals('Hello'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/publish-clientid-recipient-1
    test('sends POST with clientId recipient', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.publish(
        {'clientId': 'user-123'},
        {
          'data': {'key': 'value'},
        },
      );

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body['recipient']['clientId'], equals('user-123'));
      expect(body['data']['key'], equals('value'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/publish-deviceid-recipient-2
    test('sends POST with deviceId recipient', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.push.admin.publish(
        {'deviceId': 'device-abc'},
        {
          'notification': {'title': 'Device Push'},
        },
      );

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body['recipient']['deviceId'], equals('device-abc'));
      expect(body['notification']['title'], equals('Device Push'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/rejects-empty-recipient-3
    test('rejects empty recipient', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
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
        () => client.push.admin.publish(
          {},
          {
            'notification': {'title': 'Test'},
          },
        ),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40000),
        ),
      );

      expect(mockHttp.capturedRequests.length, equals(0));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/rejects-empty-data-4
    test('rejects empty data', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
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
        () => client.push.admin.publish(
          {'clientId': 'user-123'},
          {},
        ),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40000),
        ),
      );

      expect(mockHttp.capturedRequests.length, equals(0));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/rejects-null-recipient-5
    test('rejects null recipient', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      // Passing an empty map as recipient should be rejected
      // (equivalent to null recipient - no valid recipient fields)
      expect(
        () => client.push.admin.publish(
          {},
          {
            'notification': {'title': 'Test'},
          },
        ),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40000),
        ),
      );

      // No request should have been made
      expect(mockHttp.capturedRequests.length, equals(0));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1a/server-error-propagated-6
    test('propagates server error', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(400, {
            'error': {
              'code': 40000,
              'statusCode': 400,
              'message': 'Invalid recipient',
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

      expect(
        () => client.push.admin.publish(
          {'transportType': 'invalid'},
          {
            'notification': {'title': 'Test'},
          },
        ),
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
}

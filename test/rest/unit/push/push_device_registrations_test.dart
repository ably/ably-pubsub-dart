import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for PushDeviceRegistrations (RSH1b1–RSH1b5).
///
/// Spec: uts/test/rest/unit/push/push_device_registrations.md
void main() {
  group('RSH1b1 - get', () {
    // UTS: rest/unit/RSH1b1/get-device-details-0
    test('returns DeviceDetails for known device', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'id': 'device-001',
            'clientId': 'client-abc',
            'formFactor': 'phone',
            'platform': 'ios',
            'metadata': {'model': 'iPhone 14'},
            'push': {
              'recipient': {
                'transportType': 'apns',
                'deviceToken': 'token-123',
              },
              'state': 'Active',
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

      final device =
          await client.push.admin.deviceRegistrations.get('device-001');

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(
        request.url.path,
        equals(
          '/push/deviceRegistrations/${Uri.encodeComponent('device-001')}',
        ),
      );

      expect(device, isA<DeviceDetails>());
      expect(device.id, equals('device-001'));
      expect(device.clientId, equals('client-abc'));
      expect(device.formFactor, equals('phone'));
      expect(device.platform, equals('ios'));
      expect(device.metadata!['model'], equals('iPhone 14'));
      expect(device.push!.recipient['transportType'], equals('apns'));
      expect(device.push!.state, equals('Active'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b1/get-unknown-device-error-1
    test('returns error for unknown device', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(404, {
            'error': {
              'code': 40400,
              'statusCode': 404,
              'message': 'Device not found',
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
        () => client.push.admin.deviceRegistrations.get('nonexistent-device'),
        throwsA(
          isA<AblyException>().having(
            (e) => e.errorInfo?.code,
            'code',
            40400,
          ),
        ),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b1/get-url-encodes-deviceid-2
    test('URL-encodes deviceId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'id': 'device/with special:chars',
            'platform': 'ios',
            'formFactor': 'phone',
            'push': {
              'recipient': {},
              'state': 'Active',
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

      await client.push.admin.deviceRegistrations
          .get('device/with special:chars');

      expect(
        mockHttp.capturedRequests[0].url.path,
        equals(
          '/push/deviceRegistrations/${Uri.encodeComponent('device/with special:chars')}',
        ),
      );

      mockHttp.dispose();
    });
  });

  group('RSH1b2 - list', () {
    // UTS: rest/unit/RSH1b2/list-filtered-by-deviceid-0
    test('returns paginated DeviceDetails filtered by deviceId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'device-001',
              'clientId': 'client-abc',
              'platform': 'ios',
              'formFactor': 'phone',
              'push': {'recipient': {}, 'state': 'Active'},
            },
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

      final result = await client.push.admin.deviceRegistrations
          .list({'deviceId': 'device-001'});

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(request.url.queryParameters['deviceId'], equals('device-001'));

      expect(result, isA<PaginatedResult<DeviceDetails>>());
      expect(result.items.length, equals(1));
      expect(result.items[0], isA<DeviceDetails>());
      expect(result.items[0].id, equals('device-001'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b2/list-filtered-by-clientid-1
    test('returns paginated DeviceDetails filtered by clientId', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'device-001',
              'clientId': 'client-abc',
              'platform': 'ios',
              'formFactor': 'phone',
              'push': {'recipient': {}, 'state': 'Active'},
            },
            {
              'id': 'device-002',
              'clientId': 'client-abc',
              'platform': 'android',
              'formFactor': 'tablet',
              'push': {'recipient': {}, 'state': 'Active'},
            },
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

      final result = await client.push.admin.deviceRegistrations
          .list({'clientId': 'client-abc'});

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['clientId'],
        equals('client-abc'),
      );
      expect(result.items.length, equals(2));
      expect(result.items[0].clientId, equals('client-abc'));
      expect(result.items[1].clientId, equals('client-abc'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b2/list-with-limit-param-2
    test('supports limit for pagination', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'device-001',
              'platform': 'ios',
              'formFactor': 'phone',
              'push': {'recipient': {}, 'state': 'Active'},
            },
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

      await client.push.admin.deviceRegistrations.list({'limit': '2'});

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['limit'],
        equals('2'),
      );

      mockHttp.dispose();
    });
  });

  group('RSH1b3 - save', () {
    // UTS: rest/unit/RSH1b3/save-put-device-details-0
    test('issues PUT with DeviceDetails', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'id': 'device-001',
            'clientId': 'client-abc',
            'platform': 'ios',
            'formFactor': 'phone',
            'metadata': {},
            'push': {
              'recipient': {
                'transportType': 'apns',
                'deviceToken': 'token-123',
              },
              'state': 'Active',
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

      final device = DeviceDetails(
        id: 'device-001',
        clientId: 'client-abc',
        platform: 'ios',
        formFactor: 'phone',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'apns',
            'deviceToken': 'token-123',
          },
        ),
      );

      final result = await client.push.admin.deviceRegistrations.save(device);

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('PUT'));
      expect(
        request.url.path,
        equals(
          '/push/deviceRegistrations/${Uri.encodeComponent('device-001')}',
        ),
      );

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['id'], equals('device-001'));
      expect(body['clientId'], equals('client-abc'));
      expect(body['platform'], equals('ios'));
      expect(body['formFactor'], equals('phone'));
      expect(body['push']['recipient']['transportType'], equals('apns'));

      expect(result, isA<DeviceDetails>());
      expect(result.id, equals('device-001'));
      expect(result.push!.state, equals('Active'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b3/save-updates-existing-1
    test('updates existing device', () async {
      var requestCount = 0;

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          requestCount++;
          if (requestCount == 1) {
            request.respondWith(200, {
              'id': 'device-001',
              'platform': 'ios',
              'formFactor': 'phone',
              'push': {
                'recipient': {
                  'transportType': 'apns',
                  'deviceToken': 'token-old',
                },
                'state': 'Active',
              },
            });
          } else {
            request.respondWith(200, {
              'id': 'device-001',
              'platform': 'ios',
              'formFactor': 'phone',
              'push': {
                'recipient': {
                  'transportType': 'apns',
                  'deviceToken': 'token-new',
                },
                'state': 'Active',
              },
            });
          }
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final device = DeviceDetails(
        id: 'device-001',
        platform: 'ios',
        formFactor: 'phone',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'apns',
            'deviceToken': 'token-old',
          },
        ),
      );

      final result1 = await client.push.admin.deviceRegistrations.save(device);

      final updatedDevice = DeviceDetails(
        id: 'device-001',
        platform: 'ios',
        formFactor: 'phone',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'apns',
            'deviceToken': 'token-new',
          },
        ),
      );

      final result2 =
          await client.push.admin.deviceRegistrations.save(updatedDevice);

      expect(result1.push!.recipient['deviceToken'], equals('token-old'));
      expect(result2.push!.recipient['deviceToken'], equals('token-new'));
      expect(requestCount, equals(2));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b3/save-error-propagated-2
    test('propagates server error', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(400, {
            'error': {
              'code': 40000,
              'statusCode': 400,
              'message': 'Invalid device details',
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

      final device = DeviceDetails(
        id: 'device-001',
        platform: 'ios',
        formFactor: 'phone',
        push: DevicePushDetails(recipient: {}),
      );

      expect(
        () => client.push.admin.deviceRegistrations.save(device),
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

  group('RSH1b4 - remove', () {
    // UTS: rest/unit/RSH1b4/remove-delete-device-0
    test('issues DELETE for device', () async {
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

      await client.push.admin.deviceRegistrations.remove('device-001');

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(
        request.url.path,
        equals(
          '/push/deviceRegistrations/${Uri.encodeComponent('device-001')}',
        ),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b4/remove-nonexistent-succeeds-1
    test('succeeds for nonexistent device', () async {
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
      await client.push.admin.deviceRegistrations.remove('nonexistent-device');

      mockHttp.dispose();
    });
  });

  group('RSH1b5 - removeWhere', () {
    // UTS: rest/unit/RSH1b5/remove-where-clientid-0
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

      await client.push.admin.deviceRegistrations
          .removeWhere({'clientId': 'client-abc'});

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(
        request.url.queryParameters['clientId'],
        equals('client-abc'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b5/remove-where-deviceid-1
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

      await client.push.admin.deviceRegistrations
          .removeWhere({'deviceId': 'device-001'});

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(
        request.url.queryParameters['deviceId'],
        equals('device-001'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH1b5/remove-where-no-match-succeeds-2
    test('succeeds with no matching devices', () async {
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
      await client.push.admin.deviceRegistrations
          .removeWhere({'clientId': 'nonexistent-client'});

      mockHttp.dispose();
    });
  });
}

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';
import '../../../helpers/poll_until.dart';

/// Unit tests for push device authentication (RSH6) and the push admin API
/// clauses that require it (RSH1b3, RSH1b5, RSH1c3, RSH1c4, RSH3d2b).
///
/// These tests use a mocked HTTP client and a mocked push platform to verify
/// that requests operating on the present, activated device carry the
/// appropriate device-auth header (`X-Ably-DeviceToken` per RSH6a, or
/// `X-Ably-DeviceSecret` per RSH6b), and that requests for any other device
/// carry no device-auth header.
///
/// Spec: specification/uts/rest/unit/push/push_device_auth.md
void main() {
  group('RSH6a - X-Ably-DeviceToken device auth on push admin requests', () {
    // UTS: rest/unit/RSH6a/admin-device-registrations-save-own-device-0
    test(
        'RSH6a, RSH1b3 - deviceRegistrations.save for the present activated '
        'device includes device auth', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockHttp, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      final device = DeviceDetails(
        id: deviceId,
        platform: 'android',
        formFactor: 'phone',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'fcm',
            'registrationToken': 'fcm-token-1',
          },
        ),
      );

      await client.push.admin.deviceRegistrations.save(device);

      // The seeding activation POST, then the admin save PUT
      expect(mockHttp.capturedRequests.length, equals(2));

      final request = mockHttp.capturedRequests[1];
      expect(request.method, equals('PUT'));
      expect(
        request.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      // RSH1b3 + RSH6a — the deviceId is that of the present activated
      // client, so the request must include push device authentication
      expect(request.headers['X-Ably-DeviceToken'], equals('ident-token-1'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH6a/admin-save-other-device-no-device-auth-1
    test(
        'RSH6a, RSH1b3 - deviceRegistrations.save for a different device '
        'carries no device auth', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockHttp, mockStorage);

      final device = DeviceDetails(
        id: 'other-device-1',
        platform: 'ios',
        formFactor: 'tablet',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'apns',
            'deviceToken': 'apns-token-1',
          },
        ),
      );

      await client.push.admin.deviceRegistrations.save(device);

      expect(mockHttp.capturedRequests.length, equals(2));

      final request = mockHttp.capturedRequests[1];
      expect(request.method, equals('PUT'));
      expect(
        request.url.path,
        equals(
          '/push/deviceRegistrations/'
          '${Uri.encodeComponent('other-device-1')}',
        ),
      );

      // The deviceId is not that of the present client — no device auth
      expect(request.headers.containsKey('X-Ably-DeviceToken'), isFalse);
      expect(request.headers.containsKey('X-Ably-DeviceSecret'), isFalse);

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH6a/admin-channel-subscriptions-save-own-device-2
    test(
        'RSH6a, RSH1c3, RSH1c4 - channelSubscriptions save/remove for the '
        'present device include device auth', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockHttp, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      final subscription = PushChannelSubscription.forDevice(
        channel: 'push-test-channel',
        deviceId: deviceId,
      );

      // RSH1c3
      await client.push.admin.channelSubscriptions.save(subscription);
      // RSH1c4
      await client.push.admin.channelSubscriptions.remove(subscription);

      // Seeding POST, then the subscription POST, then the subscription
      // DELETE
      expect(mockHttp.capturedRequests.length, equals(3));

      // RSH1c3 — the save POST includes device auth
      final saveRequest = mockHttp.capturedRequests[1];
      expect(saveRequest.method, equals('POST'));
      expect(saveRequest.url.path, equals('/push/channelSubscriptions'));
      final body = saveRequest.jsonBody as Map<String, dynamic>;
      expect(body['channel'], equals('push-test-channel'));
      expect(body['deviceId'], equals(deviceId));
      expect(
        saveRequest.headers['X-Ably-DeviceToken'],
        equals('ident-token-1'),
      );

      // RSH1c4 — the remove DELETE includes device auth
      final removeRequest = mockHttp.capturedRequests[2];
      expect(removeRequest.method, equals('DELETE'));
      expect(removeRequest.url.path, equals('/push/channelSubscriptions'));
      expect(
        removeRequest.url.queryParameters['channel'],
        equals('push-test-channel'),
      );
      expect(
        removeRequest.url.queryParameters['deviceId'],
        equals(deviceId),
      );
      expect(
        removeRequest.headers['X-Ably-DeviceToken'],
        equals('ident-token-1'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH6a/admin-remove-where-own-device-3
    test(
        'RSH6a, RSH1b5 - deviceRegistrations.removeWhere for the present '
        'device includes device auth', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockHttp, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      await client.push.admin.deviceRegistrations
          .removeWhere({'deviceId': deviceId});

      expect(mockHttp.capturedRequests.length, equals(2));

      final request = mockHttp.capturedRequests[1];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(request.url.queryParameters['deviceId'], equals(deviceId));

      // RSH1b5 + RSH6a — the deviceId param is that of the present
      // activated client
      expect(request.headers['X-Ably-DeviceToken'], equals('ident-token-1'));

      mockHttp.dispose();
    });
  });

  group('RSH6b - X-Ably-DeviceSecret device auth', () {
    // UTS: rest/unit/RSH6b/device-secret-auth-before-identity-token-0
    test(
        'RSH6b, RSH3d2b - a device with a deviceSecret but no '
        'deviceIdentityToken authenticates with X-Ably-DeviceSecret', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockHttp, mockStorage);

      // Registration succeeds but confers no deviceIdentityToken
      Future<DeviceRegistrationResult> registerCallback(
        DeviceDetails device,
      ) async =>
          const DeviceRegistrationResult();

      await client.push.activate(registerCallback: registerCallback);
      await _pollUntilActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      final deviceId = mockStorage.dump()['ably.push.deviceId']!;
      final deviceSecret = mockStorage.dump()['ably.push.deviceSecret']!;

      await client.push.deactivate();
      await _pollUntilActivationState(mockStorage, 'NotActivated');

      // Registration went through the callback, so the only HTTP request is
      // the deregistration DELETE (RSH3d2b)
      expect(mockHttp.capturedRequests.length, equals(1));

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(request.url.queryParameters['deviceId'], equals(deviceId));

      // RSH6b — deviceSecret auth, since the device has no
      // deviceIdentityToken
      expect(request.headers['X-Ably-DeviceSecret'], equals(deviceSecret));
      expect(request.headers.containsKey('X-Ably-DeviceToken'), isFalse);

      mockHttp.dispose();
    });
  });
}

/// Handler consulted before the standard routes; returns true if it handled
/// (or held) the request.
typedef _OverrideHandler = bool Function(PendingRequest request);

/// HTTP mock routing registration and admin endpoints; captures every
/// request into [MockHttpClient.capturedRequests]. Individual tests may
/// override specific routes via the [overrides] handler, which is consulted
/// first and may hold requests without responding.
MockHttpClient _mockRegistrationServer({_OverrideHandler? overrides}) =>
    MockHttpClient(
      onConnectionAttempt: (conn) => conn.respondWithSuccess(),
      onRequest: (request) {
        if (overrides != null && overrides(request)) {
          // The override handled (or held) the request
          return;
        }
        if (request.method == 'POST' &&
            request.url.path == '/push/deviceRegistrations') {
          final body = request.jsonBody as Map<String, dynamic>;
          request.respondWith(201, {
            ...body,
            'deviceIdentityToken': {'token': 'ident-token-1'},
          });
        } else if (request.method == 'PUT' &&
            request.url.path.startsWith('/push/deviceRegistrations/')) {
          request.respondWith(200, request.jsonBody as Object);
        } else if (request.method == 'PATCH' &&
            request.url.path.startsWith('/push/deviceRegistrations/')) {
          request.respondWith(200, request.jsonBody as Object);
        } else if (request.method == 'DELETE' &&
            request.url.path == '/push/deviceRegistrations') {
          request.respondWith(204, '');
        } else if (request.method == 'POST' &&
            request.url.path == '/push/channelSubscriptions') {
          request.respondWith(200, request.jsonBody as Object);
        } else if (request.method == 'DELETE' &&
            request.url.path == '/push/channelSubscriptions') {
          request.respondWith(204, '');
        } else {
          request.respondWith(500, {
            'error': {'message': 'unexpected request', 'code': 50000},
          });
        }
      },
    );

PushPlatformConfig _buildPushPlatform(
  MockPushStorage storage, {
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
}) =>
    PushPlatformConfig(
      platform: 'android',
      formFactor: 'phone',
      storage: storage,
      requestToken: requestToken ??
          () async =>
              token ??
              const PushDeviceToken(
                transportType: 'fcm',
                token: 'fcm-token-1',
              ),
    );

RestClient _pushClient(
  MockHttpClient mockHttp,
  MockPushStorage storage, {
  String? clientId,
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
}) =>
    RestClient.forTesting(
      options: ClientOptions(
        key: 'appId.keyId:keySecret',
        clientId: clientId,
        pushPlatform: _buildPushPlatform(
          storage,
          token: token,
          requestToken: requestToken,
        ),
      ),
      httpClient: mockHttp,
    );

/// Runs a full activation so that [storage] holds a registered device
/// (deviceId, deviceSecret, deviceIdentityToken, pushRecipient) and the
/// persisted activation state is WaitingForNewPushDeviceDetails.
Future<RestClient> _activateInto(
  MockHttpClient mockHttp,
  MockPushStorage storage, {
  String? clientId,
}) async {
  final client = _pushClient(mockHttp, storage, clientId: clientId);
  await client.push.activate();
  await _pollUntilActivationState(storage, 'WaitingForNewPushDeviceDetails');
  return client;
}

/// Polls until the persisted activation state equals [state].
Future<void> _pollUntilActivationState(
  MockPushStorage storage,
  String state,
) =>
    pollUntil<bool>(
      () async =>
          storage.dump()['ably.push.activationState'] == state ? true : null,
    );

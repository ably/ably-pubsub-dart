import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';
import '../../../helpers/poll_until.dart';

/// Unit tests for LocalDevice (RSH8, RSH8a, RSH8d, RSH8e, RSH8f, RSH8k,
/// RSH8k1, RSH8k2).
///
/// These tests use a mocked HTTP client and a mocked push platform
/// (storage + requestToken via ClientOptions.pushPlatform) to verify the
/// behaviour of the LocalDevice and its device accessor.
///
/// Spec: uts/rest/unit/push/local_device.md
void main() {
  group('RSH8 - device accessor', () {
    // UTS: rest/unit/RSH8/device-returns-local-device-0
    test(
        'RSH8, RSH8k1, RSH8k2 - device accessor returns the activated '
        'LocalDevice', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockHttp, mockStorage);

      final device = await _getDevice(client);

      final persisted = mockStorage.dump();
      expect(device.id, equals(persisted['ably.push.deviceId']));
      // RSH8k2
      expect(device.deviceSecret, isNotNull);
      // RSH8k1
      expect(device.deviceIdentityToken, equals('ident-token-1'));
      expect(device.platform, equals('android'));
      expect(device.formFactor, equals('phone'));
      expect(
        device.push?.recipient,
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-1',
        }),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH8a/device-populated-from-persisted-state-0
    test(
        'RSH8a - LocalDevice is populated from persisted state without any '
        'request', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      // client1: register and persist
      await _activateInto(mockHttp, mockStorage);
      final persisted = mockStorage.dump();

      // A fresh client over the same storage simulates an app restart
      final client2 = _pushClient(mockHttp, mockStorage);
      final requestsBefore = mockHttp.capturedRequests.length;
      final device = await _getDevice(client2);

      expect(device.id, equals(persisted['ably.push.deviceId']));
      expect(device.deviceSecret, equals(persisted['ably.push.deviceSecret']));
      expect(device.deviceIdentityToken, equals('ident-token-1'));
      expect(
        device.push?.recipient,
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-1',
        }),
      );

      // The device accessor made no HTTP request of its own
      expect(mockHttp.capturedRequests.length, equals(requestsBefore));

      mockHttp.dispose();
    });
  });

  group('RSH8k1 - deviceIdentityToken before registration', () {
    // UTS: rest/unit/RSH8k1/device-identity-token-null-before-registration-0
    test('RSH8k1 - deviceIdentityToken is null before registration', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockHttp, mockStorage);

      final device = await _getDevice(client);

      expect(device.deviceIdentityToken, isNull);
      // Deliberately no assertion on device.id / device.deviceSecret — see
      // the UTS spec Notes (eager vs lazy generation is not portable).

      mockHttp.dispose();
    });
  });

  group('RSH8f - clientId from registration response', () {
    // UTS: rest/unit/RSH8f/clientid-from-registration-response-0
    test(
        'RSH8f - clientId from the registration response is set on the '
        'LocalDevice', () async {
      final mockHttp = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'POST' &&
              req.url.path == '/push/deviceRegistrations') {
            final body = req.jsonBody as Map<String, dynamic>;
            req.respondWith(201, {
              ...body,
              'deviceIdentityToken': {'token': 'ident-token-1'},
              'clientId': 'client-from-server',
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      // no clientId — unidentified (RSA7)
      final client = _pushClient(mockHttp, mockStorage);

      await client.push.activate();
      final device = await _getDevice(client);

      expect(device.clientId, equals('client-from-server'));

      mockHttp.dispose();
    });
  });

  group('RSH8d - late clientId', () {
    // UTS: rest/unit/RSH8d/late-clientid-persisted-0
    test('RSH8d - a clientId acquired after registration is set and persisted',
        () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _lateIdentifiedClient(mockHttp, mockStorage);

      await client.push.activate();
      final device = await _getDevice(client);
      expect(device.deviceIdentityToken, equals('ident-token-1'));
      // registered while unidentified
      expect(device.clientId, isNull);

      // The client becomes identified: the second token carries clientId
      // "alice" (RSA7b2)
      final tokenDetails = await client.auth.authorize();
      expect(tokenDetails?.clientId, equals('alice'));

      // RSH8d — the LocalDevice clientId is set...
      await pollUntil(
        () async =>
            (await _getDevice(client)).clientId == 'alice' ? true : null,
      );

      // ...and persisted: a fresh client over the same storage sees it
      // (polled, because persistence may settle asynchronously after the
      // clientId is set)
      final device2 = await pollUntil(() async {
        final d = await _getDevice(_pushClient(mockHttp, mockStorage));
        return d.clientId == 'alice' ? d : null;
      });
      expect(device2.id, equals(device.id));
      expect(device2.clientId, equals('alice'));

      mockHttp.dispose();
    });
  });

  group('RSH8e - late clientId triggers registration sync', () {
    // UTS: rest/unit/RSH8e/late-clientid-triggers-sync-0
    test(
        'RSH8e - a late clientId on a registered device triggers a '
        'registration sync', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _lateIdentifiedClient(mockHttp, mockStorage);

      // registered; machine in WaitingForNewPushDeviceDetails
      await client.push.activate();
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // client becomes identified as "alice" (RSA7b2), RSH8d sets clientId
      await client.auth.authorize();

      // RSH8e — GotPushDeviceDetails is sent once the clientId is set,
      // observable as the RSH3d3b registration sync
      final patch = await pollUntil(() async {
        final patches = mockHttp.capturedRequests
            .where((r) => r.method == 'PATCH')
            .toList();
        return patches.isNotEmpty ? patches.first : null;
      });

      expect(
        patch.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      // RSH3d3b + RSH6a — push device authentication
      expect(patch.headers['X-Ably-DeviceToken'], equals('ident-token-1'));

      // The sync completes and the machine settles back into
      // WaitingForNewPushDeviceDetails (RSH3d3d -> WaitingForRegistrationSync,
      // then RegistrationSynced -> RSH3e2a)
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      mockHttp.dispose();
    });
  });
}

/// Mirrors the UTS `mock_registration_server` helper: an HTTP mock routing
/// the push registration endpoints, echoing request bodies. Captured
/// requests are available on the returned mock's
/// [MockHttpClient.capturedRequests]. Individual tests override specific
/// routes via [overrides], which is consulted first and may hold requests
/// without responding.
MockHttpClient _mockRegistrationServer({
  bool Function(PendingRequest req)? overrides,
}) {
  return MockHttpClient(
    onConnectionAttempt: (conn) => conn.respondWithSuccess(),
    onRequest: (req) {
      if (overrides != null && overrides(req)) {
        // the override handled (or held) the request
        return;
      }
      if (req.method == 'POST' && req.url.path == '/push/deviceRegistrations') {
        final body = req.jsonBody as Map<String, dynamic>;
        req.respondWith(201, {
          ...body,
          'deviceIdentityToken': {'token': 'ident-token-1'},
        });
      } else if (req.method == 'PUT' &&
          req.url.path.startsWith('/push/deviceRegistrations/')) {
        req.respondWith(200, req.jsonBody as Object);
      } else if (req.method == 'PATCH' &&
          req.url.path.startsWith('/push/deviceRegistrations/')) {
        req.respondWith(200, req.jsonBody as Object);
      } else if (req.method == 'DELETE' &&
          req.url.path == '/push/deviceRegistrations') {
        req.respondWith(204, '');
      } else {
        req.respondWith(500, {
          'error': {'message': 'unexpected request', 'code': 50000},
        });
      }
    },
  );
}

/// Mirrors the UTS `build_push_platform` helper.
PushPlatformConfig _buildPushPlatform(
  MockPushStorage storage, {
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
}) {
  return PushPlatformConfig(
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
}

/// Mirrors the UTS `push_client` helper: `install_push_platform` maps to
/// `ClientOptions.pushPlatform` and `install_mock` maps to the injected
/// [MockHttpClient].
RestClient _pushClient(
  MockHttpClient mockHttp,
  MockPushStorage storage, {
  String? clientId,
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
}) {
  return RestClient.forTesting(
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
}

/// Mirrors the UTS `activate_into` helper: runs a full activation so that
/// [storage] holds a registered device and the persisted activation state is
/// WaitingForNewPushDeviceDetails.
Future<RestClient> _activateInto(
  MockHttpClient mockHttp,
  MockPushStorage storage, {
  String? clientId,
}) async {
  final client = _pushClient(mockHttp, storage, clientId: clientId);
  await client.push.activate();
  await _pollForActivationState(storage, 'WaitingForNewPushDeviceDetails');
  return client;
}

/// Mirrors the UTS `late_identified_client` helper: a client using token
/// auth via authCallback, so that its identity can change after construction
/// (RSA7b2/RSA7b3). The first token is anonymous, every later token is
/// identified as "alice". No HTTP is involved — the callback returns
/// TokenDetails directly (RSA8d).
RestClient _lateIdentifiedClient(
  MockHttpClient mockHttp,
  MockPushStorage storage,
) {
  var authCalls = 0;
  return RestClient.forTesting(
    options: ClientOptions(
      authCallback: (tokenParams) async {
        authCalls += 1;
        if (authCalls == 1) {
          return const TokenDetails(token: 'anon-token-1');
        }
        return const TokenDetails(token: 'alice-token-1', clientId: 'alice');
      },
      pushPlatform: _buildPushPlatform(storage),
    ),
    httpClient: mockHttp,
  );
}

/// Polls until the persisted `ably.push.activationState` equals [state].
Future<void> _pollForActivationState(
  MockPushStorage storage,
  String state,
) async {
  await pollUntil(
    () async =>
        storage.dump()['ably.push.activationState'] == state ? true : null,
  );
}

/// Maps the UTS `AWAIT client.device()` accessor onto ably-dart's
/// `RestClient.getDevice()`, which loads the LocalDevice from persisted
/// state on first call (RSH8, RSH8a).
Future<LocalDevice> _getDevice(RestClient client) => client.getDevice();

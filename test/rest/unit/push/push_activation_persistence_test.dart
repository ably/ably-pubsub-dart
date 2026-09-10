import 'dart:convert';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';
import '../../../helpers/poll_until.dart';

/// Unit tests for the persistence seam of push activation (RSH3h, RSH3a2c,
/// RSH8a, RSH8a1, RSH8b, RSH8c).
///
/// These tests use a mocked HTTP client and a mocked push platform
/// (storage + requestToken via ClientOptions.pushPlatform) to verify what
/// the SDK loads from storage on a fresh start, how it recovers from corrupt
/// or partial persisted state, how it behaves when persistence itself fails,
/// and when the registration outcome is persisted.
///
/// Spec: uts/rest/unit/push/push_activation_persistence.md
void main() {
  group('RSH8a1 - corrupt persisted state', () {
    // UTS: rest/unit/RSH8a1/corrupt-device-state-discarded-0
    test(
        'RSH8a1, RSH3h - corrupt persisted device state discards all '
        'persisted state', () async {
      var tokenRequests = 0;
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      mockStorage.seed({
        'ably.push.deviceId': 'seeded-device-1',
        // deviceSecret missing — the id/secret pair is incomplete, so the
        // device load must fail
        'ably.push.deviceIdentityToken': '"stale-token"',
        'ably.push.activationState': 'WaitingForNewPushDeviceDetails',
      });
      final client = _pushClient(
        mockHttp,
        mockStorage,
        requestToken: () async {
          tokenRequests += 1;
          return const PushDeviceToken(
            transportType: 'fcm',
            token: 'fcm-token-1',
          );
        },
      );

      await client.push.activate();
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      // Full first-time registration — not the registration sync the stale
      // state would imply
      expect(tokenRequests, equals(1));
      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/deviceRegistrations'));

      // RSH8a1 (1) — the seeded device identity was discarded; a fresh id
      // was generated
      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['id'], isNot(equals('seeded-device-1')));

      // The stale identity token was discarded and replaced by the
      // registration result
      final persisted = mockStorage.dump();
      expect(
        persisted['ably.push.deviceId'],
        isNot(equals('seeded-device-1')),
      );
      expect(
        json.decode(persisted['ably.push.deviceIdentityToken']!),
        equals('ident-token-1'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSH8a1/corrupt-machine-state-recovers-1
    test(
        'RSH8a1, RSH3h - corrupt persisted machine state recovers without '
        'crashing', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      mockStorage.seed({
        'ably.push.deviceId': 'seeded-device-1',
        'ably.push.deviceSecret': 'seeded-secret',
        'ably.push.deviceIdentityToken': '"seeded-ident-token"',
        'ably.push.pushRecipient':
            '{"transportType":"fcm","registrationToken":"seeded-token-1"}',
        'ably.push.activationState': 'BogusStateName',
      });
      final client = _pushClient(mockHttp, mockStorage);

      // Must not crash: the machine falls back to NotActivated (RSH3h),
      // where the registered device (it has a deviceIdentityToken) is
      // validated per RSH3a2a
      await client.push.activate();

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals(
          '/push/deviceRegistrations/'
          '${Uri.encodeComponent('seeded-device-1')}',
        ),
      );
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      mockHttp.dispose();
    });
  });

  group('RSH3a2c - persisted push details', () {
    // UTS: rest/unit/RSH3a2c/existing-push-details-skip-token-request-0
    test(
        'RSH3a2c, RSH8a - persisted push details skip the platform token '
        'request', () async {
      var tokenRequests = 0;
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      mockStorage.seed({
        'ably.push.deviceId': 'seeded-device-1',
        'ably.push.deviceSecret': 'seeded-secret',
        // no deviceIdentityToken — the device is not yet registered
        'ably.push.pushRecipient':
            '{"transportType":"fcm","registrationToken":"persisted-token-1"}',
        'ably.push.activationState': 'NotActivated',
      });
      final client = _pushClient(
        mockHttp,
        mockStorage,
        requestToken: () async {
          tokenRequests += 1;
          return const PushDeviceToken(
            transportType: 'fcm',
            token: 'unexpected-token',
          );
        },
      );

      await client.push.activate();
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      // RSH3a2c — the platform was not consulted
      expect(tokenRequests, equals(0));

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/deviceRegistrations'));

      final body = request.jsonBody as Map<String, dynamic>;
      // RSH3a2b — id and deviceSecret already exist, so they are not
      // regenerated
      expect(body['id'], equals('seeded-device-1'));
      // RSH8a — the recipient came from persisted state
      final push = body['push'] as Map<String, dynamic>;
      expect(
        push['recipient'],
        equals({
          'transportType': 'fcm',
          'registrationToken': 'persisted-token-1',
        }),
      );

      mockHttp.dispose();
    });
  });

  group('RSH8b - persistence failure', () {
    // UTS: rest/unit/RSH8b/persist-failure-fails-activate-then-recovers-0
    test(
        'RSH8b - a persistence failure fails activate; activation recovers '
        'once it clears', () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      mockStorage.failWrites = true;
      final client = _pushClient(mockHttp, mockStorage);

      // The generated identifiers cannot be persisted: activation fails,
      // no HTTP request
      Object? activateError;
      try {
        await client.push.activate();
      } catch (e) {
        activateError = e;
      }
      expect(
        activateError,
        isNotNull,
        reason: 'activate() must fail when the generated identifiers cannot '
            'be persisted',
      );
      expect(mockHttp.capturedRequests, isEmpty);

      // Once storage works again, the SAME client can activate: the failed
      // device load must not be cached
      mockStorage.failWrites = false;
      await client.push.activate();

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(mockHttp.capturedRequests[0].method, equals('POST'));
      await _pollForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      mockHttp.dispose();
    });
  });

  group('RSH8c - identity token persistence timing', () {
    // UTS: rest/unit/RSH8c/identity-token-persisted-only-after-registration-0
    test(
        'RSH8c - deviceIdentityToken is persisted only after successful '
        'registration', () async {
      PendingRequest? heldPost;
      final mockHttp = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'POST' &&
              req.url.path == '/push/deviceRegistrations' &&
              heldPost == null) {
            // hold the registration open
            heldPost = req;
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockHttp, mockStorage);

      final activation = client.push.activate();
      await pollUntil(() async => heldPost);

      // Registration in flight: the identity token must not be persisted yet
      expect(
        mockStorage.dump().containsKey('ably.push.deviceIdentityToken'),
        isFalse,
      );

      final heldBody = heldPost!.jsonBody as Map<String, dynamic>;
      heldPost!.respondWith(201, {
        ...heldBody,
        'deviceIdentityToken': {'token': 'ident-token-1'},
      });
      await activation;

      // After activate resolves and the fire-and-forget writes settle
      await pollUntil(
        () async => mockStorage.dump()['ably.push.deviceIdentityToken'],
      );
      expect(
        json.decode(mockStorage.dump()['ably.push.deviceIdentityToken']!),
        equals('ident-token-1'),
      );

      mockHttp.dispose();
    });
  });

  group('RSH3h - no persisted state', () {
    // UTS: rest/unit/RSH3h/no-persisted-state-starts-not-activated-0
    test('RSH3h - with no persisted state the machine starts in NotActivated',
        () async {
      final mockHttp = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockHttp, mockStorage);

      // NotActivated is the initial state: deactivate resolves immediately
      // (RSH3a1d)
      await client.push.deactivate();
      expect(mockHttp.capturedRequests, isEmpty);

      // and activate runs the full first-time registration flow from
      // NotActivated
      await client.push.activate();
      expect(mockHttp.capturedRequests.length, equals(1));
      expect(mockHttp.capturedRequests[0].method, equals('POST'));
      expect(
        mockHttp.capturedRequests[0].url.path,
        equals('/push/deviceRegistrations'),
      );
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

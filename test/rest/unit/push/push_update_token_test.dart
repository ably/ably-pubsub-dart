import 'dart:convert';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';

/// Unit tests for `Push#updateToken` (RSH2f), the portable API through which
/// the application delivers a rotated or additional platform token, thereby
/// producing the RSH8g `GotPushDeviceDetails` event.
///
/// `updateToken` resolves once the new recipient has been persisted and the
/// event has been handed to the state machine. The registration sync the
/// event triggers (RSH3d3b/RSH3d3c) is fire-and-forget: its outcome is
/// reported through the `updatedCallback` provided to `Push#activate`
/// (RSH3e2c/RSH3e3d), never through the `updateToken` return value. Tests
/// therefore poll for the sync's observable effects (the HTTP request, the
/// persisted state) rather than awaiting a promise.
///
/// These tests use a mocked HTTP client and a mocked push platform, and are
/// black-box: they never construct events or inspect machine state directly.
///
/// Spec: specification/uts/rest/unit/push/push_update_token.md
void main() {
  group('RSH3d3 - rotated token sync', () {
    // UTS: rest/unit/RSH3d3b/update-token-patch-0
    test(
        'RSH8g, RSH3d3 - a rotated fcm token is synced via PATCH with '
        'changed fields only', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(server, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );

      // The sync is fire-and-forget: poll for the PATCH it issues
      await _waitFor(() => server.requests.length == 2);
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      final request = server.requests[1];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      // RSH3d3b — only the changed fields travel in the body; the device id
      // is in the URL
      expect(
        request.jsonBody,
        equals({
          'push': {
            'recipient': {
              'transportType': 'fcm',
              'registrationToken': 'fcm-token-2',
            },
          },
        }),
      );

      // RSH3d3b + RSH6a — push device authentication
      expect(request.headers['X-Ably-DeviceToken'], equals('ident-token-1'));

      // The rotated recipient was persisted
      expect(
        json.decode(mockStorage.dump()['ably.push.pushRecipient']!),
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-2',
        }),
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH8g/update-token-apns-recipient-1
    test('RSH8g - an apns token maps to an apns recipient', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(
        server,
        mockStorage,
        token: const PushDeviceToken(
          transportType: 'apns',
          token: 'apns-token-1',
        ),
        platform: 'ios',
      );
      await client.push.activate();
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      await client.push.updateToken(
        const PushDeviceToken(transportType: 'apns', token: 'apns-token-2'),
      );
      await _waitFor(() => server.requests.length == 2);

      final request = server.requests[1];
      expect(request.method, equals('PATCH'));
      // RSH3d3b — an apns recipient's token field is deviceToken
      expect(
        request.jsonBody,
        equals({
          'push': {
            'recipient': {
              'transportType': 'apns',
              'deviceToken': 'apns-token-2',
            },
          },
        }),
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH8g/update-token-cold-start-3
    test(
        'RSH8g, RSH3h - updateToken works from persisted state on a cold '
        'start, without activate() this session', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      await _activateInto(server, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // A fresh client over the same storage simulates an app restart
      final restarted = _pushClient(server, mockStorage);
      await restarted.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );
      await _waitFor(() => server.requests.length == 2);

      final request = server.requests[1];
      expect(request.method, equals('PATCH'));
      // The restarted client loaded the persisted device id and addressed
      // the same registration (RSH3h, RSH3d3b)
      expect(
        request.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );
      final dynamic body = request.jsonBody;
      expect(
        body['push']['recipient']['registrationToken'],
        equals('fcm-token-2'),
      );

      server.httpClient.dispose();
    });
  });

  group('RSH2f1, RSH2f2 - updateToken guards', () {
    // UTS: rest/unit/RSH2f2/update-token-requires-activation-2
    test(
        'RSH2f2 - updateToken requires an activated device, and does not '
        'disturb a later activation', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(server, mockStorage);

      try {
        await client.push.updateToken(
          const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
        );
        fail('updateToken on a non-activated device should have failed');
      } on AblyException catch (error) {
        expect(error.code, equals(40000));
      }

      // Nothing reached the machine or the network
      await _processPendingEvents();
      expect(server.requests, isEmpty);

      // A subsequent activation is unaffected by the rejected update
      await client.push.activate();
      expect(server.requests.length, equals(1));
      expect(server.requests[0].method, equals('POST'));
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH2f1/update-token-validation-5
    test(
        'RSH2f1 - malformed tokens are rejected without touching the '
        'machine, the network, or storage', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(server, mockStorage);
      final persistedBefore = mockStorage.dump();

      // The UTS spec's null-token case is unrepresentable here: Dart's
      // null safety makes `updateToken(null)` a compile-time error, so the
      // null rejection of RSH2f1 is enforced by the type system. The
      // remaining invalid tokens are exercised at runtime: a "web"
      // transport (web recipients are not app-suppliable) and an empty
      // token string.
      const badTokens = [
        PushDeviceToken(transportType: 'web', token: 'web-token-1'),
        PushDeviceToken(transportType: 'fcm', token: ''),
      ];
      for (final bad in badTokens) {
        try {
          await client.push.updateToken(bad);
          fail('updateToken should have rejected $bad');
        } on AblyException catch (error) {
          expect(error.code, equals(40000));
        }
      }

      await _processPendingEvents();
      expect(
        server.requests.length,
        equals(1),
        reason: 'just the activation POST',
      );
      // Storage untouched, recipient included
      expect(mockStorage.dump(), equals(persistedBefore));

      server.httpClient.dispose();
    });
  });

  group('RSH3e - sync outcome reporting', () {
    // UTS: rest/unit/RSH3e3d/update-token-sync-failure-callback-4
    test(
        'RSH3e3d, RSH3f1a - a failed sync is reported via updatedCallback; '
        'a retry re-validates per RSH3a2a', () async {
      var failPatch = true;
      final server = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'PATCH' && failPatch) {
            req.respondWith(400, {
              'error': {
                'message': 'sync rejected',
                'code': 40199,
                'statusCode': 400,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = _pushClient(server, mockStorage);

      final syncResults = <ErrorInfo?>[];
      await client.push.activate(updatedCallback: syncResults.add);
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // The sync is fire-and-forget: updateToken resolves despite the PATCH
      // failing
      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );

      // RSH3e3d — the failure reaches the updatedCallback
      await _waitFor(() => syncResults.length == 1);
      expect(syncResults[0]?.code, equals(40199));

      // The rotated recipient was persisted even though the sync failed
      expect(
        json.decode(mockStorage.dump()['ably.push.pushRecipient']!),
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-2',
        }),
      );

      // RSH3e3b — the machine is in AfterRegistrationSyncFailed
      await _waitForActivationState(
        mockStorage,
        'AfterRegistrationSyncFailed',
      );

      // RSH3f1a — a retry with the server healthy re-runs the RSH3a2a
      // validation, which per RSH3a2a3 is the same RSH3d3b sync: a second
      // PATCH with the complete recipient
      failPatch = false;
      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );

      await _waitFor(() => _patches(server).length == 2);
      final retry = _patches(server)[1];
      expect(
        retry.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );
      final dynamic retryBody = retry.jsonBody;
      expect(
        retryBody['push']['recipient']['registrationToken'],
        equals('fcm-token-2'),
      );

      // RSH3e2c — the successful sync reaches the updatedCallback with no
      // error
      await _waitFor(() => syncResults.length == 2);
      expect(syncResults[1], isNull);

      // RSH3e2a — settled back in WaitingForNewPushDeviceDetails
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH3e1a/activate-during-token-sync-7
    test(
        'RSH3e1a - activate during an in-flight token sync resolves '
        'immediately without a request', () async {
      PendingRequest? heldPatch;
      final server = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'PATCH' && heldPatch == null) {
            heldPatch = req; // hold the sync open
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(server, mockStorage);

      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );
      // machine now in WaitingForRegistrationSync (RSH3d3d)
      await _waitFor(() => heldPatch != null);

      // RSH3e1a — resolves while the PATCH is still held, so it did not
      // wait for the sync
      await client.push.activate();

      // RSH3e1b — self-transition: no request was issued for the activate
      await _processPendingEvents();
      expect(
        server.requests.length,
        equals(2),
        reason: 'activation POST + held PATCH only',
      );

      heldPatch!.respondWith(200, heldPatch!.jsonBody as Object);

      // RSH3e2a — the released sync settles the machine in
      // WaitingForNewPushDeviceDetails
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      server.httpClient.dispose();
    });
  });

  group('RSH3d3a - custom registerCallback', () {
    // UTS: rest/unit/RSH3d3a/update-token-register-callback-6
    test(
        'RSH3d3a - a device activated via a custom registerCallback syncs '
        'through the same callback', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(server, mockStorage);

      final registeredDevices = <DeviceDetails>[];
      Future<DeviceRegistrationResult> registerCallback(
        DeviceDetails device,
      ) async {
        registeredDevices.add(device);
        return const DeviceRegistrationResult(
          deviceIdentityToken: 'custom-ident-1',
        );
      }

      await client.push.activate(registerCallback: registerCallback);
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );
      await _waitFor(() => registeredDevices.length == 2);

      // RSH3d3a — the sync went through the same registerCallback, with the
      // new recipient
      expect(
        registeredDevices[1].push?.recipient,
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-2',
        }),
      );

      // No HTTP at all: neither the registration nor the sync touched the
      // network
      expect(server.requests, isEmpty);

      // The rotated recipient was persisted
      await _waitFor(() {
        final persisted = mockStorage.dump()['ably.push.pushRecipient'];
        if (persisted == null) {
          return false;
        }
        final dynamic recipient = json.decode(persisted);
        return recipient['registrationToken'] == 'fcm-token-2';
      });

      server.httpClient.dispose();
    });
  });

  group('RSH4 - updateToken event queueing', () {
    // UTS: rest/unit/RSH4/update-token-queued-behind-inflight-sync-8
    test(
        'RSH4 - an update issued during an in-flight sync is queued and '
        'applied after it settles', () async {
      PendingRequest? heldPatch;
      final server = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'PATCH' && heldPatch == null) {
            // hold the first sync open; later PATCHes use the default route
            heldPatch = req;
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(server, mockStorage);

      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );
      await _waitFor(() => heldPatch != null);

      // Resolves (recipient persisted, event handed over), but its sync is
      // queued per RSH4
      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-3'),
      );

      await _processPendingEvents();
      expect(
        _patches(server).length,
        equals(1),
        reason: 'only the held one',
      );

      heldPatch!.respondWith(200, heldPatch!.jsonBody as Object);
      await _waitFor(() => _patches(server).length == 2);

      // RSH3d3b — the dequeued GotPushDeviceDetails issued its own
      // changed-fields PATCH
      expect(
        _patches(server)[1].jsonBody,
        equals({
          'push': {
            'recipient': {
              'transportType': 'fcm',
              'registrationToken': 'fcm-token-3',
            },
          },
        }),
      );

      await _waitFor(() {
        final persisted = mockStorage.dump()['ably.push.pushRecipient'];
        if (persisted == null) {
          return false;
        }
        final dynamic recipient = json.decode(persisted);
        return recipient['registrationToken'] == 'fcm-token-3';
      });
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH4/update-token-discarded-after-deregistration-9
    test(
        'RSH4 - an update racing a deactivation is discarded once the '
        'device is deregistered', () async {
      PendingRequest? heldDelete;
      final server = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'DELETE' && heldDelete == null) {
            heldDelete = req; // hold the deregistration open
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(server, mockStorage);

      final deactivation = client.push.deactivate();
      await _waitFor(() => heldDelete != null);

      // The device still has its deviceIdentityToken, so the guard passes;
      // the event queues
      await client.push.updateToken(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-2'),
      );

      heldDelete!.respondWith(204, '');
      await deactivation;
      await _waitForActivationState(mockStorage, 'NotActivated');

      // RSH4 + RSH3a3a — the queued event was consumed in NotActivated: no
      // sync ever ran
      await _processPendingEvents();
      expect(_patches(server), isEmpty);

      // RSH3g2a — deregistration removed the recipient the update had
      // persisted
      expect(
        mockStorage.dump().containsKey('ably.push.pushRecipient'),
        isFalse,
      );

      server.httpClient.dispose();
    });
  });

  group('RSH8l2 - APNs token variants', () {
    // UTS: rest/unit/RSH8l2/update-token-push-to-start-10
    test(
        'RSH8l2, PCP3a - registering a push-to-start token adds a variant '
        'slot without disturbing the default token', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateIntoApns(server, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      await client.push.updateToken(
        const PushDeviceToken(
          transportType: 'apns',
          token: 'pts-token-1',
          apnsTokenType: 'pushToStart',
        ),
      );

      await _waitFor(() => _patches(server).length == 1);

      final patch = _patches(server)[0];
      expect(
        patch.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      final dynamic body = patch.jsonBody;
      final dynamic recipient = body['push']['recipient'];
      expect(recipient['transportType'], equals('apns'));

      // PCP3a — the variant landed in its slot
      expect(
        recipient['apnsDeviceTokens']['pushToStart'],
        equals('pts-token-1'),
      );

      // RSH8l2 — the default token was preserved (either representation
      // per PCP3a)
      final dynamic defaultToken =
          recipient['deviceToken'] ?? recipient['apnsDeviceTokens']['default'];
      expect(defaultToken, equals('apns-token-1'));

      // The full recipient, variants included, is persisted
      final dynamic persistedRecipient =
          json.decode(mockStorage.dump()['ably.push.pushRecipient']!);
      expect(
        persistedRecipient['apnsDeviceTokens']['pushToStart'],
        equals('pts-token-1'),
      );

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH8l2/update-token-variant-preserves-others-11
    test(
        'RSH8l2 - rotating the default token preserves registered variant '
        'slots', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateIntoApns(server, mockStorage);

      await client.push.updateToken(
        const PushDeviceToken(
          transportType: 'apns',
          token: 'pts-token-1',
          apnsTokenType: 'pushToStart',
        ),
      );
      await _waitFor(() => _patches(server).length == 1);

      // Rotate the default token (apnsTokenType absent — defaults to
      // "default" per PDT4)
      await client.push.updateToken(
        const PushDeviceToken(transportType: 'apns', token: 'apns-token-2'),
      );

      await _waitFor(() => _patches(server).length == 2);

      final patch = _patches(server)[1];
      final dynamic body = patch.jsonBody;
      final dynamic recipient = body['push']['recipient'];

      // The rotated default token (either representation per PCP3a)
      final dynamic defaultToken =
          recipient['deviceToken'] ?? recipient['apnsDeviceTokens']['default'];
      expect(defaultToken, equals('apns-token-2'));

      // RSH8l2 — the pushToStart variant survived the default-token
      // rotation
      expect(
        recipient['apnsDeviceTokens']['pushToStart'],
        equals('pts-token-1'),
      );

      final dynamic persistedRecipient =
          json.decode(mockStorage.dump()['ably.push.pushRecipient']!);
      expect(
        persistedRecipient['apnsDeviceTokens']['pushToStart'],
        equals('pts-token-1'),
      );

      server.httpClient.dispose();
    });
  });
}

/// A mock registration server: the mocked HTTP client plus every request it
/// captured, mirroring the UTS `mock_registration_server` helper.
class _MockServer {
  _MockServer(this.httpClient, this.requests);

  final MockHttpClient httpClient;
  final List<PendingRequest> requests;
}

/// HTTP mock routing registration endpoints; captures every request.
///
/// Individual tests override specific routes via the [overrides] handler,
/// which is consulted first and may hold requests without responding (by
/// returning true after capturing the [PendingRequest]).
_MockServer _mockRegistrationServer({
  bool Function(PendingRequest req)? overrides,
}) {
  final requests = <PendingRequest>[];
  final httpClient = MockHttpClient(
    onRequest: (req) {
      requests.add(req);
      if (overrides != null && overrides(req)) {
        return; // the override handled (or held) the request
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
  return _MockServer(httpClient, requests);
}

/// The PATCH requests captured so far, in order.
List<PendingRequest> _patches(_MockServer server) =>
    server.requests.where((r) => r.method == 'PATCH').toList();

/// Builds a REST client configured with a mock push platform over [storage],
/// mirroring the UTS `push_client` / `build_push_platform` helpers. The mock
/// HTTP client of [server] is injected via `RestClient.forTesting`.
RestClient _pushClient(
  _MockServer server,
  MockPushStorage storage, {
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
  String platform = 'android',
}) =>
    RestClient.forTesting(
      options: ClientOptions(
        key: 'appId.keyId:keySecret',
        pushPlatform: PushPlatformConfig(
          platform: platform,
          formFactor: 'phone',
          storage: storage,
          requestToken: requestToken ??
              () async =>
                  token ??
                  const PushDeviceToken(
                    transportType: 'fcm',
                    token: 'fcm-token-1',
                  ),
        ),
      ),
      httpClient: server.httpClient,
    );

/// Runs a full activation so that [storage] holds a registered device
/// (deviceId, deviceSecret, deviceIdentityToken, pushRecipient) and the
/// persisted activation state is WaitingForNewPushDeviceDetails.
Future<RestClient> _activateInto(
  _MockServer server,
  MockPushStorage storage,
) async {
  final client = _pushClient(server, storage);
  await client.push.activate();
  await _waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');
  return client;
}

/// Activation as in [_activateInto], but as an ios/apns device.
Future<RestClient> _activateIntoApns(
  _MockServer server,
  MockPushStorage storage,
) async {
  final client = _pushClient(
    server,
    storage,
    token: const PushDeviceToken(
      transportType: 'apns',
      token: 'apns-token-1',
    ),
    platform: 'ios',
  );
  await client.push.activate();
  await _waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');
  return client;
}

/// Polls until [condition] returns true, failing the test on timeout.
/// Dart translation of the UTS `poll_until` / `poll_until_success` helpers.
Future<void> _waitFor(
  bool Function() condition, {
  Duration interval = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('_waitFor: condition not met within $timeout');
    }
    await Future<void>.delayed(interval);
  }
}

/// Polls until the persisted `ably.push.activationState` equals [state].
Future<void> _waitForActivationState(MockPushStorage storage, String state) =>
    _waitFor(() => storage.dump()['ably.push.activationState'] == state);

/// UTS `process_pending_events()`: lets in-flight asynchronous work (event
/// dispatch, fire-and-forget persistence, any request a queued event would
/// erroneously issue) settle before asserting that nothing further happened.
Future<void> _processPendingEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

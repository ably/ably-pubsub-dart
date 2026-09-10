import 'dart:async';
import 'dart:convert';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';

/// Unit tests for the Push Activation State Machine (RSH2, RSH3, RSH6a,
/// RSH8h).
///
/// These tests are black-box: they never construct state machine events or
/// inspect machine state directly. Events are produced by driving the public
/// API (`push.activate()`, `push.deactivate()`), by the mocked `requestToken`
/// and by responding to the mocked HTTP requests the machine issues. State is
/// observed through behaviour (which requests are made, which operations
/// resolve or fail) and, after operations settle, through the persisted
/// `ably.push.activationState`.
///
/// Spec: uts/rest/unit/push/push_activation_state_machine.md
void main() {
  tearDown(() {
    _mockHttp?.dispose();
    _mockHttp = null;
  });

  group('RSH2a, RSH3a2, RSH3b, RSH3c - activation', () {
    // UTS: rest/unit/RSH2a/activate-full-flow-0
    test(
        'RSH2a, RSH3a2, RSH3b3, RSH3c2 - activate performs the full '
        'registration flow', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockStorage);

      await client.push.activate();
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );

      expect(capturedRequests.length, equals(1));

      final request = capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/push/deviceRegistrations'));

      // RSH3b3b — the LocalDevice with push details and deviceSecret
      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['id'], isNotNull);
      expect(body['deviceSecret'], isNotNull);
      expect(body['platform'], equals('android'));
      expect(body['formFactor'], equals('phone'));
      final push = body['push'] as Map<String, dynamic>;
      expect(
        push['recipient'],
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-1',
        }),
      );

      // RSH3c2a + RSH8c — the registration response was applied and persisted
      final persisted = mockStorage.dump();
      expect(persisted['ably.push.deviceId'], equals(body['id']));
      expect(persisted['ably.push.deviceSecret'], isNotNull);
      expect(
        json.decode(persisted['ably.push.deviceIdentityToken']!),
        equals('ident-token-1'),
      );
      expect(
        json.decode(persisted['ably.push.pushRecipient']!),
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-1',
        }),
      );
    });

    // UTS: rest/unit/RSH3a2b/device-id-secret-generation-0
    test(
        'RSH3a2b - generated device identifiers are unique and the secret '
        'has sufficient entropy', () async {
      _mockRegistrationServer();
      final storageA = MockPushStorage();
      final storageB = MockPushStorage();

      await _pushClient(storageA).push.activate();
      await _pushClient(storageB).push.activate();
      await _waitFor(
        () => storageA.dump()['ably.push.deviceId'] != null,
        'deviceId to be persisted to storage A',
      );
      await _waitFor(
        () => storageB.dump()['ably.push.deviceId'] != null,
        'deviceId to be persisted to storage B',
      );

      final a = storageA.dump();
      final b = storageB.dump();

      // Unique per device
      expect(a['ably.push.deviceId'], isNot(equals(b['ably.push.deviceId'])));
      expect(
        a['ably.push.deviceSecret'],
        isNot(equals(b['ably.push.deviceSecret'])),
      );

      // The secret is base64 and decodes to at least 32 bytes
      final decoded = base64.decode(a['ably.push.deviceSecret']!);
      expect(decoded.length, greaterThanOrEqualTo(32));
    });

    // UTS: rest/unit/RSH3b3a/activate-register-callback-0
    test(
        'RSH3b3a, RSH8c - activate with a custom registerCallback routes '
        'registration through the callback', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockStorage);

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
      await _waitFor(
        () => mockStorage.dump()['ably.push.deviceIdentityToken'] != null,
        'deviceIdentityToken to be persisted',
      );

      // Registration went through the callback, not HTTP
      expect(capturedRequests, isEmpty);
      expect(registeredDevices.length, equals(1));
      expect(
        registeredDevices[0].push?.recipient,
        equals({
          'transportType': 'fcm',
          'registrationToken': 'fcm-token-1',
        }),
      );

      // RSH8c — the callback's identity token was persisted
      expect(
        json.decode(mockStorage.dump()['ably.push.deviceIdentityToken']!),
        equals('custom-ident-1'),
      );
    });

    // UTS: rest/unit/RSH3c3a/registration-failure-0
    test(
        'RSH3c3 - failed registration fails activate and returns to '
        'NotActivated', () async {
      var failRegistration = true;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'POST' &&
              request.url.path == '/push/deviceRegistrations' &&
              failRegistration) {
            request.respondWith(400, {
              'error': {
                'message': 'registration rejected',
                'code': 40198,
                'statusCode': 400,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockStorage);

      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40198),
        ),
      );
      expect(capturedRequests.length, equals(1));
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );

      // RSH3c3b — from NotActivated, activation can be retried successfully
      failRegistration = false;
      await client.push.activate();
      expect(capturedRequests.length, equals(2));
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );
    });

    // UTS: rest/unit/RSH3b4a/token-failure-0
    test(
        'RSH3b4, RSH8h - failed token acquisition fails activate and returns '
        'to NotActivated', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(
        mockStorage,
        requestToken: () => throw Exception('permission denied'),
      );

      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('permission denied'),
            'an error whose message contains "permission denied"',
          ),
        ),
      );

      // No registration was attempted
      expect(capturedRequests, isEmpty);
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3b1a/activate-while-waiting-push-details-0
    test(
        'RSH3b1a - repeated activate while waiting for push device details '
        'is idempotent', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();

      final tokenCompleter = Completer<PushDeviceToken>();
      var tokenRequests = 0;
      final client = _pushClient(
        mockStorage,
        requestToken: () {
          tokenRequests += 1;
          return tokenCompleter.future;
        },
      );

      final first = client.push.activate(); // pends on requestToken
      final second = client.push.activate(); // RSH3b1a — self-transition

      tokenCompleter.complete(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-1'),
      );

      await first;
      await second;

      expect(tokenRequests, equals(1));
      expect(capturedRequests.length, equals(1));
      expect(capturedRequests[0].method, equals('POST'));
    });

    // UTS: rest/unit/RSH3b2a/deactivate-while-waiting-push-details-0
    test(
        'RSH3b2 - deactivate while waiting for push device details returns '
        'to NotActivated', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();

      final tokenCompleter = Completer<PushDeviceToken>();
      final client = _pushClient(
        mockStorage,
        requestToken: () => tokenCompleter.future,
      );

      final activation = client.push.activate(); // pends on requestToken
      // The UTS spec never settles this operation; guard against an
      // unobserved failure if the implementation rejects it.
      activation.ignore();

      await client.push.deactivate(); // RSH3b2a — resolves with no error
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );

      // The token arrives late: RSH3a3a — consumed in NotActivated, no
      // registration
      tokenCompleter.complete(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-1'),
      );

      // No deregistration DELETE (nothing was registered), and no late POST;
      // allow any erroneous request to surface.
      await _settle(const Duration(milliseconds: 500));
      expect(capturedRequests, isEmpty);
      expect(
        mockStorage.dump()['ably.push.activationState'],
        equals('NotActivated'),
      );
    });

    // UTS: rest/unit/RSH3c1a/activate-while-registering-0
    test(
        'RSH3c1a - repeated activate while device registration is in flight '
        'is idempotent', () async {
      PendingRequest? heldPost;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'POST' &&
              request.url.path == '/push/deviceRegistrations' &&
              heldPost == null) {
            heldPost = request; // hold the registration open
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockStorage);

      final first = client.push.activate();
      await _waitFor(
        () => heldPost != null,
        'the registration POST to be issued and held',
      );

      // RSH3c1a — self-transition, no second POST
      final second = client.push.activate();

      heldPost!.respondWith(201, <String, dynamic>{
        ...heldPost!.jsonBody as Map<String, dynamic>,
        'deviceIdentityToken': {'token': 'ident-token-1'},
      });

      await first;
      await second;

      expect(capturedRequests.length, equals(1));
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );
    });
  });

  group('RSH3a2a, RSH3d1, RSH3e, RSH3f - re-activation and registration sync',
      () {
    // UTS: rest/unit/RSH3a2a3/activate-existing-registration-sync-0
    test(
        'RSH3a2a, RSH3a2a3, RSH3e2 - activate on an already-registered '
        'device syncs the registration via PATCH', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // A fresh client over the same storage simulates an app restart
      final client = _pushClient(mockStorage);
      await client.push.activate();
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );

      // One POST from the seeding activation, then exactly one sync PATCH —
      // no second POST
      expect(capturedRequests.length, equals(2));
      final request = capturedRequests[1];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      // RSH3d3b — changed fields only, with the complete recipient
      final body = request.jsonBody as Map<String, dynamic>;
      expect(
        body,
        equals({
          'push': {
            'recipient': {
              'transportType': 'fcm',
              'registrationToken': 'fcm-token-1',
            },
          },
        }),
      );
    });

    // UTS: rest/unit/RSH3a2a2/activate-existing-registration-register-callback-0
    test(
        'RSH3a2a2 - activate on an already-registered device with a custom '
        'registerCallback', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      final registeredDevices = <DeviceDetails>[];
      Future<DeviceRegistrationResult> registerCallback(
        DeviceDetails device,
      ) async {
        registeredDevices.add(device);
        return const DeviceRegistrationResult(
          deviceIdentityToken: 'ident-token-1',
        );
      }

      final client = _pushClient(mockStorage);
      await client.push.activate(registerCallback: registerCallback);

      // The validation went through the callback: no requests beyond the
      // seeding POST
      expect(capturedRequests.length, equals(1));
      expect(registeredDevices.length, equals(1));
      expect(registeredDevices[0].id, equals(deviceId));
    });

    // UTS: rest/unit/RSH3a2a1/activate-clientid-mismatch-0
    test(
        'RSH3a2a1 - activate fails with 61002 when the client identity '
        'conflicts with the registered device', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      await _activateInto(mockStorage, clientId: 'alice');

      final client = _pushClient(mockStorage, clientId: 'bob');
      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 61002),
        ),
      );

      // No validation request was made — only the seeding POST
      expect(capturedRequests.length, equals(1));
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'AfterRegistrationSyncFailed',
        'persisted activation state to become AfterRegistrationSyncFailed',
      );
    });

    // UTS: rest/unit/RSH3d1a/activate-when-registered-resolves-0
    test(
        'RSH3d1 - activate when already registered in the same session '
        'resolves without any request', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);

      await client.push.activate();

      // No additional request beyond the original registration POST
      expect(capturedRequests.length, equals(1));
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );
    });

    // UTS: rest/unit/RSH3e3c/sync-failure-then-reactivate-0
    test(
        'RSH3e3, RSH3f1 - a failed registration sync fails activate; '
        're-activating retries the sync', () async {
      var failPatch = true;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'PATCH' && failPatch) {
            request.respondWith(400, {
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
      await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // Fresh client over registered storage: activate syncs via PATCH,
      // which fails
      final client = _pushClient(mockStorage);
      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40199),
        ),
      );
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'AfterRegistrationSyncFailed',
        'persisted activation state to become AfterRegistrationSyncFailed',
      );

      // RSH3f1a — activate again; the machine re-runs the RSH3a2a validation
      failPatch = false;
      await client.push.activate();

      final patchRequests =
          capturedRequests.where((r) => r.method == 'PATCH').toList();
      expect(patchRequests.length, equals(2));
      expect(
        patchRequests[1].url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );
    });
  });

  group('RSH2b, RSH3d2, RSH3g, RSH3a1 - deactivation', () {
    // UTS: rest/unit/RSH2b/deactivate-full-flow-0
    test(
        'RSH3d2, RSH3g2 - deactivate deregisters the device and clears local '
        'state', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      await client.push.deactivate();
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );

      expect(capturedRequests.length, equals(2));
      final request = capturedRequests[1];
      expect(request.method, equals('DELETE'));
      expect(request.url.path, equals('/push/deviceRegistrations'));
      expect(request.url.queryParameters['deviceId'], equals(deviceId));

      // RSH3d2b + RSH6a — push device authentication
      expect(request.headers['X-Ably-DeviceToken'], equals('ident-token-1'));

      // RSH3g2a — the registered identity is cleared from storage, not just
      // memory
      final persisted = mockStorage.dump();
      expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
      expect(persisted.containsKey('ably.push.pushRecipient'), isFalse);
    });

    // UTS: rest/unit/RSH3d2a/deactivate-deregister-callback-0
    test(
        'RSH3d2a - deactivate with a custom deregisterCallback routes '
        'deregistration through the callback', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      final deregisteredIds = <String>[];
      Future<void> deregisterCallback(String deviceId) async {
        deregisteredIds.add(deviceId);
      }

      await client.push.deactivate(deregisterCallback: deregisterCallback);

      // Deregistration went through the callback: no DELETE
      expect(capturedRequests.length, equals(1)); // just the seeding POST
      expect(deregisteredIds, equals([deviceId]));
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3a1c/deactivate-not-activated-with-token-0
    test(
        'RSH3a1c - deactivate from NotActivated with a registered device '
        'still deregisters', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      mockStorage.seed({
        'ably.push.deviceId': 'seeded-device-1',
        'ably.push.deviceSecret': 'seeded-secret',
        'ably.push.deviceIdentityToken': '"seeded-ident-token"',
        'ably.push.activationState': 'NotActivated',
      });
      final client = _pushClient(mockStorage);

      await client.push.deactivate();

      expect(capturedRequests.length, equals(1));
      final request = capturedRequests[0];
      expect(request.method, equals('DELETE'));
      expect(
        request.url.queryParameters['deviceId'],
        equals('seeded-device-1'),
      );
      expect(
        request.headers['X-Ably-DeviceToken'],
        equals('seeded-ident-token'),
      );
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3a1d/deactivate-not-activated-0
    test(
        'RSH3a1d - deactivate from NotActivated with no registration '
        'resolves without any request', () async {
      final capturedRequests = _mockRegistrationServer();
      final mockStorage = MockPushStorage();
      final client = _pushClient(mockStorage);

      await client.push.deactivate();

      expect(capturedRequests, isEmpty);
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3d2c1/deregister-401-succeeds-0
    test('RSH3d2c1 - deregistration treats 401 as success', () async {
      _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'DELETE') {
            request.respondWith(401, {
              'error': {
                'message': 'unauthorized',
                'code': 40100,
                'statusCode': 401,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);

      await client.push.deactivate(); // resolves despite the 401

      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
      final persisted = mockStorage.dump();
      expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
    });

    // UTS: rest/unit/RSH3d2c1/deregister-40005-succeeds-1
    test('RSH3d2c1 - deregistration treats error code 40005 as success',
        () async {
      _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'DELETE') {
            request.respondWith(400, {
              'error': {
                'message': 'invalid credentials',
                'code': 40005,
                'statusCode': 400,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);

      await client.push.deactivate(); // resolves despite the 40005

      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3g3b/deregister-failure-rollback-0
    test(
        'RSH3d2c1, RSH3g3 - deregistration failure fails deactivate and '
        'rolls back to the previous state', () async {
      var failDelete = true;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'DELETE' && failDelete) {
            request.respondWith(400, {
              'error': {
                'message': 'deregistration rejected',
                'code': 40198,
                'statusCode': 400,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);

      await expectLater(
        Future.sync(() => client.push.deactivate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40198),
        ),
      );

      // RSH3g3b — still registered: the identity token survives the failed
      // deregistration
      expect(mockStorage.dump()['ably.push.deviceIdentityToken'], isNotNull);

      // Retry succeeds from the rolled-back state
      failDelete = false;
      await client.push.deactivate();
      // POST + failed DELETE + successful DELETE
      expect(capturedRequests.length, equals(3));
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3g1a/deactivate-while-deregistering-0
    test(
        'RSH3g1a - repeated deactivate while deregistration is in flight is '
        'idempotent', () async {
      PendingRequest? heldDelete;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'DELETE' && heldDelete == null) {
            heldDelete = request; // hold the deregistration open
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      final client = await _activateInto(mockStorage);

      final first = client.push.deactivate();
      await _waitFor(
        () => heldDelete != null,
        'the deregistration DELETE to be issued and held',
      );

      // RSH3g1a — self-transition, no second DELETE
      final second = client.push.deactivate();

      heldDelete!.respondWith(204, '');

      await first;
      await second;

      // Exactly one DELETE was issued
      final deleteRequests =
          capturedRequests.where((r) => r.method == 'DELETE').toList();
      expect(deleteRequests.length, equals(1));
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3f2a/deactivate-after-sync-failure-0
    test(
        'RSH3f2a - deactivate from AfterRegistrationSyncFailed deregisters '
        'normally', () async {
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'PATCH') {
            request.respondWith(400, {
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
      await _activateInto(mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // Drive into AfterRegistrationSyncFailed
      final client = _pushClient(mockStorage);
      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40199),
        ),
      );
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'AfterRegistrationSyncFailed',
        'persisted activation state to become AfterRegistrationSyncFailed',
      );

      await client.push.deactivate();

      final deleteRequests =
          capturedRequests.where((r) => r.method == 'DELETE').toList();
      expect(deleteRequests.length, equals(1));
      expect(
        deleteRequests[0].url.queryParameters['deviceId'],
        equals(deviceId),
      );
      await _waitFor(
        () => mockStorage.dump()['ably.push.activationState'] == 'NotActivated',
        'persisted activation state to become NotActivated',
      );
    });

    // UTS: rest/unit/RSH3g3b/deregister-failure-rollback-after-sync-failed-1
    test(
        'RSH3g3b - deregistration failure from AfterRegistrationSyncFailed '
        'rolls back to AfterRegistrationSyncFailed', () async {
      var failPatch = true;
      // Unlike failPatch, the DELETE keeps failing for the whole test (the
      // UTS spec never resets fail_delete).
      const failDelete = true;
      final capturedRequests = _mockRegistrationServer(
        overrides: (request) {
          if (request.method == 'PATCH' && failPatch) {
            request.respondWith(400, {
              'error': {
                'message': 'sync rejected',
                'code': 40199,
                'statusCode': 400,
              },
            });
            return true;
          }
          if (request.method == 'DELETE' && failDelete) {
            request.respondWith(400, {
              'error': {
                'message': 'deregistration rejected',
                'code': 40198,
                'statusCode': 400,
              },
            });
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      await _activateInto(mockStorage);

      // Drive into AfterRegistrationSyncFailed
      final client = _pushClient(mockStorage);
      await expectLater(
        Future.sync(() => client.push.activate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40199),
        ),
      );
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'AfterRegistrationSyncFailed',
        'persisted activation state to become AfterRegistrationSyncFailed',
      );

      await expectLater(
        Future.sync(() => client.push.deactivate()),
        throwsA(
          isA<AblyException>().having((e) => e.errorInfo?.code, 'code', 40198),
        ),
      );

      // Back in AfterRegistrationSyncFailed: activate re-syncs via PATCH
      // (RSH3f1a)
      failPatch = false;
      await client.push.activate();
      final patchRequests =
          capturedRequests.where((r) => r.method == 'PATCH').toList();
      expect(patchRequests.length, equals(2));
      await _waitFor(
        () =>
            mockStorage.dump()['ably.push.activationState'] ==
            'WaitingForNewPushDeviceDetails',
        'persisted activation state to become WaitingForNewPushDeviceDetails',
      );
    });
  });
}

/// The mock HTTP client installed by [_mockRegistrationServer] for the
/// current test; disposed in tearDown.
MockHttpClient? _mockHttp;

/// Builds and installs a [MockHttpClient] routing the push registration
/// endpoints, capturing every request into the returned list.
///
/// Individual tests override specific routes via the [overrides] handler,
/// which is consulted first and may hold requests without responding (return
/// true to indicate the request was handled or held).
List<PendingRequest> _mockRegistrationServer({
  bool Function(PendingRequest request)? overrides,
}) {
  final capturedRequests = <PendingRequest>[];
  _mockHttp?.dispose();
  _mockHttp = MockHttpClient(
    onRequest: (request) {
      capturedRequests.add(request);
      if (overrides != null && overrides(request)) {
        return; // the override handled (or held) the request
      }
      if (request.method == 'POST' &&
          request.url.path == '/push/deviceRegistrations') {
        request.respondWith(201, <String, dynamic>{
          ...request.jsonBody as Map<String, dynamic>,
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
      } else {
        request.respondWith(500, {
          'error': {'message': 'unexpected request', 'code': 50000},
        });
      }
    },
  );
  return capturedRequests;
}

/// Creates a REST client configured with a mock push platform over [storage]
/// and the mock HTTP client installed by [_mockRegistrationServer].
RestClient _pushClient(
  MockPushStorage storage, {
  String? clientId,
  PushDeviceToken? token,
  RequestTokenCallback? requestToken,
}) {
  return RestClient.forTesting(
    options: ClientOptions(
      key: 'appId.keyId:keySecret',
      clientId: clientId,
      pushPlatform: PushPlatformConfig(
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
      ),
    ),
    httpClient: _mockHttp,
  );
}

/// Runs a full activation so that [storage] holds a registered device
/// (deviceId, deviceSecret, deviceIdentityToken, pushRecipient) and the
/// persisted activation state is WaitingForNewPushDeviceDetails.
Future<RestClient> _activateInto(
  MockPushStorage storage, {
  String? clientId,
}) async {
  final client = _pushClient(storage, clientId: clientId);
  await client.push.activate();
  await _waitFor(
    () =>
        storage.dump()['ably.push.activationState'] ==
        'WaitingForNewPushDeviceDetails',
    'persisted activation state to become WaitingForNewPushDeviceDetails',
  );
  return client;
}

/// Polls [condition] on the event queue until it holds, failing the test
/// with [description] if [timeout] elapses first.
///
/// Fire-and-forget persistence: state-machine transitions may persist
/// asynchronously after the triggering operation resolves, so tests poll
/// rather than asserting storage contents immediately.
Future<void> _waitFor(
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits a fixed period, allowing any erroneous fire-and-forget activity
/// (late requests, stray persists) to surface before negative assertions.
Future<void> _settle(Duration duration) => Future<void>.delayed(duration);

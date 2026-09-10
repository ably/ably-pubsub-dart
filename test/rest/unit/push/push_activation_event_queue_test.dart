import 'dart:async';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_push_storage.dart';

/// Unit tests for the Activation State Machine's pending-event queue and its
/// event-handling discipline (RSH4, RSH5).
///
/// These tests use a mocked HTTP client and a mocked push platform, and are
/// black-box: they never construct events or inspect machine state directly.
/// Events are produced by driving the public API (`push.activate()`,
/// `push.deactivate()`), by the mocked `requestToken`, and by responding to
/// the mocked HTTP requests the machine issues. To pin the machine in an
/// intermediate state, tests hold a [PendingRequest] (captured in the
/// overrides handler without responding) or a pending `requestToken`
/// (a [Completer]), and release it later.
///
/// Spec: specification/uts/rest/unit/push/push_activation_event_queue.md
void main() {
  group('RSH4 - pending event queue', () {
    // UTS: rest/unit/RSH4/activate-queued-during-deregistration-0
    test(
        'RSH4 - activate queued during deregistration is consumed after it '
        'and re-registers a new device', () async {
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

      var tokenRequests = 0;
      final client = _pushClient(
        server,
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
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      final deactivation = client.push.deactivate();
      await _waitFor(() => heldDelete != null);

      // No transition defined for CalledActivate in WaitingForDeregistration:
      // it queues (RSH4)
      final activation = client.push.activate();
      await _processPendingEvents();
      expect(
        server.requests.length,
        equals(2),
        reason: 'activation POST + held DELETE; nothing new while queued',
      );

      heldDelete!.respondWith(204, '');

      await deactivation; // RSH3g2b
      // RSH3c2b — resolves after the dequeued event's full re-registration
      await activation;
      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      // RSH3a2d — the platform token was requested again for the
      // re-registration
      expect(tokenRequests, equals(2));

      // RSH3b3b — a second registration POST ran after the deregistration
      final postRequests =
          server.requests.where((r) => r.method == 'POST').toList();
      expect(postRequests.length, equals(2));

      // RSH3g2a + RSH3a2b — the old device was cleared, so a NEW deviceId
      // was registered
      final dynamic firstBody = postRequests[0].jsonBody;
      final dynamic secondBody = postRequests[1].jsonBody;
      final dynamic firstId = firstBody['id'];
      final dynamic secondId = secondBody['id'];
      expect(secondId, isNot(equals(firstId)));
      expect(mockStorage.dump()['ably.push.deviceId'], equals(secondId));

      server.httpClient.dispose();
    });

    // UTS: rest/unit/RSH4/second-activate-queued-during-activate-sync-1
    test(
        'RSH3e1, RSH4 - a second activate during an activate-triggered sync '
        'queues until the sync settles', () async {
      PendingRequest? heldPatch;
      final server = _mockRegistrationServer(
        overrides: (req) {
          if (req.method == 'PATCH' && heldPatch == null) {
            heldPatch = req; // hold the validation sync open
            return true;
          }
          return false;
        },
      );
      final mockStorage = MockPushStorage();
      await _activateInto(server, mockStorage);
      final deviceId = mockStorage.dump()['ably.push.deviceId']!;

      // A fresh client over registered storage: activate syncs the
      // registration via PATCH (RSH3a2a3)
      final client = _pushClient(server, mockStorage);
      final first = client.push.activate();
      // machine in WaitingForRegistrationSync via CalledActivate (RSH3a2a4)
      await _waitFor(() => heldPatch != null);

      // RSH3e1 carve-out applies: no transition defined, so the event
      // queues (RSH4)
      final second = client.push.activate();
      await _processPendingEvents();
      expect(
        server.requests.length,
        equals(2),
        reason: 'seeding POST + held PATCH; no additional request',
      );

      heldPatch!.respondWith(200, heldPatch!.jsonBody as Object);

      await first; // RSH3e2b
      // RSH3d1a — the dequeued CalledActivate resolves it from
      // WaitingForNewPushDeviceDetails
      await second;

      // Exactly one sync PATCH: the queued CalledActivate was consumed by
      // RSH3d1a, not by a second validation
      final patchRequests =
          server.requests.where((r) => r.method == 'PATCH').toList();
      expect(patchRequests.length, equals(1));
      expect(
        patchRequests[0].url.path,
        equals('/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}'),
      );

      await _waitForActivationState(
        mockStorage,
        'WaitingForNewPushDeviceDetails',
      );

      server.httpClient.dispose();
    });
  });

  group('RSH5 - atomic and sequential event handling', () {
    // UTS: rest/unit/RSH5/back-to-back-activate-deactivate-ordered-0
    test(
        'RSH5 - back-to-back activate then deactivate are handled strictly '
        'in order', () async {
      final server = _mockRegistrationServer();
      final mockStorage = MockPushStorage();

      final tokenDeferred = Completer<PushDeviceToken>();
      final client = _pushClient(
        server,
        mockStorage,
        requestToken: () => tokenDeferred.future,
      );

      // RSH3a2e — handled first. The spec defines no resolution for this
      // activate() in this scenario (RSH3b2 resolves only deactivate), so
      // it is not awaited; errors are ignored so a completion can never
      // surface as an unhandled Future error.
      client.push.activate().ignore();
      // RSH5 — handled only after CalledActivate has transitioned
      final deactivation = client.push.deactivate();

      await deactivation; // RSH3b2a — resolves with no error
      await _waitForActivationState(mockStorage, 'NotActivated');

      // The token arrives late: RSH3a3a — consumed in NotActivated, no
      // registration
      tokenDeferred.complete(
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-1'),
      );

      await _processPendingEvents();
      expect(server.requests, isEmpty);
      expect(
        mockStorage.dump()['ably.push.activationState'],
        equals('NotActivated'),
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

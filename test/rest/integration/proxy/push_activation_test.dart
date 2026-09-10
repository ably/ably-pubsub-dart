@Tags(['integration', 'proxy'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:math';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_push_storage.dart';
import '../../../helpers/poll_until.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

/// Push activation proxy integration tests.
///
/// The unit tier fully verifies the Activation State Machine with mocked
/// HTTP. These tests run the activation flows against the Ably sandbox
/// through the uts-proxy, injecting faults on the registration endpoints,
/// and add the assertion the unit tier cannot make: a direct admin client
/// (bypassing the proxy) inspects the server-side registration, proving
/// that a faulted request never reached the server.
///
/// The proxy serves plain HTTP (RSA1 prohibits Basic auth over an insecure
/// connection), so proxied clients authenticate via an authCallback whose
/// inner client talks directly to the sandbox.
///
/// Spec: uts/rest/integration/proxy/push_activation.md
void main() {
  late TestApp testApp;
  late String apiKey;

  setUpAll(() async {
    await ensureProxy();
    testApp = await TestApp.provision();
    apiKey = testApp.keys[0].keyStr;
  });

  tearDownAll(() async {
    try {
      await testApp.delete().timeout(const Duration(seconds: 30));
    } catch (_) {}
    stopProxy();
  });

  /// Token auth for proxied clients: the inner Rest client talks directly
  /// to the sandbox (never through the proxy), so token requests are never
  /// intercepted by fault-injection rules.
  Future<Object> Function(TokenParams params) tokenAuthCallback() {
    return (params) async {
      final innerRestClient = RestClient(
        options: ClientOptions(
          key: apiKey,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );
      try {
        return await innerRestClient.auth.requestToken();
      } finally {
        await innerRestClient.close();
      }
    };
  }

  /// The server-consumable recipient pre-seeded into storage. ablyUrl is
  /// the DIRECT sandbox URL — never the proxy (it is consumed server-side).
  Map<String, dynamic> ablyChannelRecipient(String channelName) => {
        'transportType': 'ablyChannel',
        'channel': channelName,
        'ablyKey': apiKey,
        'ablyUrl': 'https://${TestApp.sandboxRestHost}',
      };

  /// A push client routed through the proxy, over a fresh MockPushStorage
  /// pre-seeded with an ablyChannel recipient so that requestToken is never
  /// called (RSH3a2c). Each test creates its own storage and channel name.
  RestClient proxyPushClient(
    ProxySession session,
    MockPushStorage storage,
    String channelName,
  ) {
    storage.seed({
      'ably.push.pushRecipient': jsonEncode(ablyChannelRecipient(channelName)),
    });
    return RestClient(
      options: ClientOptions(
        authCallback: tokenAuthCallback(),
        endpoint: 'localhost', // REC2c2: auto-disables fallback hosts
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
        pushPlatform: PushPlatformConfig(
          platform: 'android',
          formFactor: 'phone',
          storage: storage,
          requestToken: () async => throw StateError(
            'requestToken must not be called — '
            'recipient pre-seeded (RSH3a2c)',
          ),
        ),
      ),
    );
  }

  /// An admin client that bypasses the proxy entirely — the source of
  /// server-side ground truth for these tests.
  RestClient directAdminClient() => RestClient(
        options: ClientOptions(
          key: apiKey,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );

  /// Polls the persisted activation state; persistence settles
  /// fire-and-forget after the triggering operation resolves.
  Future<void> waitForActivationState(
    MockPushStorage storage,
    String state,
  ) async {
    await pollUntil<bool>(
      () async =>
          storage.dump()['ably.push.activationState'] == state ? true : null,
      interval: const Duration(milliseconds: 100),
    );
  }

  /// Runs a fully real activation through the proxy (no rules firing) and
  /// returns the registered device id.
  Future<String> activateThroughProxy(
    RestClient client,
    MockPushStorage storage,
  ) async {
    await client.push.activate().timeout(const Duration(seconds: 15));
    await waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');
    return storage.dump()['ably.push.deviceId']!;
  }

  /// Filters the proxy event log for http_request events on the push
  /// device-registration endpoints, optionally by method.
  List<Map<String, dynamic>> registrationRequests(
    List<Map<String, dynamic>> log, {
    String? method,
  }) {
    return log.where((e) {
      final type = e['type'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      final m = e['method'] as String? ?? '';
      return type == 'http_request' &&
          path.contains('/push/deviceRegistrations') &&
          (method == null || m == method);
    }).toList();
  }

  /// Best-effort cleanup of a server-side registration a test left behind.
  void cleanupRegistration(RestClient admin, String deviceId) {
    addTearDown(() async {
      try {
        await admin.push.admin.deviceRegistrations
            .remove(deviceId)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // RSH3d2c1 — deregistration 401 is classified as Deregistered without the
  // DELETE reaching the server
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH3d2c1/deregister-401-classified-0
  test(
      'RSH3d2c1, RSH3g2a - deregistration 401 is classified as Deregistered '
      'without the DELETE reaching the server', () async {
    final session = await ProxySession.create();
    addTearDown(() async => session.close());

    final channelName = 'push-proxy-RSH3d2c1-401-${_randomId()}';
    final storage = MockPushStorage();
    final client = proxyPushClient(session, storage, channelName);
    addTearDown(client.close);
    final admin = directAdminClient();
    addTearDown(admin.close);

    // Real registration through the proxy
    final deviceId = await activateThroughProxy(client, storage);
    cleanupRegistration(admin, deviceId);

    // Server-side ground truth: the registration exists
    final registered = await admin.push.admin.deviceRegistrations
        .get(deviceId)
        .timeout(const Duration(seconds: 10));
    expect(registered.id, equals(deviceId));

    // Late fault injection: only the deregistration DELETE is faulted
    await session.addRules([
      {
        'match': {
          'type': 'http_request',
          'method': 'DELETE',
          'pathContains': '/push/deviceRegistrations',
        },
        'action': {
          'type': 'http_respond',
          'status': 401,
          'body': {
            'error': {
              'message': 'unauthorized',
              'code': 40100,
              'statusCode': 401,
            },
          },
        },
        'times': 1,
        'comment': 'RSH3d2c1: answer the deregistration DELETE with 401 '
            'without forwarding it',
      },
    ]);

    // Resolves despite the 401 — classified as Deregistered
    await client.push.deactivate().timeout(const Duration(seconds: 15));
    await waitForActivationState(storage, 'NotActivated');

    // RSH3g2a — local state cleared
    final persisted = storage.dump();
    expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
    expect(persisted.containsKey('ably.push.pushRecipient'), isFalse);

    // The DELETE never reached the server: the registration STILL exists.
    // The 401 → Deregistered classification is purely client-side.
    final stillRegistered = await admin.push.admin.deviceRegistrations
        .get(deviceId)
        .timeout(const Duration(seconds: 10));
    expect(stillRegistered.id, equals(deviceId));

    // The proxy log confirms exactly one DELETE was issued (and answered by
    // the rule)
    final log = await session.getLog();
    expect(registrationRequests(log, method: 'DELETE').length, equals(1));
  });

  // ---------------------------------------------------------------------------
  // RSH3d2c1 — deregistration error code 40005 is classified as Deregistered
  // without the DELETE reaching the server
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH3d2c1/deregister-40005-classified-1
  test(
      'RSH3d2c1, RSH3g2a - deregistration error code 40005 is classified as '
      'Deregistered without the DELETE reaching the server', () async {
    final session = await ProxySession.create();
    addTearDown(() async => session.close());

    final channelName = 'push-proxy-RSH3d2c1-40005-${_randomId()}';
    final storage = MockPushStorage();
    final client = proxyPushClient(session, storage, channelName);
    addTearDown(client.close);
    final admin = directAdminClient();
    addTearDown(admin.close);

    final deviceId = await activateThroughProxy(client, storage);
    cleanupRegistration(admin, deviceId);

    // Exercises the body-code (rather than status-code) branch of the
    // classification against a real HTTP response.
    await session.addRules([
      {
        'match': {
          'type': 'http_request',
          'method': 'DELETE',
          'pathContains': '/push/deviceRegistrations',
        },
        'action': {
          'type': 'http_respond',
          'status': 400,
          'body': {
            'error': {
              'message': 'invalid credentials',
              'code': 40005,
              'statusCode': 400,
            },
          },
        },
        'times': 1,
        'comment': 'RSH3d2c1: answer the deregistration DELETE with 400/40005 '
            'without forwarding it',
      },
    ]);

    // Resolves despite the 40005 — classified as Deregistered
    await client.push.deactivate().timeout(const Duration(seconds: 15));
    await waitForActivationState(storage, 'NotActivated');

    // RSH3g2a — local state cleared
    final persisted = storage.dump();
    expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
    expect(persisted.containsKey('ably.push.pushRecipient'), isFalse);

    // The DELETE never reached the server: the registration STILL exists
    final stillRegistered = await admin.push.admin.deviceRegistrations
        .get(deviceId)
        .timeout(const Duration(seconds: 10));
    expect(stillRegistered.id, equals(deviceId));
  });

  // ---------------------------------------------------------------------------
  // RSH3d2c1, RSH3g3b — deregistration failure fails deactivate and rolls
  // back; the retry deregisters end-to-end
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH3d2c1/deregister-failure-rollback-2
  test(
      'RSH3d2c1, RSH3g3a, RSH3g3b - deregistration failure fails deactivate '
      'and rolls back; the retry deregisters end-to-end', () async {
    final session = await ProxySession.create();
    addTearDown(() async => session.close());

    final channelName = 'push-proxy-RSH3g3b-rollback-${_randomId()}';
    final storage = MockPushStorage();
    final client = proxyPushClient(session, storage, channelName);
    addTearDown(client.close);
    final admin = directAdminClient();
    addTearDown(admin.close);

    final deviceId = await activateThroughProxy(client, storage);
    cleanupRegistration(admin, deviceId);

    await session.addRules([
      {
        'match': {
          'type': 'http_request',
          'method': 'DELETE',
          'pathContains': '/push/deviceRegistrations',
        },
        'action': {
          'type': 'http_respond',
          'status': 400,
          'body': {
            'error': {
              'message': 'deregistration rejected',
              'code': 40198,
              'statusCode': 400,
            },
          },
        },
        'times': 1,
        'comment': 'RSH3g3b: fail only the first deregistration DELETE with '
            'a non-retriable 400/40198',
      },
    ]);

    // RSH3g3a — deactivate returns with the error
    AblyException? error;
    try {
      await client.push.deactivate().timeout(const Duration(seconds: 15));
    } on AblyException catch (e) {
      error = e;
    }
    expect(error, isNotNull, reason: 'deactivate() must fail with 40198');
    expect(error!.code, equals(40198));

    // RSH3g3b — still registered locally: the identity token survives the
    // rollback
    expect(storage.dump()['ably.push.deviceIdentityToken'], isNotNull);

    // ... and server-side: the faulted DELETE was never forwarded
    final stillRegistered = await admin.push.admin.deviceRegistrations
        .get(deviceId)
        .timeout(const Duration(seconds: 10));
    expect(stillRegistered.id, equals(deviceId));

    // The rule is consumed — the retry deregisters end-to-end against the
    // real server
    await client.push.deactivate().timeout(const Duration(seconds: 15));
    await waitForActivationState(storage, 'NotActivated');

    final persisted = storage.dump();
    expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
    expect(persisted.containsKey('ably.push.pushRecipient'), isFalse);

    // Server-side registration is gone
    try {
      await admin.push.admin.deviceRegistrations
          .get(deviceId)
          .timeout(const Duration(seconds: 10));
      fail('Server-side registration must be gone after the retry');
    } on AblyException catch (e) {
      expect(e.statusCode, equals(404));
    }

    // Two DELETEs were issued: the faulted one and the real one
    final log = await session.getLog();
    expect(registrationRequests(log, method: 'DELETE').length, equals(2));
  });

  // ---------------------------------------------------------------------------
  // RSH3c3a — registration failure fails activate; the retry registers
  // against the real server
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH3c3a/registration-failure-then-retry-0
  test(
      'RSH3c3a, RSH3c3b - registration failure fails activate; the retry '
      'registers against the real server', () async {
    // Necessarily early fault injection — the fault under test is the
    // registration POST itself. endpoint "localhost" disables fallback
    // hosts (REC2c2), so the 500 produces exactly one POST attempt.
    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'method': 'POST',
            'pathContains': '/push/deviceRegistrations',
          },
          'action': {
            'type': 'http_respond',
            'status': 500,
            'body': {
              'error': {
                'message': 'internal error',
                'code': 50000,
                'statusCode': 500,
              },
            },
          },
          'times': 1,
          'comment': 'RSH3c3a: fail only the first registration POST with a '
              'synthetic 500/50000',
        },
      ],
    );
    addTearDown(() async => session.close());

    final channelName = 'push-proxy-RSH3c3a-retry-${_randomId()}';
    final storage = MockPushStorage();
    final client = proxyPushClient(session, storage, channelName);
    addTearDown(client.close);
    final admin = directAdminClient();
    addTearDown(admin.close);

    // RSH3c3a — activate returns with the error
    AblyException? error;
    try {
      await client.push.activate().timeout(const Duration(seconds: 15));
    } on AblyException catch (e) {
      error = e;
    }
    expect(error, isNotNull, reason: 'activate() must fail with 50000');
    expect(error!.code, equals(50000));
    await waitForActivationState(storage, 'NotActivated');

    // RSH3c3b — from NotActivated the retry runs the full flow against the
    // real server
    await client.push.activate().timeout(const Duration(seconds: 15));
    await waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');
    final deviceId = storage.dump()['ably.push.deviceId']!;
    cleanupRegistration(admin, deviceId);

    // Server-side ground truth: the retry's registration reached the real
    // server
    final registered = await admin.push.admin.deviceRegistrations
        .get(deviceId)
        .timeout(const Duration(seconds: 10));
    expect(registered.id, equals(deviceId));

    // Two POSTs were issued: the faulted one and the real one
    final log = await session.getLog();
    expect(registrationRequests(log, method: 'POST').length, equals(2));
  });

  // ---------------------------------------------------------------------------
  // RSH4 — deactivate issued during an in-flight registration is queued,
  // then deregisters after activation completes
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH4/deactivate-queued-behind-slow-registration-0
  test(
      'RSH4, RSH3c2b, RSH3d2 - deactivate issued during an in-flight '
      'registration is queued, then deregisters after activation completes',
      () async {
    // The proxy holds the registration POST for 2s (well under the default
    // httpRequestTimeout) so CalledDeactivate arrives in
    // WaitingForDeviceRegistration, where it has no defined transition and
    // queues per RSH4.
    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'method': 'POST',
            'pathContains': '/push/deviceRegistrations',
          },
          'action': {'type': 'http_delay', 'delayMs': 2000},
          'times': 1,
          'comment': 'RSH4: hold the registration POST for 2s so '
              'CalledDeactivate arrives in WaitingForDeviceRegistration',
        },
      ],
    );
    addTearDown(() async => session.close());

    final channelName = 'push-proxy-RSH4-queued-${_randomId()}';
    final storage = MockPushStorage();
    final client = proxyPushClient(session, storage, channelName);
    addTearDown(client.close);
    final admin = directAdminClient();
    addTearDown(admin.close);

    final resolutionOrder = <String>[];
    final activation =
        client.push.activate().then((_) => resolutionOrder.add('activate'));

    // Wait until the registration POST is in flight (visible in the proxy
    // event log while the http_delay holds it)
    await pollUntil<bool>(
      () async {
        final log = await session.getLog();
        return registrationRequests(log, method: 'POST').length == 1
            ? true
            : null;
      },
      interval: const Duration(milliseconds: 100),
    );

    // The id is generated and persisted (RSH3a2b/RSH8b) before the POST is
    // issued, so it is stable now. Capture it here: deregistration clears the
    // local DeviceDetails (RSH3g2a) and resets the identity so the
    // deregistered id is not reused.
    final deviceId = storage.dump()['ably.push.deviceId']!;

    // CalledDeactivate: no transition defined in WaitingForDeviceRegistration
    // → queued (RSH4)
    final deactivation =
        client.push.deactivate().then((_) => resolutionOrder.add('deactivate'));

    // Registration completes; activate resolves first (RSH3c2b), then the
    // dequeued CalledDeactivate deregisters (RSH3d2)
    await activation.timeout(const Duration(seconds: 15));
    await deactivation.timeout(const Duration(seconds: 15));

    // Activation resolved before deactivation
    expect(resolutionOrder, equals(['activate', 'deactivate']));

    await waitForActivationState(storage, 'NotActivated');
    final persisted = storage.dump();
    expect(persisted.containsKey('ably.push.deviceIdentityToken'), isFalse);
    expect(persisted.containsKey('ably.push.pushRecipient'), isFalse);

    // Server-side: the registration was created, then removed
    try {
      await admin.push.admin.deviceRegistrations
          .get(deviceId)
          .timeout(const Duration(seconds: 10));
      fail('Server-side registration must be gone after deactivation');
    } on AblyException catch (e) {
      expect(e.statusCode, equals(404));
    }

    // Wire sequence: the registration POST strictly precedes the
    // deregistration DELETE
    final log = await session.getLog();
    final regRequests = registrationRequests(log);
    expect(regRequests.length, equals(2));
    expect(regRequests[0]['method'], equals('POST'));
    expect(regRequests[1]['method'], equals('DELETE'));
  });

  // ---------------------------------------------------------------------------
  // RSH3e3d, RSH3f1 — a failed registration sync is reported via
  // updatedCallback; the next update syncs against the real server
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSH3e3d/sync-failure-recovery-0
  test(
    'RSH3e3d, RSH3e3b, RSH3f1 - a failed registration sync is reported via '
    'updatedCallback; the next update syncs against the real server',
    () async {
      final session = await ProxySession.create();
      addTearDown(() async => session.close());

      final channelName = 'push-proxy-RSH3e3d-sync-${_randomId()}';
      final storage = MockPushStorage();
      final client = proxyPushClient(session, storage, channelName);
      addTearDown(client.close);
      final admin = directAdminClient();
      addTearDown(admin.close);

      final updatedResults = <ErrorInfo?>[];
      await client.push
          .activate(updatedCallback: updatedResults.add)
          .timeout(const Duration(seconds: 15));
      await waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');
      final deviceId = storage.dump()['ably.push.deviceId']!;
      cleanupRegistration(admin, deviceId);

      // Late fault injection: fail only the first sync PATCH
      await session.addRules([
        {
          'match': {
            'type': 'http_request',
            'method': 'PATCH',
            'pathContains': '/push/deviceRegistrations',
          },
          'action': {
            'type': 'http_respond',
            'status': 400,
            'body': {
              'error': {
                'message': 'sync rejected',
                'code': 40199,
                'statusCode': 400,
              },
            },
          },
          'times': 1,
          'comment': 'RSH3e3d: fail only the first token-rotation sync PATCH '
              'with 400/40199',
        },
      ]);

      // updateToken resolves (the sync is fire-and-forget) ...
      await client.push
          .updateToken(
            const PushDeviceToken(
              transportType: 'fcm',
              token: 'proxy-fcm-token-2',
            ),
          )
          .timeout(const Duration(seconds: 10));

      // ... and the sync failure surfaces via the updatedCallback (RSH3e3d)
      await pollUntil<bool>(
        () async => updatedResults.length == 1 ? true : null,
        interval: const Duration(milliseconds: 100),
      );
      expect(updatedResults[0], isNotNull);
      expect(updatedResults[0]!.code, equals(40199));
      await waitForActivationState(storage, 'AfterRegistrationSyncFailed');

      // RSH3f1 — the next GotPushDeviceDetails re-runs the sync; the rule is
      // consumed, so the PATCH reaches the real server
      await client.push
          .updateToken(
            const PushDeviceToken(
              transportType: 'fcm',
              token: 'proxy-fcm-token-3',
            ),
          )
          .timeout(const Duration(seconds: 10));

      // Server-side ground truth: poll the direct admin get until the
      // recipient reflects the new token
      await pollUntil<bool>(
        () async {
          final device =
              await admin.push.admin.deviceRegistrations.get(deviceId);
          final recipient = device.push?.recipient;
          return recipient?['transportType'] == 'fcm' &&
                  recipient?['registrationToken'] == 'proxy-fcm-token-3'
              ? true
              : null;
        },
        timeout: const Duration(seconds: 15),
      );

      await waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');

      // Two PATCHes were issued: the faulted one and the real one
      final log = await session.getLog();
      expect(registrationRequests(log, method: 'PATCH').length, equals(2));
    },
    skip: 'Pending sandbox deploy of the ablyChannel PATCH fix — '
        'https://github.com/ably/realtime/pull/8591 — unskip once '
        'deployed',
  );
}

/// Unique per-run identifier for channel names and device registrations.
String _randomId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random();
  final suffix = String.fromCharCodes(
    Iterable.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
  );
  return '${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

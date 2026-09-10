@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ably/ably.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../helpers/mock_push_storage.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/wait_for_state.dart';

/// Push activation integration tests against the real Ably sandbox.
///
/// These drive the full activation state machine (RSH2, RSH3) against the
/// real service using the sandbox's test-only `ablyChannel` push recipient
/// (see the UTS spec Notes), so registration, identity-token grant, device
/// authentication, sync, deregistration and end-to-end push delivery are all
/// exercised for real.
///
/// Spec: uts/rest/integration/push_activation.md
void main() {
  late TestApp testApp;
  late String fullAccessKey;
  late String pushSubscribeKey;

  setUpAll(() async {
    testApp = await TestApp.provision();
    // keys[0] — full access; keys[1] — includes "pushenabled:*" with
    // "push-subscribe" (and "pushenabled:admin:*" with "push-admin"), per
    // ably-common test-app-setup.json. Matches the UTS Sandbox Setup.
    fullAccessKey = testApp.keys[0].keyStr;
    pushSubscribeKey = testApp.keys[1].keyStr;
  });

  tearDownAll(() async {
    // Best-effort: sandbox apps auto-expire.
    try {
      await testApp.delete().timeout(const Duration(seconds: 30));
    } catch (_) {}
  });

  /// Storage pre-seeded with an ablyChannel recipient (see UTS Notes). Per
  /// the spec this is a first-ever activation with known push details: only
  /// `ably.push.pushRecipient` needs seeding — no id/secret/identity token
  /// (a legitimate partial state per the RSH8a tolerance caveat; the id and
  /// deviceSecret are generated per RSH3a2b during activation).
  MockPushStorage seededStorage(String recipientChannel) {
    final storage = MockPushStorage();
    storage.seed({
      'ably.push.pushRecipient': jsonEncode({
        'transportType': 'ablyChannel',
        'channel': recipientChannel,
        'ablyKey': fullAccessKey,
        'ablyUrl': 'https://${TestApp.sandboxRestHost}',
      }),
    });
    return storage;
  }

  /// Per RSH3a2c the seeded recipient means requestToken is never consulted.
  RestClient pushClient(
    MockPushStorage storage, {
    String? key,
    String? platform,
  }) {
    return RestClient(
      options: ClientOptions(
        key: key ?? fullAccessKey,
        endpoint: 'nonprod:sandbox',
        useBinaryProtocol: false,
        pushPlatform: PushPlatformConfig(
          platform: platform ?? 'android',
          formFactor: 'phone',
          storage: storage,
          requestToken: () async => throw StateError(
            'requestToken must not be called: '
            'recipient is pre-seeded (RSH3a2c)',
          ),
        ),
      ),
    );
  }

  /// Separate client for server-side verification via the push admin API.
  RestClient adminClient() => RestClient(
        options: ClientOptions(
          key: fullAccessKey,
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

  /// One-off raw HTTP request against the sandbox, outside the SDK — used
  /// only for FINDING probes (observing full response bodies and header
  /// encoding acceptance), never to implement test behaviour.
  Future<http.Response> rawRequest(
    String method,
    String path, {
    required String keyStr,
    Map<String, String> extraHeaders = const {},
    Object? jsonBody,
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.https(TestApp.sandboxRestHost, path, queryParams);
    final request = http.Request(method, uri);
    request.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode(keyStr))}';
    request.headers.addAll(extraHeaders);
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }
    final streamed = await request.send().timeout(const Duration(seconds: 15));
    return http.Response.fromStream(streamed);
  }

  /// FINDING probe (RSH6a raw-token open question): tries a device-auth
  /// subscribeDevice POST with the raw deviceIdentityToken and with the
  /// base64-encoded value (as ably-java/ably-cocoa send it), and prints the
  /// server's response to each. Uses [pushSubscribeKey] so device
  /// authentication is load-bearing, mirroring the RSH8c test.
  Future<void> probeDeviceTokenEncodings({
    required String deviceId,
    required String identityToken,
    required RestClient admin,
  }) async {
    for (final variant in ['raw', 'base64']) {
      final channel = 'pushenabled:probe-rsh6a-$variant-${_randomId()}';
      final headerValue = variant == 'raw'
          ? identityToken
          : base64Encode(utf8.encode(identityToken));
      final resp = await rawRequest(
        'POST',
        '/push/channelSubscriptions',
        keyStr: pushSubscribeKey,
        extraHeaders: {'X-Ably-DeviceToken': headerValue},
        jsonBody: {'channel': channel, 'deviceId': deviceId},
      );
      // ignore: avoid_print
      print('FINDING(RSH6a): X-Ably-DeviceToken $variant value -> '
          '${resp.statusCode}: ${resp.body}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await admin.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forDevice(
            channel: channel,
            deviceId: deviceId,
          ),
        );
      }
    }
  }

  group(
      'RSH1a, RSH2a, RSH2b, RSH2f, RSH3a2a3, RSH3b3c, RSH6a, RSH8a, RSH8c - '
      'push activation against the sandbox', () {
    // -------------------------------------------------------------------------
    // RSH2a — activate registers the device with the real server
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH2a/activate-registers-device-0
    test(
        'RSH2a, RSH3a2c, RSH3b3b, RSH8c - activate registers the device with '
        'the real server', () async {
      final recipientChannel = 'push-recipient-RSH2a-${_randomId()}';
      final storage = seededStorage(recipientChannel);
      final client = pushClient(storage);
      addTearDown(client.close);

      await client.push.activate().timeout(const Duration(seconds: 15));

      final device = client.device;
      expect(device, isNotNull);
      expect(device!.id, isNotEmpty);
      expect(device.deviceIdentityToken, isNotNull);

      // Persistence settles fire-and-forget after activate resolves
      await waitForActivationState(storage, 'WaitingForNewPushDeviceDetails');

      // Server-side verification via a separate admin client
      final admin = adminClient();
      addTearDown(admin.close);
      addTearDown(() async {
        await admin.push.admin.deviceRegistrations.remove(device.id);
      });

      final registration = await admin.push.admin.deviceRegistrations
          .get(device.id)
          .timeout(const Duration(seconds: 10));
      expect(registration.id, equals(device.id));
      expect(registration.platform, equals('android'));
      expect(registration.formFactor, equals('phone'));
      expect(
        registration.push?.recipient['transportType'],
        equals('ablyChannel'),
      );
      expect(registration.push?.recipient['channel'], equals(recipientChannel));

      // FINDING probe (RSH8f): the SDK only extracts deviceIdentityToken and
      // clientId from the registration POST/PATCH responses, so observe the
      // full response bodies with a one-off raw registration outside the SDK.
      final probeId = 'probe-device-rsh8f-${_randomId()}';
      addTearDown(() async {
        await admin.push.admin.deviceRegistrations.remove(probeId);
      });
      final postResp = await rawRequest(
        'POST',
        '/push/deviceRegistrations',
        keyStr: fullAccessKey,
        jsonBody: {
          'id': probeId,
          'deviceSecret': base64Encode(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ),
          'platform': 'android',
          'formFactor': 'phone',
          'push': {
            'recipient': {
              'transportType': 'ablyChannel',
              'channel': 'push-recipient-probe-${_randomId()}',
              'ablyKey': fullAccessKey,
              'ablyUrl': 'https://${TestApp.sandboxRestHost}',
            },
          },
        },
      );
      // ignore: avoid_print
      print('FINDING(RSH8f): registration POST response '
          '${postResp.statusCode}: ${postResp.body}');
      final patchResp = await rawRequest(
        'PATCH',
        '/push/deviceRegistrations/$probeId',
        keyStr: fullAccessKey,
        jsonBody: {
          'push': {
            'recipient': {
              'transportType': 'ablyChannel',
              'channel': 'push-recipient-probe-${_randomId()}',
              'ablyKey': fullAccessKey,
              'ablyUrl': 'https://${TestApp.sandboxRestHost}',
            },
          },
        },
      );
      // ignore: avoid_print
      print('FINDING(RSH8f): registration sync PATCH response '
          '${patchResp.statusCode}: ${patchResp.body}');
    });

    // -------------------------------------------------------------------------
    // RSH8c, RSH6a — persisted deviceIdentityToken is usable by a fresh client
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH8c/identity-token-usable-0
    test(
        'RSH8c, RSH8a, RSH6a - persisted deviceIdentityToken is usable by a '
        'fresh client for device-authenticated subscribeDevice', () async {
      final recipientChannel = 'push-recipient-RSH8c-${_randomId()}';
      final storage = seededStorage(recipientChannel);

      // First app run: register the device
      final client1 = pushClient(storage);
      addTearDown(client1.close);
      await client1.push.activate().timeout(const Duration(seconds: 15));
      final deviceId = client1.device!.id;
      final identityToken = client1.device!.deviceIdentityToken!;

      final admin = adminClient();
      addTearDown(admin.close);
      addTearDown(() async {
        await admin.push.admin.deviceRegistrations.remove(deviceId);
      });

      // Second app run: fresh client over the same storage, restricted key.
      // No activate() call — the LocalDevice must hydrate from storage
      // (RSH8a). push_subscribe_key's "push-subscribe" capability authorises
      // subscribing only the authenticated device, so the operation succeeds
      // only if the server accepts the X-Ably-DeviceToken header.
      final client2 = pushClient(storage, key: pushSubscribeKey);
      addTearDown(client2.close);
      final channelName = 'pushenabled:test-RSH8c-${_randomId()}';
      final channel = client2.channels.get(channelName);

      addTearDown(() async {
        await admin.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forDevice(
            channel: channelName,
            deviceId: deviceId,
          ),
        );
      });

      try {
        // ably-dart sends the RAW deviceIdentityToken in X-Ably-DeviceToken
        // per RSH6a (ably-java/cocoa base64-encode it) — this is the
        // server-acceptance check for the raw value.
        await channel.push
            .subscribeDevice()
            .timeout(const Duration(seconds: 15));
        // ignore: avoid_print
        print('FINDING(RSH6a): subscribeDevice with RAW X-Ably-DeviceToken '
            'accepted by the sandbox');
      } on AblyException catch (e) {
        // ignore: avoid_print
        print('FINDING(RSH6a): subscribeDevice with RAW X-Ably-DeviceToken '
            'REJECTED: statusCode=${e.statusCode} code=${e.code} '
            'message=${e.message}');
        await probeDeviceTokenEncodings(
          deviceId: deviceId,
          identityToken: identityToken,
          admin: admin,
        );
        rethrow;
      }

      // Experimental cross-check regardless of outcome: raw vs base64 header
      // value acceptance (feeds the spec/implementation divergence question).
      await probeDeviceTokenEncodings(
        deviceId: deviceId,
        identityToken: identityToken,
        admin: admin,
      );

      expect(client2.device!.id, equals(deviceId));
      expect(client2.device!.deviceIdentityToken, isNotNull);

      // Server-side verification: the subscription exists
      final result = await admin.push.admin.channelSubscriptions.list({
        'channel': channelName,
        'deviceId': deviceId,
      }).timeout(const Duration(seconds: 10));
      expect(result.items.length, equals(1));
      expect(result.items[0].deviceId, equals(deviceId));
      expect(result.items[0].channel, equals(channelName));
    });

    // -------------------------------------------------------------------------
    // RSH2b — deactivate deregisters the device from the real server
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH2b/deactivate-deregisters-0
    test('RSH2b, RSH3g3a - deactivate deregisters the device from the server',
        () async {
      final recipientChannel = 'push-recipient-RSH2b-${_randomId()}';
      final storage = seededStorage(recipientChannel);
      final client = pushClient(storage);
      addTearDown(client.close);

      await client.push.activate().timeout(const Duration(seconds: 15));
      final deviceId = client.device!.id;
      final identityToken = client.device!.deviceIdentityToken!;

      // Confirm the registration exists before deactivating
      final admin = adminClient();
      addTearDown(admin.close);
      await admin.push.admin.deviceRegistrations
          .get(deviceId)
          .timeout(const Duration(seconds: 10));

      await client.push.deactivate().timeout(const Duration(seconds: 15));

      try {
        final still = await admin.push.admin.deviceRegistrations
            .get(deviceId)
            .timeout(const Duration(seconds: 10));
        // The deregistration DELETE carries the raw X-Ably-DeviceToken and
        // RSH3d2c1 treats a 401/40005 rejection as success — so a raw-token
        // rejection would be masked by deactivate() resolving. A registration
        // that still exists here is how that failure mode surfaces.
        // ignore: avoid_print
        print('FINDING(RSH2b/RSH6a): registration ${still.id} still exists '
            'after deactivate() resolved — the device-authenticated DELETE '
            'was likely rejected (RSH3d2c1 masks 401/40005 as success). '
            'Probing header encodings:');
        await probeDeviceTokenEncodings(
          deviceId: deviceId,
          identityToken: identityToken,
          admin: admin,
        );
        await admin.push.admin.deviceRegistrations.remove(deviceId);
        fail('Device registration still exists after deactivate()');
      } on AblyException catch (e) {
        expect(e.statusCode, equals(404));
      }
    });

    // -------------------------------------------------------------------------
    // RSH3a2a3 — reactivation over registered state syncs against the server
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH3a2a3/reactivation-validates-0
    test(
      'RSH3a2a3, RSH3a2a - reactivation over registered state performs the '
      'registration sync against the real server',
      () async {
        final recipientChannel = 'push-recipient-RSH3a2a3-${_randomId()}';
        final storage = seededStorage(recipientChannel);

        // First app run: register the device
        final client1 = pushClient(storage);
        addTearDown(client1.close);
        await client1.push.activate().timeout(const Duration(seconds: 15));
        final deviceId = client1.device!.id;

        final admin = adminClient();
        addTearDown(admin.close);
        addTearDown(() async {
          await admin.push.admin.deviceRegistrations.remove(deviceId);
        });

        // Second app run: fresh client over the same storage. The machine is
        // recovered into WaitingForNewPushDeviceDetails and activate()
        // validates the existing registration via the RSH3d3b PATCH rather
        // than re-registering.
        final client2 = pushClient(storage);
        addTearDown(client2.close);
        await client2.push.activate().timeout(const Duration(seconds: 15));

        // The sync (PATCH /push/deviceRegistrations/:deviceId) was accepted:
        // activate resolved and the same device is still registered
        // server-side.
        expect(client2.device!.id, equals(deviceId));
        expect(client2.device!.deviceIdentityToken, isNotNull);

        final registration = await admin.push.admin.deviceRegistrations
            .get(deviceId)
            .timeout(const Duration(seconds: 10));
        expect(registration.id, equals(deviceId));
        expect(
          registration.push?.recipient['transportType'],
          equals('ablyChannel'),
        );
        expect(
          registration.push?.recipient['channel'],
          equals(recipientChannel),
        );
      },
      skip: 'Pending sandbox deploy of the ablyChannel PATCH fix — '
          'https://github.com/ably/realtime/pull/8591 — unskip once '
          'deployed',
    );

    // -------------------------------------------------------------------------
    // RSH1a — direct publish to the activated device is received end to end
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH1a/direct-publish-received-0
    test(
        'RSH1a - direct publish to the activated device is received end to '
        'end via the ablyChannel recipient', () async {
      final recipientChannel = 'push-recipient-RSH1a-${_randomId()}';
      final storage = seededStorage(recipientChannel);
      final client = pushClient(storage);
      addTearDown(client.close);

      await client.push.activate().timeout(const Duration(seconds: 15));
      final deviceId = client.device!.id;

      final admin = adminClient();
      addTearDown(admin.close);
      addTearDown(() async {
        await admin.push.admin.deviceRegistrations.remove(deviceId);
      });

      // A realtime client subscribed to the recipient channel receives the
      // push, which the sandbox delivers as an __ably_push__ message with
      // the push payload JSON-encoded as a string in the message data.
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: fullAccessKey,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => realtime.close());

      realtime.connect();
      await waitForConnectionState(
        realtime.connection,
        ConnectionState.connected,
      );
      final rtChannel = realtime.channels.get(recipientChannel);
      await rtChannel.attach().timeout(const Duration(seconds: 10));
      final received = <Message>[];
      rtChannel.subscribe(received.add, name: '__ably_push__');

      final pushPayload = {
        'notification': {
          'title': 'Integration Test',
          'body': 'Push activation e2e',
        },
        'data': {'foo': 'bar'},
      };

      await admin.push.admin
          .publish({'deviceId': deviceId}, pushPayload).timeout(
        const Duration(seconds: 10),
      );

      final msg = await pollUntil<Message>(
        () async => received.isNotEmpty ? received[0] : null,
        interval: const Duration(milliseconds: 100),
        timeout: const Duration(seconds: 15),
      );

      expect(msg.name, equals('__ably_push__'));
      final data = msg.data;
      final receivedPayload = (data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : Map<String, dynamic>.from(data as Map));
      expect(
        (receivedPayload['notification'] as Map)['title'],
        equals('Integration Test'),
      );
      expect(
        (receivedPayload['notification'] as Map)['body'],
        equals('Push activation e2e'),
      );
      expect(receivedPayload['data'], equals({'foo': 'bar'}));
    });

    // -------------------------------------------------------------------------
    // RSH3b3c — registration rejected by the server fails activation
    // -------------------------------------------------------------------------
    // UTS: rest/integration/RSH3b3c/registration-failure-invalid-platform-0
    test(
        'RSH3b3c, RSH3b4a - registration rejected by the server fails '
        'activate() and the machine returns to NotActivated', () async {
      final recipientChannel = 'push-recipient-RSH3b3c-${_randomId()}';
      final storage = seededStorage(recipientChannel);
      final client = pushClient(storage, platform: 'not_a_real_platform');
      addTearDown(client.close);

      AblyException? error;
      try {
        await client.push.activate().timeout(const Duration(seconds: 15));
      } on AblyException catch (e) {
        error = e;
      }
      expect(
        error,
        isNotNull,
        reason: 'activate() with an invalid platform must fail',
      );
      // ignore: avoid_print
      print('FINDING(RSH3b3c): server rejected invalid platform with '
          'statusCode=${error!.statusCode} code=${error.code} '
          'message=${error.message}');
      expect(error.statusCode, isNotNull);
      expect(error.statusCode, inInclusiveRange(400, 499));

      // The machine settles back in NotActivated
      await waitForActivationState(storage, 'NotActivated');

      expect(client.device?.deviceIdentityToken, isNull);
    });

    // -------------------------------------------------------------------------
    // RSH2f — updateToken's fire-and-forget sync is accepted by the server
    // -------------------------------------------------------------------------
    // Validation-risk test (see UTS Notes): replaces the ablyChannel
    // recipient with a fabricated fcm one, so it uses its own storage and
    // device and runs last.
    // UTS: rest/integration/RSH2f/update-token-synced-0
    test(
      'RSH2f, RSH3d3b - updateToken applies the new fcm recipient and the '
      'fire-and-forget PATCH sync lands server-side',
      () async {
        // The device is registered with the seeded ablyChannel recipient and
        // updateToken replaces it with an fcm one (the sandbox accepts
        // fabricated fcm registrationTokens at both registration and update
        // time).
        final recipientChannel = 'push-recipient-RSH2f-${_randomId()}';
        final storage = seededStorage(recipientChannel);
        final client = pushClient(storage);
        addTearDown(client.close);

        await client.push.activate().timeout(const Duration(seconds: 15));
        final deviceId = client.device!.id;
        final newToken = 'fake-fcm-token-${_randomId()}';

        final admin = adminClient();
        addTearDown(admin.close);
        addTearDown(() async {
          await admin.push.admin.deviceRegistrations.remove(deviceId);
        });

        await client.push
            .updateToken(
              PushDeviceToken(transportType: 'fcm', token: newToken),
            )
            .timeout(const Duration(seconds: 15));

        // The sync is fire-and-forget: poll the admin API until the PATCH
        // lands server-side.
        final registration = await pollUntil<DeviceDetails>(
          () async {
            final reg =
                await admin.push.admin.deviceRegistrations.get(deviceId);
            return reg.push?.recipient['transportType'] == 'fcm' ? reg : null;
          },
          timeout: const Duration(seconds: 20),
        );

        expect(registration.id, equals(deviceId));
        expect(registration.push?.recipient['transportType'], equals('fcm'));
        expect(
          registration.push?.recipient['registrationToken'],
          equals(newToken),
        );
      },
      skip: 'Pending sandbox deploy of the ablyChannel PATCH fix — '
          'https://github.com/ably/realtime/pull/8591 — unskip once '
          'deployed',
    );
  });
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

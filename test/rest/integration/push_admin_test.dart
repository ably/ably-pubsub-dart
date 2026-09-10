@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/test_app_helper.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  RestClient buildClient() => RestClient(
        options: ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );

  // Helper: generate a unique device ID for each test.
  String uniqueDeviceId(String tag) =>
      'test-device-$tag-${DateTime.now().millisecondsSinceEpoch}';

  // Helper: create a minimal DeviceDetails with an APNs-style recipient.
  DeviceDetails makeDevice(
    String deviceId, {
    String? clientId,
    String token = 'fake-apns-token',
  }) {
    return DeviceDetails(
      id: deviceId,
      clientId: clientId,
      platform: 'ios',
      formFactor: 'phone',
      push: DevicePushDetails(
        recipient: {
          'transportType': 'apns',
          'deviceToken': token,
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RSH1a — push.admin.publish
  // ---------------------------------------------------------------------------
  group('RSH1a - push.admin.publish', () {
    // UTS: rest/integration/RSH1a/push-publish-clientid-0
    test('RSH1a - publish to valid clientId recipient does not throw',
        () async {
      final client = buildClient();
      addTearDown(client.close);

      await expectLater(
        client.push.admin.publish(
          {'clientId': 'test-client-${DateTime.now().millisecondsSinceEpoch}'},
          {
            'notification': {'title': 'Test', 'body': 'Hello'},
          },
        ),
        completes,
      );
    });

    // UTS: rest/integration/RSH1a/push-publish-invalid-recipient-1
    test('RSH1a invalid - empty recipient throws AblyException', () async {
      final client = buildClient();
      addTearDown(client.close);

      await expectLater(
        client.push.admin.publish(
          {},
          {
            'notification': {'title': 'Test', 'body': 'Hello'},
          },
        ),
        throwsA(isA<AblyException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1b3+RSH1b1 — save device registration and get by deviceId
  // ---------------------------------------------------------------------------
  group('RSH1b3+RSH1b1 - save and get device registration', () {
    // UTS: rest/integration/RSH1b3/save-and-get-device-0
    test('RSH1b3+RSH1b1 - save device, get by deviceId, verify fields',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('b3-get');
      final device = makeDevice(deviceId);

      DeviceDetails? saved;
      addTearDown(() async {
        await client.push.admin.deviceRegistrations.remove(deviceId);
      });

      saved = await client.push.admin.deviceRegistrations.save(device);
      expect(saved.id, equals(deviceId));
      expect(saved.platform, equals('ios'));
      expect(saved.formFactor, equals('phone'));

      final fetched = await client.push.admin.deviceRegistrations.get(deviceId);
      expect(fetched.id, equals(deviceId));
      expect(fetched.platform, equals('ios'));
    });

    // UTS: rest/integration/RSH1b3/update-device-registration-1
    test(
        'RSH1b3 update - save device twice with different token, verify via get',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('b3-update');

      addTearDown(() async {
        await client.push.admin.deviceRegistrations.remove(deviceId);
      });

      // Save initial registration
      await client.push.admin.deviceRegistrations
          .save(makeDevice(deviceId, token: 'token-v1'));

      // Save again with updated token
      await client.push.admin.deviceRegistrations
          .save(makeDevice(deviceId, token: 'token-v2'));

      // Verify the update was persisted
      final fetched = await client.push.admin.deviceRegistrations.get(deviceId);
      expect(fetched.id, equals(deviceId));
      // The updated recipient should reflect the new token
      expect(
        fetched.push?.recipient['deviceToken'],
        equals('token-v2'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1b1 — get non-existent device returns 404
  // ---------------------------------------------------------------------------
  group('RSH1b1 - get non-existent device', () {
    // UTS: rest/integration/RSH1b1/get-unknown-device-error-0
    test('RSH1b1 not found - get nonexistent deviceId throws with 404',
        () async {
      final client = buildClient();
      addTearDown(client.close);

      try {
        await client.push.admin.deviceRegistrations
            .get('nonexistent-device-${DateTime.now().millisecondsSinceEpoch}');
        fail('Expected AblyException to be thrown');
      } on AblyException catch (e) {
        expect(e.statusCode, equals(404));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1b2 — list device registrations
  // ---------------------------------------------------------------------------
  group('RSH1b2 - list device registrations', () {
    // UTS: rest/integration/RSH1b2/list-devices-filtered-0
    test('RSH1b2 list - save device, list by deviceId, verify 1 result',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('b2-list');

      addTearDown(() async {
        await client.push.admin.deviceRegistrations.remove(deviceId);
      });

      await client.push.admin.deviceRegistrations.save(makeDevice(deviceId));

      final result = await client.push.admin.deviceRegistrations
          .list({'deviceId': deviceId});
      expect(result.items.length, equals(1));
      expect(result.items.first.id, equals(deviceId));
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1b4 — remove device registration
  // ---------------------------------------------------------------------------
  group('RSH1b4 - remove device registration', () {
    // UTS: rest/integration/RSH1b4/remove-device-0
    test('RSH1b4 remove - save device, remove, subsequent get returns 404',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('b4-remove');

      await client.push.admin.deviceRegistrations.save(makeDevice(deviceId));
      await client.push.admin.deviceRegistrations.remove(deviceId);

      try {
        await client.push.admin.deviceRegistrations.get(deviceId);
        fail('Expected AblyException to be thrown after removal');
      } on AblyException catch (e) {
        expect(e.statusCode, equals(404));
      }
    });

    // UTS: rest/integration/RSH1b4/remove-nonexistent-device-1
    test('RSH1b4 remove nonexistent - does not throw', () async {
      final client = buildClient();
      addTearDown(client.close);

      await expectLater(
        client.push.admin.deviceRegistrations
            .remove('nonexistent-${DateTime.now().millisecondsSinceEpoch}'),
        completes,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1b5 — removeWhere device registrations
  // ---------------------------------------------------------------------------
  group('RSH1b5 - removeWhere device registrations', () {
    test(
        'RSH1b5 removeWhere - save 2 devices with same clientId, removeWhere, list returns 0',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final clientId = 'shared-client-${DateTime.now().millisecondsSinceEpoch}';
      final deviceId1 = uniqueDeviceId('b5-a');
      final deviceId2 = uniqueDeviceId('b5-b');

      await client.push.admin.deviceRegistrations
          .save(makeDevice(deviceId1, clientId: clientId));
      await client.push.admin.deviceRegistrations
          .save(makeDevice(deviceId2, clientId: clientId));

      await client.push.admin.deviceRegistrations
          .removeWhere({'clientId': clientId});

      final result = await client.push.admin.deviceRegistrations
          .list({'clientId': clientId});
      expect(result.items, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1c3+RSH1c1 — save and list channel subscriptions (device-based)
  // ---------------------------------------------------------------------------
  group('RSH1c3+RSH1c1 - save and list subscriptions', () {
    test(
        'RSH1c3+RSH1c1 - save device, save subscription for channel, list finds it',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('c3-device');
      final channelName =
          'pushenabled:test-sub-${DateTime.now().millisecondsSinceEpoch}';

      addTearDown(() async {
        await client.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forDevice(
            channel: channelName,
            deviceId: deviceId,
          ),
        );
        await client.push.admin.deviceRegistrations.remove(deviceId);
      });

      // Register device first
      await client.push.admin.deviceRegistrations.save(makeDevice(deviceId));

      // Save subscription
      final saved = await client.push.admin.channelSubscriptions.save(
        PushChannelSubscription.forDevice(
          channel: channelName,
          deviceId: deviceId,
        ),
      );
      expect(saved.channel, equals(channelName));
      expect(saved.deviceId, equals(deviceId));

      // List subscriptions for the channel
      final result = await client.push.admin.channelSubscriptions
          .list({'channel': channelName});
      expect(result.items, isNotEmpty);
      expect(
        result.items.any((s) => s.deviceId == deviceId),
        isTrue,
      );
    });

    // UTS: rest/integration/RSH1c3/save-and-list-subscriptions-0
    test('RSH1c3 clientId subscription - save clientId subscription, verify',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final clientId = 'push-client-${DateTime.now().millisecondsSinceEpoch}';
      final channelName =
          'pushenabled:test-clientsub-${DateTime.now().millisecondsSinceEpoch}';

      addTearDown(() async {
        await client.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forClientId(
            channel: channelName,
            clientId: clientId,
          ),
        );
      });

      final saved = await client.push.admin.channelSubscriptions.save(
        PushChannelSubscription.forClientId(
          channel: channelName,
          clientId: clientId,
        ),
      );
      expect(saved.channel, equals(channelName));
      expect(saved.clientId, equals(clientId));
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1c2 — listChannels
  // ---------------------------------------------------------------------------
  group('RSH1c2 - listChannels', () {
    // UTS: rest/integration/RSH1c2/list-channels-with-subscriptions-0
    test(
        'RSH1c2 listChannels - save clientId subscription, listChannels returns channel',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final clientId = 'lc-client-${DateTime.now().millisecondsSinceEpoch}';
      final channelName =
          'pushenabled:listchannels-${DateTime.now().millisecondsSinceEpoch}';

      addTearDown(() async {
        await client.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forClientId(
            channel: channelName,
            clientId: clientId,
          ),
        );
      });

      await client.push.admin.channelSubscriptions.save(
        PushChannelSubscription.forClientId(
          channel: channelName,
          clientId: clientId,
        ),
      );

      final result = await client.push.admin.channelSubscriptions
          .listChannels({'clientId': clientId});
      expect(result.items, contains(channelName));
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1c4 — remove channel subscription
  // ---------------------------------------------------------------------------
  group('RSH1c4 - remove subscription', () {
    // UTS: rest/integration/RSH1c4/remove-channel-subscription-0
    test('RSH1c4 remove sub - save sub, remove it, list returns 0', () async {
      final client = buildClient();
      addTearDown(client.close);
      final deviceId = uniqueDeviceId('c4-remove');
      final channelName =
          'pushenabled:c4-remove-${DateTime.now().millisecondsSinceEpoch}';

      addTearDown(() async {
        await client.push.admin.deviceRegistrations.remove(deviceId);
      });

      await client.push.admin.deviceRegistrations.save(makeDevice(deviceId));

      final sub = PushChannelSubscription.forDevice(
        channel: channelName,
        deviceId: deviceId,
      );
      await client.push.admin.channelSubscriptions.save(sub);

      // Verify it was saved
      final before = await client.push.admin.channelSubscriptions
          .list({'channel': channelName});
      expect(before.items, isNotEmpty);

      // Remove the subscription
      await client.push.admin.channelSubscriptions.remove(sub);

      final after = await client.push.admin.channelSubscriptions
          .list({'channel': channelName});
      expect(after.items, isEmpty);
    });

    // UTS: rest/integration/RSH1c4/remove-nonexistent-subscription-1
    test('RSH1c4 remove nonexistent sub - does not throw', () async {
      final client = buildClient();
      addTearDown(client.close);

      await expectLater(
        client.push.admin.channelSubscriptions.remove(
          PushChannelSubscription.forClientId(
            channel:
                'pushenabled:nonexistent-${DateTime.now().millisecondsSinceEpoch}',
            clientId: 'nonexistent-client',
          ),
        ),
        completes,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSH1c5 — removeWhere subscriptions
  // ---------------------------------------------------------------------------
  group('RSH1c5 - removeWhere subscriptions', () {
    test(
        'RSH1c5 removeWhere - 2 subs for same clientId on different channels, removeWhere, list returns 0',
        () async {
      final client = buildClient();
      addTearDown(client.close);
      final clientId = 'c5-client-${DateTime.now().millisecondsSinceEpoch}';
      final channel1 =
          'pushenabled:c5-ch1-${DateTime.now().millisecondsSinceEpoch}';
      final channel2 =
          'pushenabled:c5-ch2-${DateTime.now().millisecondsSinceEpoch}';

      await client.push.admin.channelSubscriptions.save(
        PushChannelSubscription.forClientId(
          channel: channel1,
          clientId: clientId,
        ),
      );
      await client.push.admin.channelSubscriptions.save(
        PushChannelSubscription.forClientId(
          channel: channel2,
          clientId: clientId,
        ),
      );

      // RemoveWhere by clientId
      await client.push.admin.channelSubscriptions
          .removeWhere({'clientId': clientId});

      // Both subscriptions should be removed
      final result1 = await client.push.admin.channelSubscriptions
          .list({'channel': channel1});
      final result2 = await client.push.admin.channelSubscriptions
          .list({'channel': channel2});

      expect(result1.items, isEmpty);
      expect(result2.items, isEmpty);
    });
  });
}

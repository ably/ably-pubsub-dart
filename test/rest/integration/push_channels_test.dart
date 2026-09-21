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

  RestClient buildAdminClient() => RestClient(
        options: ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );

  // Helper: generate a unique device ID for each test.
  String uniqueDeviceId(String tag) =>
      'test-device-$tag-${DateTime.now().millisecondsSinceEpoch}';

  // ---------------------------------------------------------------------------
  // RSH7a+RSH7c — subscribeDevice / unsubscribeDevice
  // ---------------------------------------------------------------------------
  group('RSH7a+RSH7c - subscribeDevice / unsubscribeDevice', () {
    test(
      'RSH7a+RSH7c - register device, subscribe via channel.push.subscribeDevice, '
      'verify via admin list, unsubscribe, verify removed',
      () {},
      skip: 'Requires real deviceIdentityToken from push activation flow '
          '(RSH2), not available in sandbox',
    );
  });

  // ---------------------------------------------------------------------------
  // RSH7b+RSH7d — subscribeClient / unsubscribeClient
  // ---------------------------------------------------------------------------
  group('RSH7b+RSH7d - subscribeClient / unsubscribeClient', () {
    test(
        'RSH7b+RSH7d - set device with clientId, subscribe via channel.push.subscribeClient, '
        'verify via admin list, unsubscribe, verify removed', () async {
      final adminClient = buildAdminClient();
      addTearDown(adminClient.close);

      final deviceId = uniqueDeviceId('rsh7b');
      final clientId =
          'push-client-rsh7b-${DateTime.now().millisecondsSinceEpoch}';
      final channelName =
          'pushenabled:rsh7b-${DateTime.now().millisecondsSinceEpoch}';

      // Build a client that simulates the local device with a clientId
      final deviceClient = RestClient(
        options: ClientOptions(
          key: testApp.keys[1].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );
      addTearDown(deviceClient.close);

      // Set the local device on the client, including a clientId
      deviceClient.device = LocalDevice(
        id: deviceId,
        clientId: clientId,
        deviceIdentityToken: 'fake-identity-token-$deviceId',
        platform: 'ios',
        formFactor: 'phone',
        push: DevicePushDetails(
          recipient: {
            'transportType': 'apns',
            'deviceToken': 'fake-apns-token-$deviceId',
          },
        ),
      );

      final channel = deviceClient.channels.get(channelName);

      // RSH7b: Subscribe client
      await channel.push.subscribeClient();

      // Verify via admin list using clientId
      final subs = await adminClient.push.admin.channelSubscriptions
          .list({'channel': channelName, 'clientId': clientId});
      expect(subs.items, isNotEmpty);
      expect(
        subs.items.any((s) => s.clientId == clientId),
        isTrue,
      );

      // RSH7d: Unsubscribe client
      await channel.push.unsubscribeClient();

      // Verify removed
      final subsAfter = await adminClient.push.admin.channelSubscriptions
          .list({'channel': channelName, 'clientId': clientId});
      expect(subsAfter.items, isEmpty);
    });
  });
}

@Tags(['integration', 'proxy'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/jwt_helper.dart';
import '../../../helpers/poll_until.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    await ensureProxy();
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
    stopProxy();
  });

  group('Publish and History Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTL6 - End-to-end publish and history through proxy
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL6/publish-history-through-proxy-0
    test('RTL6 - End-to-end publish and history through proxy', () async {
      final apiKey = testApp.keys[0].keyStr;
      final channelName =
          'rtl6-e2e-publish-${DateTime.now().millisecondsSinceEpoch}';

      // No proxy rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      // Create Realtime client
      final realtimeClient = RealtimeClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await realtimeClient.close());

      await realtimeClient.connect();

      final channel = realtimeClient.channels.get(channelName);

      // Attach and publish
      await channel.attach();
      await channel.publish(name: 'test-msg', data: 'hello world');

      // Allow message to propagate
      await Future<void>.delayed(const Duration(seconds: 1));

      // Poll until history contains the published message. History is served
      // over HTTP through the same proxy.
      final result = await pollUntil(
        () async {
          final history = await channel.history();
          if (history.items.isNotEmpty) return history;
          return null;
        },
        timeout: const Duration(seconds: 15),
      );

      // Assert: history contains the published message
      expect(result.items, isNotEmpty);
      final message = result.items.first;
      expect(message.name, equals('test-msg'));
      expect(message.data, equals('hello world'));
    });
  });
}

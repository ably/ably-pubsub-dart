@Tags(['integration'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../helpers/poll_until.dart';
import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/test_channel_name.dart';
import '../../helpers/wait_for_state.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Realtime Channel History Integration Tests', (protocol) {
    // -------------------------------------------------------------------------
    // RTL10d - History contains messages published by another client
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RTL10d/history-cross-client-0
    test('RTL10d - History contains messages published by another client',
        () async {
      // Create two Realtime clients
      final publisher = createClient(
        ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: protocol == 'msgpack',
          autoConnect: false,
        ),
      );
      addTearDown(() async => await publisher.close());

      final subscriber = createClient(
        ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: protocol == 'msgpack',
          autoConnect: false,
        ),
      );
      addTearDown(() async => await subscriber.close());

      // Connect both clients
      publisher.connect();
      subscriber.connect();
      await Future.wait([
        waitForConnectionState(publisher.connection, ConnectionState.connected),
        waitForConnectionState(
          subscriber.connection,
          ConnectionState.connected,
        ),
      ]);

      // Get channels on both clients with the same name
      final channelName = testChannelName('rtl10d-history');
      final pubChannel = publisher.channels.get(channelName);
      final subChannel = subscriber.channels.get(channelName);

      // Attach both channels
      await pubChannel.attach();
      await subChannel.attach();

      // Publisher publishes 3 messages
      await pubChannel.publish(name: 'event1', data: 'data1');
      await pubChannel.publish(name: 'event2', data: 'data2');
      await pubChannel.publish(name: 'event3', data: 'data3');

      // Use pollUntil on subscriber's channel.history() until 3 items
      final historyPage = await pollUntil<PaginatedResult<Message>>(
        () async {
          final result = await subChannel.history();
          if (result.items.length >= 3) return result;
          return null;
        },
        timeout: const Duration(seconds: 15),
      );

      // Assert: 3 items
      expect(historyPage.items, hasLength(3));

      // Assert: newest first order (default direction is backwards)
      expect(historyPage.items[0].name, equals('event3'));
      expect(historyPage.items[0].data, equals('data3'));
      expect(historyPage.items[1].name, equals('event2'));
      expect(historyPage.items[1].data, equals('data2'));
      expect(historyPage.items[2].name, equals('event1'));
      expect(historyPage.items[2].data, equals('data1'));
    });
  });
}

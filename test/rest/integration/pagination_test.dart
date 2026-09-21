@Tags(['integration'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../helpers/test_app_helper.dart';
import '../../helpers/poll_until.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  // Helper: create a REST client with sandbox + JSON protocol.
  RestClient makeClient() => RestClient(
        options: ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );

  // Helper: publish [count] messages to [channel] and poll until the history
  // count equals [count] (or at least [minCount] when specified).
  Future<void> publishAndWait(
    RestChannel channel,
    int count, {
    Duration timeout = const Duration(seconds: 20),
    String namePrefix = 'msg',
  }) async {
    for (var i = 0; i < count; i++) {
      await channel.publish(name: '$namePrefix-$i', data: 'data-$i');
    }
    await pollUntil(
      () async {
        final page = await channel.history(
          const RestHistoryParams(limit: 1000),
        );
        return page.items.length >= count ? true : null;
      },
      timeout: timeout,
    );
  }

  group('TG1, TG2 - First page has correct count and hasNext', () {
    test(
        'TG1, TG2 - Publish 15 messages, limit 5 returns 5 items with hasNext true',
        () async {
      final client = makeClient();
      final channelName =
          'persisted:pagination-tg1-${DateTime.now().millisecondsSinceEpoch}';
      final channel = client.channels.get(channelName);

      await publishAndWait(channel, 15);

      final page = await channel.history(const RestHistoryParams(limit: 5));

      expect(page.items.length, equals(5));
      expect(page.hasNext(), isTrue);
      expect(page.isLast(), isFalse);
    });
  });

  group('TG3 - Pagination traversal with no duplicate IDs', () {
    test(
        'TG3 - Publish 12 messages, paginate limit 5, verify no duplicates across 3 pages',
        () async {
      final client = makeClient();
      final channelName =
          'persisted:pagination-tg3-${DateTime.now().millisecondsSinceEpoch}';
      final channel = client.channels.get(channelName);

      await publishAndWait(channel, 12);

      final page1 = await channel.history(const RestHistoryParams(limit: 5));
      expect(page1.items.length, equals(5));
      expect(page1.hasNext(), isTrue);

      final page2 = await page1.next();
      expect(page2, isNotNull);
      expect(page2!.items.length, equals(5));
      expect(page2.hasNext(), isTrue);

      final page3 = await page2.next();
      expect(page3, isNotNull);
      expect(page3!.items.length, equals(2));
      expect(page3.hasNext(), isFalse);

      // Verify no duplicate message IDs across pages.
      final allIds = [
        ...page1.items.map((m) => m.id),
        ...page2.items.map((m) => m.id),
        ...page3.items.map((m) => m.id),
      ];
      final uniqueIds = allIds.toSet();
      expect(uniqueIds.length, equals(12));
    });
  });

  group('TG4 - first() returns same items as original first page', () {
    test(
        'TG4 - Publish 10 messages, navigate to page2, call first() and verify matches page1',
        () async {
      final client = makeClient();
      final channelName =
          'persisted:pagination-tg4-${DateTime.now().millisecondsSinceEpoch}';
      final channel = client.channels.get(channelName);

      await publishAndWait(channel, 10);

      final page1 = await channel.history(const RestHistoryParams(limit: 3));
      expect(page1.items.length, equals(3));

      final page2 = await page1.next();
      expect(page2, isNotNull);

      final firstAgain = await page2!.first();
      expect(firstAgain.items.length, equals(page1.items.length));

      // IDs and names must match.
      final firstIds = page1.items.map((m) => m.id).toList();
      final againIds = firstAgain.items.map((m) => m.id).toList();
      expect(againIds, equals(firstIds));
    });
  });

  group('TG5 - Iterate all pages and collect all messages', () {
    test(
        'TG5 - Publish 25 messages, iterate with limit 7, collect all 25 items',
        () async {
      final client = makeClient();
      final channelName =
          'persisted:pagination-tg5-${DateTime.now().millisecondsSinceEpoch}';
      final channel = client.channels.get(channelName);

      const messageCount = 25;
      await publishAndWait(
        channel,
        messageCount,
        timeout: const Duration(seconds: 30),
      );

      final allMessages = <Message>[];
      PaginatedResult<Message>? current =
          await channel.history(const RestHistoryParams(limit: 7));

      while (current != null) {
        allMessages.addAll(current.items);
        current = current.hasNext() ? await current.next() : null;
      }

      expect(allMessages.length, equals(messageCount));

      // Verify all published event names are present.
      final names = allMessages.map((m) => m.name).toSet();
      for (var i = 0; i < messageCount; i++) {
        expect(names, contains('msg-$i'));
      }
    });
  });

  group('TG - next() on last page returns null', () {
    test(
        'TG - Publish 3 messages, get with limit 10, hasNext false, next() returns null',
        () async {
      final client = makeClient();
      final channelName =
          'persisted:pagination-last-${DateTime.now().millisecondsSinceEpoch}';
      final channel = client.channels.get(channelName);

      await publishAndWait(channel, 3);

      final page = await channel.history(const RestHistoryParams(limit: 10));

      expect(page.items.length, equals(3));
      expect(page.hasNext(), isFalse);
      expect(page.isLast(), isTrue);

      final nextPage = await page.next();
      expect(nextPage, isNull);
    });
  });
}

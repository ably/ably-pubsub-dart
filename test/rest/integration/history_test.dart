@Tags(['integration'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/test_channel_name.dart';
import '../../helpers/poll_until.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Rest Channel History', (protocol) {
    late RestClient client;

    setUpAll(() {
      client = RestClient(
        options: ClientOptions(
          key: testApp.keys[0].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: protocol == 'msgpack',
        ),
      );
    });

    tearDownAll(() async {
      await client.close();
    });

    // ---------------------------------------------------------------------------
    // RSL2a — History returns published messages
    // ---------------------------------------------------------------------------
    group('RSL2a - History returns published messages', () {
      test(
          'RSL2a - publish 3 messages then poll history until 3 returned, '
          'default order is newest first', () async {
        final channelName = testChannelName('rsl2a-order');
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'evt', data: 'first');
        await channel.publish(name: 'evt', data: 'second');
        await channel.publish(name: 'evt', data: 'third');

        // Poll until all 3 messages are visible in history.
        final page = await pollUntil(
          () async {
            final p = await channel.history();
            if (p.items.length >= 3) return p;
            return null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(page.items.length, equals(3));

        // Default direction is backwards (newest first).
        final dataValues = page.items.map((m) => m.data as String).toList();
        expect(
          dataValues,
          equals(['third', 'second', 'first']),
          reason: 'Default history order should be newest first (backwards)',
        );
      });
    });

    // ---------------------------------------------------------------------------
    // RSL2b1 — Direction forwards
    // ---------------------------------------------------------------------------
    group('RSL2b1 - Direction forwards', () {
      test('RSL2b1 - history with direction forwards returns oldest first',
          () async {
        final channelName = testChannelName('rsl2b1-fwd');
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'evt', data: 'alpha');
        await channel.publish(name: 'evt', data: 'beta');
        await channel.publish(name: 'evt', data: 'gamma');

        // Poll until at least 3 messages appear.
        await pollUntil(
          () async {
            final p = await channel.history();
            if (p.items.length >= 3) return p;
            return null;
          },
          timeout: const Duration(seconds: 15),
        );

        // Now fetch with direction forwards.
        final page = await channel.history(
          const RestHistoryParams(direction: HistoryDirection.forwards),
        );

        expect(page.items.length, equals(3));
        final dataValues = page.items.map((m) => m.data as String).toList();
        expect(
          dataValues,
          equals(['alpha', 'beta', 'gamma']),
          reason: 'Forwards history order should be oldest first',
        );
      });
    });

    // ---------------------------------------------------------------------------
    // RSL2b2 — Limit
    // ---------------------------------------------------------------------------
    group('RSL2b2 - Limit', () {
      test('RSL2b2 - publish 10 messages, history with limit 5 returns 5',
          () async {
        final channelName = testChannelName('rsl2b2-limit');
        final channel = client.channels.get(channelName);

        for (var i = 0; i < 10; i++) {
          await channel.publish(name: 'evt', data: 'msg$i');
        }

        // Poll until all 10 are visible.
        await pollUntil(
          () async {
            final p = await channel.history();
            if (p.items.length >= 10) return p;
            return null;
          },
          timeout: const Duration(seconds: 20),
        );

        // Now fetch with limit 5.
        final page = await channel.history(
          const RestHistoryParams(limit: 5),
        );

        expect(
          page.items.length,
          equals(5),
          reason: 'limit: 5 should return exactly 5 messages',
        );
      });
    });

    // ---------------------------------------------------------------------------
    // RSL2b3 — Time range
    // ---------------------------------------------------------------------------
    group('RSL2b3 - Time range', () {
      test('RSL2b3 - query with start/end returns only messages in range',
          () async {
        final channelName = testChannelName('rsl2b3-timerange');
        final channel = client.channels.get(channelName);

        // Publish an "early" batch.
        await channel.publish(name: 'early', data: 'early1');
        await channel.publish(name: 'early', data: 'early2');

        // Wait for the early messages to appear in history so we can capture
        // their timestamps.
        final earlyPage = await pollUntil(
          () async {
            final p = await channel.history(
              const RestHistoryParams(direction: HistoryDirection.forwards),
            );
            if (p.items.length >= 2) return p;
            return null;
          },
          timeout: const Duration(seconds: 15),
        );

        // The last early message gives us a boundary timestamp.
        final boundaryMs = earlyPage.items.last.timestamp!;
        // Use a gap to ensure "late" messages fall strictly after the boundary.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Publish a "late" batch.
        await channel.publish(name: 'late', data: 'late1');
        await channel.publish(name: 'late', data: 'late2');

        // Poll until 4 messages appear.
        await pollUntil(
          () async {
            final p = await channel.history();
            if (p.items.length >= 4) return p;
            return null;
          },
          timeout: const Duration(seconds: 15),
        );

        // Query only for messages after the boundary (late batch).
        final latePage = await channel.history(
          RestHistoryParams(
            start: boundaryMs + 1,
            direction: HistoryDirection.forwards,
          ),
        );

        expect(
          latePage.items.length,
          equals(2),
          reason: 'Should return only the 2 late messages',
        );
        for (final msg in latePage.items) {
          expect(
            msg.name,
            equals('late'),
            reason: 'Only messages after the time boundary should be returned',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // RSL2 — Empty channel
    // ---------------------------------------------------------------------------
    group('RSL2 - Empty channel history', () {
      test(
          'RSL2 - history on a fresh channel returns empty items and hasNext false',
          () async {
        final channelName = testChannelName('rsl2-empty');
        final channel = client.channels.get(channelName);

        final page = await channel.history();

        expect(
          page.items,
          isEmpty,
          reason: 'Fresh channel should have no history',
        );
        expect(
          page.hasNext(),
          isFalse,
          reason: 'Empty history should not have a next page',
        );
      });
    });
  });
}

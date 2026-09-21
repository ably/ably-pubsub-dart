@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/test_app_helper.dart';

void main() {
  late TestApp testApp;
  late RestClient client;

  setUpAll(() async {
    testApp = await TestApp.provision();
    client = RestClient(
      options: ClientOptions(
        key: testApp.keys[0].keyStr,
        endpoint: 'nonprod:sandbox',
        useBinaryProtocol: false,
      ),
    );
  });

  tearDownAll(() async {
    await client.close();
    await testApp.delete();
  });

  // ---------------------------------------------------------------------------
  // RSC16 — server time
  // ---------------------------------------------------------------------------
  group('RSC16 - time()', () {
    // UTS: rest/integration/RSC16/time-returns-server-time-0
    test('RSC16 - time() returns server time within 5 seconds of local time',
        () async {
      final before = DateTime.now();
      final serverTime = await client.time();
      final after = DateTime.now();

      // Server time must be a valid DateTime
      expect(serverTime, isA<DateTime>());

      // Server time should be close to client time (within 5 seconds either
      // way, allowing for network latency and minor clock skew).
      final diff = serverTime.difference(before).abs();
      final diffFromAfter = serverTime.difference(after).abs();
      final minDiff = diff < diffFromAfter ? diff : diffFromAfter;

      expect(
        minDiff,
        lessThan(const Duration(seconds: 5)),
        reason: 'Server time ($serverTime) differs from client time ($before) '
            'by more than 5 seconds',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSC6 — stats()
  // ---------------------------------------------------------------------------
  group('RSC6 - stats()', () {
    // UTS: rest/integration/RSC6/stats-returns-result-0
    test('RSC6 - stats() returns PaginatedResult of Stats', () async {
      final result = await client.stats();

      expect(result, isA<PaginatedResult<Stats>>());
      expect(result.items, isA<List<Stats>>());
      // A fresh sandbox app may have zero stats entries — that is fine.
    });

    // UTS: rest/integration/RSC6/stats-with-parameters-1
    test('RSC6 - stats() with limit/direction/unit respects parameters',
        () async {
      final result = await client.stats(
        limit: 5,
        direction: StatsDirection.forwards,
        unit: StatsUnit.hour,
      );

      expect(result, isA<PaginatedResult<Stats>>());
      expect(
        result.items.length,
        lessThanOrEqualTo(5),
        reason: 'limit: 5 should return at most 5 items',
      );
    });
  });
}

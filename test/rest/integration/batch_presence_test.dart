@Tags(['integration'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../helpers/protocol_variants.dart';
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

  groupEachProtocol('Rest Batch Presence', (protocol) {
    // Helper: REST client (full-access key[0]).
    RestClient makeRestClient([int keyIndex = 0]) => RestClient(
          options: ClientOptions(
            key: testApp.keys[keyIndex].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );

    // Helper: Realtime client for enterClient (key auth, no clientId on options).
    RealtimeClient makeRealtimeClientForEnterClient([int keyIndex = 0]) =>
        RealtimeClient(
          options: ClientOptions(
            key: testApp.keys[keyIndex].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );

    // -----------------------------------------------------------------------
    // RSC24, BGR2 - batchPresence returns members for both queried channels
    // -----------------------------------------------------------------------
    group('RSC24, BGR2 - batchPresence returns presence for multiple channels',
        () {
      test(
          'RSC24, BGR2 - Enter members on 2 channels, batchPresence returns successCount==2 with correct members',
          () async {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final channelA = 'persisted:batch-presence-a-$ts';
        final channelB = 'persisted:batch-presence-b-$ts';
        const memberA = 'user-a';
        const memberB = 'user-b';

        // Enter presence on both channels via Realtime.
        final realtime = makeRealtimeClientForEnterClient();

        final rtChannelA = realtime.channels.get(channelA);
        final rtChannelB = realtime.channels.get(channelB);

        await rtChannelA.attach();
        await rtChannelB.attach();

        await rtChannelA.presence.enterClient(memberA, 'data-a');
        await rtChannelB.presence.enterClient(memberB, 'data-b');

        // Poll until both channels show the entered member via REST.
        final restClient = makeRestClient();

        await pollUntil(
          () async {
            final resp = await restClient.batchPresence([channelA, channelB]);
            if (resp.successCount < 2) return null;
            final resultA =
                resp.results.whereType<BatchPresenceSuccessResult>().firstWhere(
                      (r) => r.channel == channelA,
                      orElse: () => BatchPresenceSuccessResult(
                        channel: channelA,
                        presence: [],
                      ),
                    );
            final resultB =
                resp.results.whereType<BatchPresenceSuccessResult>().firstWhere(
                      (r) => r.channel == channelB,
                      orElse: () => BatchPresenceSuccessResult(
                        channel: channelB,
                        presence: [],
                      ),
                    );
            if (resultA.presence.isEmpty || resultB.presence.isEmpty) {
              return null;
            }
            return true;
          },
          timeout: const Duration(seconds: 20),
        );

        // Keep realtime open during query (per spec requirement).
        final response = await restClient.batchPresence([channelA, channelB]);

        expect(response.successCount, equals(2));
        expect(response.failureCount, equals(0));

        final resultA = response.results
            .whereType<BatchPresenceSuccessResult>()
            .firstWhere((r) => r.channel == channelA);
        final resultB = response.results
            .whereType<BatchPresenceSuccessResult>()
            .firstWhere((r) => r.channel == channelB);

        final clientIdsA = resultA.presence.map((m) => m.clientId).toList();
        final clientIdsB = resultB.presence.map((m) => m.clientId).toList();

        expect(clientIdsA, contains(memberA));
        expect(clientIdsB, contains(memberB));

        await realtime.close();
      });
    });

    // -----------------------------------------------------------------------
    // RSC24, BGF2 - Restricted key: allowed channel succeeds, denied channel fails
    // -----------------------------------------------------------------------
    group('RSC24, BGF2 - Restricted key causes partial failure', () {
      test(
          'RSC24, BGF2 - keys[2] can access channel6 but not a random channel, failureCount==1 with error 40160',
          () async {
        // keys[2] capability: channel0-channel6 with varying access.
        // channel6 has ["*"] so all operations including presence are allowed.
        // A random channel name outside that list will be denied.
        final ts = DateTime.now().millisecondsSinceEpoch;
        final deniedChannel = 'persisted:not-allowed-$ts';
        const allowedChannel = 'channel6';

        final restrictedRestClient = makeRestClient(2);

        final response = await restrictedRestClient
            .batchPresence([allowedChannel, deniedChannel]);

        expect(response.successCount, equals(1));
        expect(response.failureCount, equals(1));

        final failureResult = response.results
            .whereType<BatchPresenceFailureResult>()
            .firstWhere((r) => r.channel == deniedChannel);

        expect(failureResult.error.code, equals(40160));
      });
    });

    // -----------------------------------------------------------------------
    // RSC24 empty channel - verify empty and populated channels both succeed
    // -----------------------------------------------------------------------
    group('RSC24 - Empty and populated channels both succeed', () {
      test(
          'RSC24 - batchPresence on empty channel + populated channel: both succeed',
          () async {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final emptyChannel = 'persisted:bp-empty-$ts';
        final populatedChannel = 'persisted:bp-populated-$ts';
        const memberId = 'member-one';

        // Enter presence on the populated channel.
        final realtime = makeRealtimeClientForEnterClient();
        final rtChannel = realtime.channels.get(populatedChannel);
        await rtChannel.attach();
        await rtChannel.presence.enterClient(memberId, 'present');

        // Poll until the member is visible via REST.
        final restClient = makeRestClient();
        await pollUntil(
          () async {
            final resp = await restClient.batchPresence([populatedChannel]);
            if (resp.successCount < 1) return null;
            final result =
                resp.results.whereType<BatchPresenceSuccessResult>().firstWhere(
                      (r) => r.channel == populatedChannel,
                      orElse: () => BatchPresenceSuccessResult(
                        channel: populatedChannel,
                        presence: [],
                      ),
                    );
            return result.presence.isNotEmpty ? true : null;
          },
          timeout: const Duration(seconds: 20),
        );

        final response =
            await restClient.batchPresence([emptyChannel, populatedChannel]);

        expect(response.successCount, equals(2));
        expect(response.failureCount, equals(0));

        final emptyResult = response.results
            .whereType<BatchPresenceSuccessResult>()
            .firstWhere((r) => r.channel == emptyChannel);
        expect(emptyResult.presence, isEmpty);

        final populatedResult = response.results
            .whereType<BatchPresenceSuccessResult>()
            .firstWhere((r) => r.channel == populatedChannel);
        expect(populatedResult.presence.length, equals(1));
        expect(
          populatedResult.presence.first.clientId,
          equals(memberId),
        );

        await realtime.close();
      });
    });
  });
}

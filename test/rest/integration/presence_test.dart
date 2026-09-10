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

  groupEachProtocol('Rest Presence', (protocol) {
    // Helper: create a REST client.
    RestClient makeRestClient([int keyIndex = 0]) => RestClient(
          options: ClientOptions(
            key: testApp.keys[keyIndex].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );

    // Helper: create a Realtime client with a specific clientId.
    RealtimeClient makeRealtimeClientWithClientId(String clientId) =>
        RealtimeClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            clientId: clientId,
          ),
        );

    // The fixture channel with pre-populated presence members from test-app-setup.json.
    const fixtureChannelName = 'persisted:presence_fixtures';

    // -----------------------------------------------------------------------
    // RSP1: channel.presence is not null
    // -----------------------------------------------------------------------
    group('RSP1 - RestPresence is accessible on channel', () {
      // UTS: rest/integration/RSP1/access-presence-from-channel-0
      test('RSP1 - channel.presence is not null', () {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);
        expect(channel.presence, isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // RSP3_1: presence.get() returns >= 5 fixture members
    // -----------------------------------------------------------------------
    group('RSP3_1 - presence.get() returns fixture members', () {
      test(
          'RSP3_1 - get() returns PaginatedResult with >= 5 items including known clientIds',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get();

        expect(page.items.length, greaterThanOrEqualTo(5));

        final clientIds = page.items.map((m) => m.clientId).toSet();
        expect(clientIds, contains('client_bool'));
        expect(clientIds, contains('client_string'));
        expect(clientIds, contains('client_json'));
      });
    });

    // -----------------------------------------------------------------------
    // RSP3_2: Verify client_string member fields
    // -----------------------------------------------------------------------
    group('RSP3_2 - client_string member has correct fields', () {
      test(
          'RSP3_2 - client_string member has action==present, correct data, non-null connectionId',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get();
        final member =
            page.items.firstWhere((m) => m.clientId == 'client_string');

        expect(member.action, equals(PresenceAction.present));
        expect(member.data, equals('This is a string clientData payload'));
        expect(member.connectionId, isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // RSP3a1: presence.get(limit: 2) returns <= 2 items
    // -----------------------------------------------------------------------
    group('RSP3a1 - presence.get() respects limit parameter', () {
      // UTS: rest/integration/RSP3a1/get-with-limit-0
      test('RSP3a1 - get(limit: 2) returns at most 2 items', () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get(
          const RestPresenceParams(limit: 2),
        );

        expect(page.items.length, lessThanOrEqualTo(2));
      });
    });

    // -----------------------------------------------------------------------
    // RSP3a2: presence.get(clientId: 'client_json') returns exactly 1 item
    // -----------------------------------------------------------------------
    group('RSP3a2 - presence.get() can filter by clientId', () {
      test(
          'RSP3a2 - get(clientId: client_json) returns 1 item with json payload',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get(
          const RestPresenceParams(clientId: 'client_json'),
        );

        expect(page.items.length, equals(1));
        expect(page.items.first.clientId, equals('client_json'));
      });
    });

    // -----------------------------------------------------------------------
    // RSP3_Empty: Fresh channel presence.get() returns empty list
    // -----------------------------------------------------------------------
    group('RSP3_Empty - get() on empty channel returns empty result', () {
      // UTS: rest/integration/RSP3/get-empty-channel-2
      test('RSP3_Empty - empty channel has no presence members', () async {
        final client = makeRestClient();
        final channelName =
            'persisted:presence-empty-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final page = await channel.presence.get();

        expect(page.items, isEmpty);
        expect(page.hasNext(), isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // RSP5_1: client_string data is a String
    // -----------------------------------------------------------------------
    group('RSP5_1 - client_string data is correctly typed as String', () {
      // UTS: rest/integration/RSP5/decode-string-data-0
      test('RSP5_1 - client_string data is a String with correct value',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get();
        final member =
            page.items.firstWhere((m) => m.clientId == 'client_string');

        expect(member.data, isA<String>());
        expect(
          member.data as String,
          equals('This is a string clientData payload'),
        );
      });
    });

    // -----------------------------------------------------------------------
    // RSP5_2: client_decoded data is Map with nested json field
    // -----------------------------------------------------------------------
    group('RSP5_2 - client_decoded data is decoded to a Map', () {
      test(
          'RSP5_2 - client_decoded data is Map with data[example][json] == Object',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final page = await channel.presence.get();
        final member =
            page.items.firstWhere((m) => m.clientId == 'client_decoded');

        expect(member.data, isA<Map>());
        final data = member.data as Map;
        expect(data['example'], isA<Map>());
        final example = data['example'] as Map;
        expect(example['json'], equals('Object'));
      });
    });

    // -----------------------------------------------------------------------
    // RSP4_1: Realtime enter/update/leave generates history entries
    // -----------------------------------------------------------------------
    group('RSP4_1 - Realtime presence actions appear in REST history', () {
      test(
          'RSP4_1 - enter/update/leave via Realtime appear in REST presence history',
          () async {
        const clientId = 'test-client-rsp4-1';
        final channelName =
            'persisted:presence-history-${DateTime.now().millisecondsSinceEpoch}';

        final realtime = makeRealtimeClientWithClientId(clientId);
        final rtChannel = realtime.channels.get(channelName);
        await rtChannel.attach();

        await rtChannel.presence.enter('enter-data');
        await rtChannel.presence.update('update-data');
        await rtChannel.presence.leave('leave-data');

        await realtime.close();

        // Poll REST until we see >= 3 presence history entries.
        final restClient = makeRestClient();
        final restChannel = restClient.channels.get(channelName);

        await pollUntil(
          () async {
            final page = await restChannel.presence.history();
            return page.items.length >= 3 ? true : null;
          },
          timeout: const Duration(seconds: 20),
        );

        final page = await restChannel.presence.history();
        final actions = page.items.map((m) => m.action).toSet();

        expect(actions, contains(PresenceAction.enter));
        expect(actions, contains(PresenceAction.update));
        expect(actions, contains(PresenceAction.leave));
      });
    });

    // -----------------------------------------------------------------------
    // RSP4b2: Forwards direction returns events in chronological order
    // -----------------------------------------------------------------------
    group('RSP4b2 - presence history direction forwards', () {
      test(
          'RSP4b2 - history(direction: forwards) first item is the earliest event',
          () async {
        const clientId = 'test-client-rsp4b2';
        final channelName =
            'persisted:presence-fwd-${DateTime.now().millisecondsSinceEpoch}';

        final realtime = makeRealtimeClientWithClientId(clientId);
        final rtChannel = realtime.channels.get(channelName);
        await rtChannel.attach();

        await rtChannel.presence.enter('first');
        await rtChannel.presence.update('second-update');

        await realtime.close();

        final restClient = makeRestClient();
        final restChannel = restClient.channels.get(channelName);

        // Poll until at least 2 history entries exist.
        await pollUntil(
          () async {
            final page = await restChannel.presence.history();
            return page.items.length >= 2 ? true : null;
          },
          timeout: const Duration(seconds: 20),
        );

        final page = await restChannel.presence.history(
          const RestHistoryParams(direction: HistoryDirection.forwards),
        );

        expect(page.items, isNotEmpty);
        // The first item in forwards order is the ENTER (earliest event).
        expect(page.items.first.action, equals(PresenceAction.enter));
        expect(page.items.first.data, equals('first'));
      });
    });

    // -----------------------------------------------------------------------
    // RSP_Pagination: Paginate through fixture presence with limit 2
    // -----------------------------------------------------------------------
    group('RSP_Pagination - presence.get() pagination', () {
      test(
          'RSP_Pagination - paginate fixture channel with limit 2, collect >= 5 unique clientIds',
          () async {
        final client = makeRestClient();
        final channel = client.channels.get(fixtureChannelName);

        final allMembers = <PresenceMessage>[];
        PaginatedResult<PresenceMessage>? current =
            await channel.presence.get(const RestPresenceParams(limit: 2));

        while (current != null) {
          allMembers.addAll(current.items);
          current = current.hasNext() ? await current.next() : null;
        }

        expect(allMembers.length, greaterThanOrEqualTo(5));

        // No duplicate clientIds.
        final clientIds = allMembers.map((m) => m.clientId).toList();
        final uniqueClientIds = clientIds.toSet();
        expect(uniqueClientIds.length, equals(clientIds.length));
      });
    });

    // -----------------------------------------------------------------------
    // RSP_Error_1: Invalid key causes 401
    // -----------------------------------------------------------------------
    group('RSP_Error_1 - Invalid API key returns auth error', () {
      // UTS: rest/integration/RSP3/get-presence-members-0
      test('RSP_Error_1 - presence.get() with invalid key throws 401',
          () async {
        // Use a syntactically valid key format but one that will be rejected.
        final client = RestClient(
          options: ClientOptions(
            key: 'invalid.key:secret',
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
        final channel = client.channels.get(fixtureChannelName);

        expect(
          () => channel.presence.get(),
          throwsA(
            predicate((e) {
              if (e is AblyException) {
                return e.statusCode == 401;
              }
              return false;
            }),
          ),
        );
      });
    });
  });
}

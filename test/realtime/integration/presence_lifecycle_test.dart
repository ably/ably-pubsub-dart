@Tags(['integration'])
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/wait_for_state.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Realtime Presence Lifecycle Integration Tests',
      (protocol) {
    /// Helper to create a Realtime client with optional clientId.
    PubSubClient buildClient({String? clientId, bool autoConnect = false}) =>
        createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: autoConnect,
            clientId: clientId,
          ),
        );

    /// Unique channel name for each test.
    String uniqueChannel(String prefix) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rand = Random().nextInt(100000);
      return '$prefix-$ts-$rand';
    }

    group('Presence lifecycle', () {
      // -------------------------------------------------------------------------
      // RTP8, RTP9, RTP10 - Enter, update, leave lifecycle
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTP8/enter-update-leave-lifecycle-0
      test(
        'RTP8, RTP9, RTP10 - Enter, update, leave lifecycle',
        () async {
          final clientA = buildClient(clientId: 'lifecycle-client');
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          final channelName = uniqueChannel('presence-lifecycle');

          // Connect both clients (fire-and-forget, then await state)
          clientA.connect();
          clientB.connect();
          await Future.wait([
            waitForConnectionState(
              clientA.connection,
              ConnectionState.connected,
            ),
            waitForConnectionState(
              clientB.connection,
              ConnectionState.connected,
            ),
          ]);

          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          // Attach both channels
          await channelA.attach();
          await channelB.attach();

          // Collect presence events on channel B
          final events = <PresenceMessage>[];
          channelB.presence.subscribe((event) {
            events.add(event);
          });

          // RTP8: Enter presence
          await channelA.presence.enter('hello');

          // Wait until 1 event received, then verify get()
          await pollUntil(() async => events.isNotEmpty ? true : null);
          final membersAfterEnter = await channelB.presence.get();
          expect(membersAfterEnter.length, equals(1));
          expect(membersAfterEnter.first.clientId, equals('lifecycle-client'));
          expect(membersAfterEnter.first.data, equals('hello'));

          // RTP9: Update presence
          await channelA.presence.update('world');

          await pollUntil(() async => events.length >= 2 ? true : null);
          final membersAfterUpdate = await channelB.presence.get();
          expect(membersAfterUpdate.length, equals(1));
          expect(membersAfterUpdate.first.data, equals('world'));

          // RTP10: Leave presence
          await channelA.presence.leave('goodbye');

          await pollUntil(() async => events.length >= 3 ? true : null);
          final membersAfterLeave = await channelB.presence.get();
          expect(membersAfterLeave, isEmpty);

          // Verify event sequence: ENTER/hello, UPDATE/world, LEAVE/goodbye
          expect(events.length, equals(3));

          expect(events[0].action, equals(PresenceAction.enter));
          expect(events[0].data, equals('hello'));
          expect(events[0].clientId, equals('lifecycle-client'));

          expect(events[1].action, equals(PresenceAction.update));
          expect(events[1].data, equals('world'));
          expect(events[1].clientId, equals('lifecycle-client'));

          expect(events[2].action, equals(PresenceAction.leave));
          expect(events[2].data, equals('goodbye'));
          expect(events[2].clientId, equals('lifecycle-client'));
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      // -------------------------------------------------------------------------
      // RTP4, RTP6, RTP11a - Bulk enterClient observed on different connection
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTP4/bulk-enter-observed-0
      test(
        'RTP4, RTP6, RTP11a - Bulk enterClient observed on different connection',
        () async {
          // Use key auth without clientId for enterClient with multiple clientIds
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          final channelName = uniqueChannel('presence-bulk');
          const memberCount = 20;

          // Connect both clients (fire-and-forget, then await state)
          clientA.connect();
          clientB.connect();
          await Future.wait([
            waitForConnectionState(
              clientA.connection,
              ConnectionState.connected,
            ),
            waitForConnectionState(
              clientB.connection,
              ConnectionState.connected,
            ),
          ]);

          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          // Subscribe to ENTER events on channel B BEFORE attaching
          final enterEvents = <PresenceMessage>[];
          channelB.presence.subscribe(
            (event) {
              if (event.action == PresenceAction.enter) {
                enterEvents.add(event);
              }
            },
            action: PresenceAction.enter,
          );

          // Attach both channels
          await channelA.attach();
          await channelB.attach();

          // Enter 20 clients in parallel via enterClient
          await Future.wait(
            List.generate(memberCount, (i) {
              return channelA.presence.enterClient('user-$i', 'data-$i');
            }),
          );

          // Wait until all 20 ENTER events are received on B
          await pollUntil(
            () async => enterEvents.length >= memberCount ? true : null,
            timeout: const Duration(seconds: 20),
          );

          expect(enterEvents.length, equals(memberCount));

          // Verify presence.get() returns all 20 members
          final members = await channelB.presence.get();
          expect(members.length, equals(memberCount));

          // Verify each member has correct clientId and data
          final memberMap = {
            for (final m in members) m.clientId: m.data,
          };
          for (var i = 0; i < memberCount; i++) {
            expect(
              memberMap.containsKey('user-$i'),
              isTrue,
              reason: 'Missing member user-$i',
            );
            expect(
              memberMap['user-$i'],
              equals('data-$i'),
              reason: 'Wrong data for user-$i',
            );
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    });
  });
}

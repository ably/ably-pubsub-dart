import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// Presence Sync Tests
///
/// Spec points: RTP18, RTP18a, RTP18b, RTP18c, RTP19, RTP19a
///
/// Spec: uts/test/realtime/unit/presence/presence_sync.md
void main() {
  group('Presence Sync', () {
    group('RTP18a - startSync sets isSyncInProgress', () {
      // UTS: realtime/unit/RTP18a/startsync-sets-flag-0
      test('isSyncInProgress becomes true after startSync', () {
        final map = PresenceMap();
        expect(map.isSyncInProgress, isFalse);

        map.startSync();

        expect(map.isSyncInProgress, isTrue);
      });
    });

    group('RTP18b - endSync clears isSyncInProgress', () {
      // UTS: realtime/unit/RTP18b/endsync-clears-flag-0
      test('isSyncInProgress becomes false after endSync', () {
        final map = PresenceMap();
        map.startSync();
        expect(map.isSyncInProgress, isTrue);

        map.endSync();

        expect(map.isSyncInProgress, isFalse);
      });
    });

    group('RTP19 - Stale members get LEAVE events after sync', () {
      // UTS: realtime/unit/RTP19/stale-members-leave-after-sync-0
      test('members not updated during sync get LEAVE events', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        expect(map.values().length, equals(2));

        // Start sync — only alice appears in sync data
        map.startSync();
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // End sync — bob was not updated, gets removed
        final leaveEvents = map.endSync();

        expect(leaveEvents.length, equals(1));
        expect(leaveEvents[0].clientId, equals('bob'));
        expect(leaveEvents[0].action, equals(PresenceAction.leave));

        // Only alice remains
        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c2:bob'), isNull);
      });
    });

    group('RTP19 - Synthesized LEAVE has id=null and current timestamp', () {
      // UTS: realtime/unit/RTP19/synth-leave-null-id-timestamp-1
      test('leave events have null id and recent timestamp', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            data: 'bob-data',
          ),
        );

        final beforeTime = DateTime.now();

        map.startSync();
        // No messages for bob during sync
        final leaveEvents = map.endSync();

        final afterTime = DateTime.now();

        expect(leaveEvents.length, equals(1));

        final leave = leaveEvents[0];
        expect(leave.action, equals(PresenceAction.leave));
        expect(leave.clientId, equals('bob'));
        expect(leave.connectionId, equals('c2'));
        expect(leave.data, equals('bob-data'));
        expect(leave.id, isNull);
        expect(
          leave.timestamp!.millisecondsSinceEpoch,
          greaterThanOrEqualTo(beforeTime.millisecondsSinceEpoch),
        );
        expect(
          leave.timestamp!.millisecondsSinceEpoch,
          lessThanOrEqualTo(afterTime.millisecondsSinceEpoch),
        );
      });
    });

    group('RTP19 - Members updated during sync survive', () {
      // UTS: realtime/unit/RTP19/updated-members-survive-sync-2
      test('members seen during sync are not removed', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'carol',
            connectionId: 'c3',
            id: 'c3:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        map.startSync();

        // Alice via SYNC (PRESENT action)
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Bob via PRESENCE during sync (UPDATE action)
        map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
            data: 'new-data',
          ),
        );

        // Carol does NOT appear during sync
        final leaveEvents = map.endSync();

        // Only carol is stale
        expect(leaveEvents.length, equals(1));
        expect(leaveEvents[0].clientId, equals('carol'));

        // Alice and bob survive
        expect(map.values().length, equals(2));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c2:bob'), isNotNull);
        expect(map.get('c2:bob')!.data, equals('new-data'));
      });
    });

    group('RTP18a - New sync discards previous in-flight sync', () {
      // UTS: realtime/unit/RTP18a/new-sync-discards-previous-1
      test('starting new sync resets residual tracking', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        // First sync starts — only alice appears
        map.startSync();
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Before first sync ends, a NEW sync starts
        map.startSync();

        // In the new sync, both alice and bob appear
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:2:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(300),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(300),
          ),
        );

        final leaveEvents = map.endSync();

        // No stale members — both were seen in the new sync
        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(2));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c2:bob'), isNotNull);
      });
    });

    group('RTP18c - Single-message sync', () {
      // UTS: realtime/unit/RTP18c/single-message-sync-0
      test('sync with immediate start and end', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        // Single-message sync: start, put one member, end immediately
        map.startSync();
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );
        final leaveEvents = map.endSync();

        // Bob was not in the sync — gets LEAVE
        expect(leaveEvents.length, equals(1));
        expect(leaveEvents[0].clientId, equals('bob'));
        expect(leaveEvents[0].action, equals(PresenceAction.leave));

        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.isSyncInProgress, isFalse);
      });
    });

    group('RTP19a - ATTACHED without HAS_PRESENCE clears all members', () {
      // UTS: realtime/unit/RTP19a/no-has-presence-clears-members-0
      test('startSync + endSync with no puts removes all members', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            data: 'a',
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            data: 'b',
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'carol',
            connectionId: 'c3',
            id: 'c3:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            data: 'c',
          ),
        );

        // No HAS_PRESENCE: immediate sync with no members
        map.startSync();
        final leaveEvents = map.endSync();

        // All members get LEAVE events
        expect(leaveEvents.length, equals(3));

        final aliceLeave = leaveEvents.firstWhere(
          (e) => e.clientId == 'alice',
        );
        final bobLeave = leaveEvents.firstWhere(
          (e) => e.clientId == 'bob',
        );
        final carolLeave = leaveEvents.firstWhere(
          (e) => e.clientId == 'carol',
        );

        expect(aliceLeave.action, equals(PresenceAction.leave));
        expect(aliceLeave.data, equals('a'));
        expect(aliceLeave.id, isNull);

        expect(bobLeave.action, equals(PresenceAction.leave));
        expect(bobLeave.data, equals('b'));
        expect(bobLeave.id, isNull);

        expect(carolLeave.action, equals(PresenceAction.leave));
        expect(carolLeave.data, equals('c'));
        expect(carolLeave.id, isNull);

        // Map is empty
        expect(map.values(), isEmpty);
      });
    });

    group('RTP2h2a - LEAVE during sync stored as ABSENT (in sync context)', () {
      // UTS: realtime/unit/RTP2h2a/leave-during-sync-absent-cleanup-0
      test('LEAVE during sync becomes ABSENT, cleaned up on endSync', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        map.startSync();

        // Alice appears in sync
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Bob sends LEAVE during sync — stored as ABSENT
        final leaveResult = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        expect(leaveResult, isNull);
        expect(map.get('c2:bob'), isNotNull);
        expect(map.get('c2:bob')!.action, equals(PresenceAction.absent));

        // End sync
        map.endSync();

        // Bob's ABSENT entry is cleaned up
        expect(map.get('c2:bob'), isNull);

        // Alice survives
        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);
      });
    });

    group('RTP19 - Empty map sync produces no leave events', () {
      // UTS: realtime/unit/RTP19/empty-map-sync-no-leaves-3
      test('sync on empty map then adding members produces no leaves', () {
        final map = PresenceMap();
        map.startSync();
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );
        final leaveEvents = map.endSync();

        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);
      });
    });

    group('RTP18 - endSync without startSync is a no-op', () {
      // UTS: realtime/unit/RTP18/endsync-without-startsync-noop-0
      test('endSync when no sync is in progress preserves map state', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        final leaveEvents = map.endSync();

        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.isSyncInProgress, isFalse);
      });
    });

    group('RTP19 - Stale SYNC message still removes member from residuals', () {
      // UTS: realtime/unit/RTP19/stale-sync-removes-from-residuals-4
      test('stale put is rejected but member survives endSync', () {
        final map = PresenceMap();

        // Pre-populate with a member via ENTER
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:5:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(500),
            data: 'original',
          ),
        );

        // Start sync
        map.startSync();

        // SYNC message arrives with OLDER id (stale — lower msgSerial)
        final result = map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:3:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(300),
            data: 'stale',
          ),
        );

        final leaveEvents = map.endSync();

        // The stale put was rejected
        expect(result, isNull);

        // But alice must NOT be evicted — she was "seen" during sync
        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(1));
        expect(map.get('c1:alice'), isNotNull);

        // Original data is preserved (stale message did not overwrite)
        expect(map.get('c1:alice')!.data, equals('original'));
      });
    });

    group('RTP19 - PRESENCE echoes followed by SYNC preserves all members', () {
      // UTS: realtime/unit/RTP19/presence-echoes-then-sync-preserves-5
      test('stale SYNC ids do not cause members to be evicted as residual', () {
        final map = PresenceMap();

        // Simulate server echoing PRESENCE events for 3 members
        for (var i = 0; i < 3; i++) {
          map.put(
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'user-$i',
              connectionId: 'c1',
              id: 'c1:$i:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
              data: 'data-$i',
            ),
          );
        }

        expect(map.values().length, equals(3));

        // Server starts SYNC — members already exist from PRESENCE echoes
        map.startSync();

        // SYNC messages arrive with the SAME ids as the PRESENCE echoes (stale)
        for (var i = 0; i < 3; i++) {
          map.put(
            PresenceMessage(
              action: PresenceAction.present,
              clientId: 'user-$i',
              connectionId: 'c1',
              id: 'c1:$i:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
              data: 'data-$i',
            ),
          );
        }

        final leaveEvents = map.endSync();

        // No members evicted — all were seen during sync despite stale ids
        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(3));

        for (var i = 0; i < 3; i++) {
          final member = map.get('c1:user-$i');
          expect(member, isNotNull);
          expect(member!.data, equals('data-$i'));
        }
      });
    });

    group('RTP19 - New member added during sync is not stale', () {
      // UTS: realtime/unit/RTP19/new-member-during-sync-survives-6
      test('new member during sync survives endSync', () {
        final map = PresenceMap();
        // Pre-populate with alice only
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        map.startSync();

        // Alice appears in sync
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Bob is NEW — entered via PRESENCE during sync
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        final leaveEvents = map.endSync();

        // No leave events — both alice and bob are current
        expect(leaveEvents, isEmpty);
        expect(map.values().length, equals(2));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c2:bob'), isNotNull);
      });
    });
  });
}

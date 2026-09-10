import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// PresenceMap Tests
///
/// Spec points: RTP2, RTP2a, RTP2b, RTP2b1, RTP2b1a, RTP2b2, RTP2c,
///              RTP2d, RTP2d1, RTP2d2, RTP2h, RTP2h1, RTP2h1a, RTP2h1b,
///              RTP2h2, RTP2h2a, RTP2h2b
///
/// Spec: uts/test/realtime/unit/presence/presence_map.md
void main() {
  group('PresenceMap', () {
    group('RTP2 - Basic put and get', () {
      // UTS: realtime/unit/RTP2/basic-put-and-get-0
      test('put ENTER message and retrieve by memberKey', () {
        final map = PresenceMap();
        final msg = PresenceMessage(
          action: PresenceAction.enter,
          clientId: 'client-1',
          connectionId: 'conn-1',
          id: 'conn-1:0:0',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        );
        final result = map.put(msg);

        expect(result, isNotNull);
        expect(map.get('conn-1:client-1'), isNotNull);
        expect(map.get('conn-1:client-1')!.clientId, equals('client-1'));
        expect(
          map.get('conn-1:client-1')!.connectionId,
          equals('conn-1'),
        );
      });
    });

    group('RTP2d2 - ENTER stored as PRESENT', () {
      // UTS: realtime/unit/RTP2d2/update-stored-as-present-1
      test('ENTER message stored with action PRESENT', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'entered',
          ),
        );

        final stored = map.get('conn-1:client-1');
        expect(stored, isNotNull);
        expect(stored!.action, equals(PresenceAction.present));
        expect(stored.data, equals('entered'));
      });

      // UTS: realtime/unit/RTP2d2/enter-stored-as-present-0
      test('UPDATE message stored with action PRESENT', () {
        final map = PresenceMap();
        // First enter
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'initial',
          ),
        );
        // Then update
        map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            data: 'updated',
          ),
        );

        final stored = map.get('conn-1:client-1');
        expect(stored!.action, equals(PresenceAction.present));
        expect(stored.data, equals('updated'));
      });

      // UTS: realtime/unit/RTP2d2/present-stored-as-present-2
      test('PRESENT message stored with action PRESENT', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        final stored = map.get('conn-1:client-1');
        expect(stored, isNotNull);
        expect(stored!.action, equals(PresenceAction.present));
      });
    });

    group('RTP2d1 - put returns message with original action', () {
      // UTS: realtime/unit/RTP2d1/put-returns-original-action-0
      test('emitted message preserves original ENTER action', () {
        final map = PresenceMap();
        final emittedEnter = map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        final emittedUpdate = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            data: 'updated',
          ),
        );

        expect(emittedEnter, isNotNull);
        expect(emittedEnter!.action, equals(PresenceAction.enter));

        expect(emittedUpdate, isNotNull);
        expect(emittedUpdate!.action, equals(PresenceAction.update));
      });
    });

    group('RTP2h1 - LEAVE outside sync removes member', () {
      // UTS: realtime/unit/RTP2h1/leave-outside-sync-removes-0
      test('remove returns LEAVE and deletes from map', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        final emitted = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
        );

        // RTP2h1a: emit LEAVE to subscribers
        expect(emitted, isNotNull);
        expect(emitted!.action, equals(PresenceAction.leave));

        // RTP2h1b: deleted from presence map
        expect(map.get('conn-1:client-1'), isNull);
        expect(map.values(), isEmpty);
      });

      // UTS: realtime/unit/RTP2h1/leave-nonexistent-returns-null-1
      test('LEAVE for non-existent member returns null', () {
        final map = PresenceMap();
        final emitted = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'unknown',
            connectionId: 'conn-x',
            id: 'conn-x:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        expect(emitted, isNull);
      });
    });

    group('RTP2h2a - LEAVE during sync stores as ABSENT', () {
      // UTS: realtime/unit/RTP2h2a/leave-during-sync-stores-absent-0
      test('LEAVE during sync marks member as ABSENT', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        map.startSync();

        final emitted = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
        );

        // No LEAVE emitted during sync
        expect(emitted, isNull);

        // Member is stored as ABSENT (not deleted)
        final stored = map.get('conn-1:client-1');
        expect(stored, isNotNull);
        expect(stored!.action, equals(PresenceAction.absent));
      });
    });

    group('RTP2h2b - ABSENT members deleted on endSync', () {
      // UTS: realtime/unit/RTP2h2b/absent-deleted-on-endsync-0
      test('endSync removes ABSENT entries', () {
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

        // Alice gets updated during sync
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'alice',
            connectionId: 'c1',
            id: 'c1:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Bob sends LEAVE during sync (stored as ABSENT)
        map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        map.endSync();

        // Bob's ABSENT entry was deleted
        expect(map.get('c2:bob'), isNull);

        // Alice remains
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c1:alice')!.action, equals(PresenceAction.present));
        expect(map.values().length, equals(1));
      });
    });

    group('RTP2b2 - Newness comparison by id (msgSerial:index)', () {
      // UTS: realtime/unit/RTP2b2/newness-by-msgserial-index-0
      test('newer msgSerial wins, older msgSerial rejected', () {
        final map = PresenceMap();
        // Add initial message with msgSerial=5
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:5:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'first',
          ),
        );

        // Try to put an older message (msgSerial=3) — rejected (RTP2a)
        final staleResult = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:3:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            data: 'stale',
          ),
        );

        // Put a newer message (msgSerial=7)
        final newerResult = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:7:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(500),
            data: 'newer',
          ),
        );

        expect(staleResult, isNull);
        expect(map.get('conn-1:client-1')!.data, isNot(equals('stale')));

        expect(newerResult, isNotNull);
        expect(map.get('conn-1:client-1')!.data, equals('newer'));
      });

      // UTS: realtime/unit/RTP2b2/newness-by-index-same-serial-1
      test('same msgSerial: higher index wins', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:5:2',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'index-2',
          ),
        );

        // Same msgSerial, lower index — stale
        final stale = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:5:1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            data: 'index-1',
          ),
        );

        // Same msgSerial, higher index — newer
        final newer = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:5:5',
            timestamp: DateTime.fromMillisecondsSinceEpoch(500),
            data: 'index-5',
          ),
        );

        expect(stale, isNull);
        expect(newer, isNotNull);
        expect(map.get('conn-1:client-1')!.data, equals('index-5'));
      });
    });

    group('RTP2b1 - Newness comparison by timestamp (synthesized leave)', () {
      // UTS: realtime/unit/RTP2b1/newness-by-timestamp-0
      test('synthesized leave with newer timestamp removes member', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'entered',
          ),
        );

        // Synthesized leave: id does NOT start with connectionId
        final synthLeave = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'synthesized-leave-id',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
        );

        expect(synthLeave, isNotNull);
        expect(synthLeave!.action, equals(PresenceAction.leave));
        expect(map.get('conn-1:client-1'), isNull);
      });

      // UTS: realtime/unit/RTP2b1/older-synth-leave-rejected-1
      test('synthesized leave with older timestamp is rejected', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(5000),
            data: 'entered',
          ),
        );

        // Synthesized leave with older timestamp
        final result = map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'synthesized-leave-id',
            timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
          ),
        );

        expect(result, isNull);
        expect(map.get('conn-1:client-1'), isNotNull);
        expect(map.get('conn-1:client-1')!.data, equals('entered'));
      });
    });

    group('RTP2b1a - Equal timestamps: incoming is newer', () {
      // UTS: realtime/unit/RTP2b1a/equal-timestamps-incoming-wins-0
      test('incoming message with equal timestamp wins', () {
        final map = PresenceMap();
        map.put(
          PresenceMessage(
            action: PresenceAction.enter,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'synthesized-id-1',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'first',
          ),
        );

        // Same timestamp, incoming wins
        final result = map.put(
          PresenceMessage(
            action: PresenceAction.update,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'synthesized-id-2',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'second',
          ),
        );

        expect(result, isNotNull);
        expect(map.get('conn-1:client-1')!.data, equals('second'));
      });
    });

    group('RTP2c - SYNC messages use same newness comparison', () {
      // UTS: realtime/unit/RTP2c/sync-uses-same-newness-0
      test('PRESENT messages during sync use newness check', () {
        final map = PresenceMap();
        map.startSync();

        // First SYNC message
        map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:5:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            data: 'sync-first',
          ),
        );

        // Second SYNC message with older serial — rejected
        final stale = map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:3:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            data: 'sync-stale',
          ),
        );

        // Third SYNC message with newer serial — accepted
        final newer = map.put(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'client-1',
            connectionId: 'conn-1',
            id: 'conn-1:8:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(500),
            data: 'sync-newer',
          ),
        );

        expect(stale, isNull);
        expect(newer, isNotNull);
        expect(map.get('conn-1:client-1')!.data, equals('sync-newer'));
      });
    });

    group('RTP2 - Multiple members coexist', () {
      // UTS: realtime/unit/RTP2/multiple-members-coexist-1
      test('different memberKeys stored independently', () {
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
            clientId: 'alice',
            connectionId: 'c3',
            id: 'c3:0:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(100),
          ),
        );

        // Three distinct members (alice on c1, bob on c2, alice on c3)
        expect(map.values().length, equals(3));
        expect(map.get('c1:alice'), isNotNull);
        expect(map.get('c2:bob'), isNotNull);
        expect(map.get('c3:alice'), isNotNull);
      });
    });

    group('RTP2 - values() excludes ABSENT members', () {
      // UTS: realtime/unit/RTP2/values-excludes-absent-2
      test('ABSENT members excluded from values()', () {
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

        // Start sync and mark bob as ABSENT
        map.startSync();
        map.remove(
          PresenceMessage(
            action: PresenceAction.leave,
            clientId: 'bob',
            connectionId: 'c2',
            id: 'c2:1:0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(200),
          ),
        );

        // Bob is stored as ABSENT but excluded from values()
        expect(map.get('c2:bob'), isNotNull);
        expect(map.get('c2:bob')!.action, equals(PresenceAction.absent));

        final members = map.values();
        expect(members.length, equals(1));
        expect(members[0].clientId, equals('alice'));
      });
    });

    group('clear() resets all state', () {
      // UTS: realtime/unit/RTP2/clear-resets-state-3
      test('clears map and sync state', () {
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
        map.startSync();

        map.clear();

        expect(map.values(), isEmpty);
        expect(map.get('c1:alice'), isNull);
        expect(map.isSyncInProgress, isFalse);
      });
    });
  });
}

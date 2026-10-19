import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:ably_pubsub_device/src/impl/realtime_channel_impl.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence.get (RTP11).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_get.md
void main() {
  group('RTP11a - get returns current members (single-message sync)', () {
    // UTS: realtime/unit/RTP11a/get-returns-members-single-sync-0
    test('waits for sync before returning', () async {
      final channelName = testChannelName('RTP11a-single');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Send ATTACHED with HAS_PRESENCE but do NOT send SYNC yet
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Start get() — sync has not arrived yet, so this must wait
      var getCompleted = false;
      final getFuture = channel.presence.get().then((members) {
        getCompleted = true;
        return members;
      });

      // Pump microtasks — get should NOT have completed yet
      await Future<void>.delayed(Duration.zero);
      expect(
        getCompleted,
        isFalse,
        reason: 'get() should wait for sync to complete',
      );

      // Now send a single-message SYNC (empty cursor = complete)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.sync,
          channel: channelName,
          channelSerial: 'seq1:',
          presence: [
            PresenceMessage(
              action: PresenceAction.present,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
              data: 'a',
            ),
            PresenceMessage(
              action: PresenceAction.present,
              clientId: 'bob',
              connectionId: 'c2',
              id: 'c2:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
              data: 'b',
            ),
          ],
        ),
      );

      final members = await getFuture;

      expect(members.length, equals(2));
      final clientIds = members.map((m) => m.clientId).toList()..sort();
      expect(clientIds, equals(['alice', 'bob']));

      mockWs.dispose();
    });
  });

  group('RTP11a, RTP11c1 - get waits for multi-message sync', () {
    // UTS: realtime/unit/RTP11a/get-waits-for-multi-sync-1
    test('waits for all SYNC messages before returning', () async {
      final channelName = testChannelName('RTP11c1-multi');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Start get() — sync has not arrived yet
      var getCompleted = false;
      final getFuture = channel.presence.get().then((members) {
        getCompleted = true;
        return members;
      });

      await Future<void>.delayed(Duration.zero);
      expect(getCompleted, isFalse);

      // Send first SYNC message (non-empty cursor = more to come)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.sync,
          channel: channelName,
          channelSerial: 'seq1:cursor1',
          presence: [
            PresenceMessage(
              action: PresenceAction.present,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            ),
          ],
        ),
      );

      // get() should still be waiting — sync not complete
      await Future<void>.delayed(Duration.zero);
      expect(
        getCompleted,
        isFalse,
        reason: 'get() should still wait — cursor was non-empty',
      );

      // Send final SYNC message (empty cursor = sync complete)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.sync,
          channel: channelName,
          channelSerial: 'seq1:',
          presence: [
            PresenceMessage(
              action: PresenceAction.present,
              clientId: 'bob',
              connectionId: 'c2',
              id: 'c2:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(100),
            ),
          ],
        ),
      );

      final members = await getFuture;

      // Both alice (from first SYNC) and bob (from second) are present
      expect(members.length, equals(2));
      final clientIds = members.map((m) => m.clientId).toList()..sort();
      expect(clientIds, equals(['alice', 'bob']));

      mockWs.dispose();
    });
  });

  group('RTP11c1 - get with waitForSync=false', () {
    // UTS: realtime/unit/RTP11c1/get-no-wait-returns-immediately-0
    test('returns immediately with available members', () async {
      final channelName = testChannelName('RTP11c1-nowait');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
            // Start SYNC but don't complete it (cursor is non-empty)
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.sync,
                channel: channelName,
                channelSerial: 'seq1:cursor1',
                presence: [
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c1',
                    id: 'c1:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Sync is in progress but we don't wait
      final members = await channel.presence.get(waitForSync: false);

      // Returns what's available so far (may be incomplete)
      expect(members.length, equals(1));
      expect(members[0].clientId, equals('alice'));

      mockWs.dispose();
    });
  });

  group('RTP11c2 - get filtered by clientId', () {
    // UTS: realtime/unit/RTP11c2/get-filtered-by-clientid-0
    test('returns only members matching clientId', () async {
      final channelName = testChannelName('RTP11c2');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.sync,
                channel: channelName,
                channelSerial: 'seq1:',
                presence: [
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c1',
                    id: 'c1:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'bob',
                    connectionId: 'c2',
                    id: 'c2:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c3',
                    id: 'c3:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final members = await channel.presence.get(clientId: 'alice');

      // Only alice entries returned (from two different connections)
      expect(members.length, equals(2));
      expect(members.every((m) => m.clientId == 'alice'), isTrue);

      mockWs.dispose();
    });
  });

  group('RTP11c3 - get filtered by connectionId', () {
    // UTS: realtime/unit/RTP11c3/get-filtered-by-connectionid-0
    test('returns only members matching connectionId', () async {
      final channelName = testChannelName('RTP11c3');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.sync,
                channel: channelName,
                channelSerial: 'seq1:',
                presence: [
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c1',
                    id: 'c1:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'bob',
                    connectionId: 'c2',
                    id: 'c2:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'carol',
                    connectionId: 'c1',
                    id: 'c1:0:1',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final members = await channel.presence.get(connectionId: 'c1');

      // Only members from connection c1 (alice and carol)
      expect(members.length, equals(2));
      expect(members.every((m) => m.connectionId == 'c1'), isTrue);

      mockWs.dispose();
    });
  });

  group('RTP11b - get implicitly attaches channel', () {
    // UTS: realtime/unit/RTP11b/get-implicitly-attaches-0
    test('attaches INITIALIZED channel before returning', () async {
      final channelName = testChannelName('RTP11b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      expect(channel.state, equals(ChannelState.initialized));

      final members = await channel.presence.get(waitForSync: false);

      expect(channel.state, equals(ChannelState.attached));
      expect(members, isNotNull);

      mockWs.dispose();
    });
  });

  group('RTP11d - get on SUSPENDED channel', () {
    // UTS: realtime/unit/RTP11d/get-suspended-errors-default-0
    test('errors by default (waitForSync=true)', () async {
      final channelName = testChannelName('RTP11d');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
            // Complete sync so members are stored
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.sync,
                channel: channelName,
                channelSerial: 'seq1:',
                presence: [
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c1',
                    id: 'c1:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Verify sync completed and member is present
      final beforeMembers = await channel.presence.get(waitForSync: false);
      expect(beforeMembers.length, equals(1));

      // Transition channel to SUSPENDED
      (channel as RealtimeChannelImpl).handleConnectionSuspended(
        const ErrorInfo(code: 80002, message: 'Connection suspended'),
      );
      expect(channel.state, equals(ChannelState.suspended));

      // Default get (waitForSync=true) should error
      expect(
        () => channel.presence.get(),
        throwsA(
          isA<AblyException>().having(
            (e) => e.errorInfo?.code,
            'code',
            equals(91005),
          ),
        ),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTP11d/get-suspended-no-wait-returns-1
    test('waitForSync=false returns available members', () async {
      final channelName = testChannelName('RTP11d-nowait');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.sync,
                channel: channelName,
                channelSerial: 'seq1:',
                presence: [
                  PresenceMessage(
                    action: PresenceAction.present,
                    clientId: 'alice',
                    connectionId: 'c1',
                    id: 'c1:0:0',
                    timestamp: DateTime.fromMillisecondsSinceEpoch(100),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Transition channel to SUSPENDED
      (channel as RealtimeChannelImpl).handleConnectionSuspended(
        const ErrorInfo(code: 80002, message: 'Connection suspended'),
      );
      expect(channel.state, equals(ChannelState.suspended));

      // waitForSync=false returns what's in the PresenceMap
      final members = await channel.presence.get(waitForSync: false);

      expect(members.length, equals(1));
      expect(members[0].clientId, equals('alice'));

      mockWs.dispose();
    });
  });
}

/// Waits for the connection to reach the target state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState,
) async {
  if (connection.state == targetState) return;
  await connection.on().firstWhere((change) => change.current == targetState);
  // Defer to event queue to avoid re-entrant issues
  await Future<void>.delayed(Duration.zero);
}

import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:ably_pubsub_device/src/impl/realtime_channel_impl.dart';
import 'package:ably_pubsub_device/src/impl/realtime_presence_impl.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence channel state interactions
/// (RTP1, RTP5, RTP5a, RTP5b, RTP5f, RTP13, RTP19a, RTL9, RTL11).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_channel_state.md
void main() {
  group('RTP1 - HAS_PRESENCE flag triggers sync', () {
    // UTS: realtime/unit/RTP1/has-presence-triggers-sync-0
    test('SYNC populates presence map', () async {
      final channelName = testChannelName('RTP1');

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

      final members = await channel.presence.get();

      expect(members.length, equals(1));
      expect(members[0].clientId, equals('alice'));
      expect(channel.presence.syncComplete, isTrue);

      mockWs.dispose();
    });
  });

  group('RTP1 - No HAS_PRESENCE flag means empty presence', () {
    // UTS: realtime/unit/RTP1/no-has-presence-empty-1
    test('syncComplete is immediately true with empty map', () async {
      final channelName = testChannelName('RTP1-empty');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // No HAS_PRESENCE flag
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
      await channel.attach();

      final members = await channel.presence.get();

      expect(members.length, equals(0));
      expect(channel.presence.syncComplete, isTrue);

      mockWs.dispose();
    });
  });

  group('RTP19a - No HAS_PRESENCE clears existing members', () {
    // UTS: realtime/unit/RTP1/no-has-presence-clears-existing-2
    test('emits LEAVE for each existing member', () async {
      final channelName = testChannelName('RTP19a');

      var attachCount = 0;
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            if (attachCount == 1) {
              // First attach: has presence with members
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
                  ],
                ),
              );
            } else {
              // Second attach: no HAS_PRESENCE
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
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

      // Verify members exist after first sync
      final members = await channel.presence.get();
      expect(members.length, equals(2));

      // Track LEAVE events
      final leaveEvents = <PresenceMessage>[];
      channel.presence.subscribe(
        (event) => leaveEvents.add(event),
        action: PresenceAction.leave,
      );

      // Simulate disconnect — triggers reconnect and reattach
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Reconnect and reattach (without HAS_PRESENCE this time)
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await _awaitChannelState(channel, ChannelState.attached);

      final membersAfter = await channel.presence.get();

      // All members removed
      expect(membersAfter.length, equals(0));

      // LEAVE events emitted for each member
      expect(leaveEvents.length, equals(2));
      expect(
        leaveEvents.any((e) => e.clientId == 'alice'),
        isTrue,
      );
      expect(
        leaveEvents.any((e) => e.clientId == 'bob'),
        isTrue,
      );

      // LEAVE events have id=null per RTP19a
      expect(leaveEvents.every((e) => e.id == null), isTrue);

      mockWs.dispose();
    });
  });

  group('RTP5a - DETACHED clears both presence maps', () {
    // UTS: realtime/unit/RTP5a/detached-clears-presence-maps-0
    test('no LEAVE events emitted on clear', () async {
      final channelName = testChannelName('RTP5a-detached');

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
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
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

      // Verify member exists
      final members = await channel.presence.get();
      expect(members.length, equals(1));

      // Track events — LEAVE should NOT be emitted on clear
      final leaveEvents = <PresenceMessage>[];
      channel.presence.subscribe(
        (event) {
          leaveEvents.add(event);
        },
        action: PresenceAction.leave,
      );

      // Detach the channel
      await channel.detach();
      expect(channel.state, equals(ChannelState.detached));

      // RTP5a: No LEAVE events emitted when clearing on DETACHED
      expect(leaveEvents.length, equals(0));

      // Presence map is cleared (check directly — get() would trigger
      // implicit reattach per RTP11b since channel is DETACHED)
      expect(
        (channel.presence as RealtimePresenceImpl).members.values().length,
        equals(0),
      );

      mockWs.dispose();
    });
  });

  group('RTP5a - FAILED clears both presence maps', () {
    // UTS: realtime/unit/RTP5a/failed-clears-presence-maps-1
    test('no LEAVE events emitted on channel ERROR', () async {
      final channelName = testChannelName('RTP5a-failed');

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

      final members = await channel.presence.get();
      expect(members.length, equals(1));

      final leaveEvents = <PresenceMessage>[];
      channel.presence.subscribe(
        (event) => leaveEvents.add(event),
        action: PresenceAction.leave,
      );

      // Server sends channel ERROR to put channel in FAILED state
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.error,
          channel: channelName,
          error: const ErrorInfo(code: 90001, message: 'Channel failed'),
        ),
      );

      await _awaitChannelState(channel, ChannelState.failed);

      // RTP5a: No LEAVE events emitted
      expect(leaveEvents.length, equals(0));

      mockWs.dispose();
    });
  });

  group('RTP5b - ATTACHED sends queued presence messages', () {
    // UTS: realtime/unit/RTP5b/attached-sends-queued-presence-0
    test('queued messages sent after attach completes', () async {
      final channelName = testChannelName('RTP5b');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Delay — don't respond immediately
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Start attach — channel goes to ATTACHING
      unawaited(channel.attach());
      await _awaitChannelState(channel, ChannelState.attaching);

      // Queue presence while channel is ATTACHING
      final enterFuture = channel.presence.enter('queued');

      // No presence sent yet
      expect(capturedPresence.length, equals(0));

      // Complete the attach
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      await enterFuture;

      // Queued presence was sent after attach completed
      expect(capturedPresence.length, equals(1));
      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.enter));
      expect(pm.data, equals('queued'));

      mockWs.dispose();
    });
  });

  group('RTP5f - SUSPENDED maintains presence map', () {
    // UTS: realtime/unit/RTP5f/suspended-maintains-presence-map-0
    test('members preserved during SUSPENDED', () async {
      final channelName = testChannelName('RTP5f');

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

      final members = await channel.presence.get();
      expect(members.length, equals(2));

      // Channel becomes SUSPENDED
      (channel as RealtimeChannelImpl).handleConnectionSuspended(
        const ErrorInfo(code: 80002, message: 'Connection suspended'),
      );
      expect(channel.state, equals(ChannelState.suspended));

      // PresenceMap is maintained during SUSPENDED
      final membersDuringSuspended =
          await channel.presence.get(waitForSync: false);

      expect(membersDuringSuspended.length, equals(2));

      mockWs.dispose();
    });
  });

  group('RTP13 - syncComplete attribute', () {
    // UTS: realtime/unit/RTP13/sync-complete-attribute-0
    test('false during sync, true after sync', () async {
      final channelName = testChannelName('RTP13');

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
            // Start multi-message SYNC (cursor is non-empty)
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

      // Sync is in progress — not yet complete
      expect(channel.presence.syncComplete, isFalse);

      // Complete the sync (empty cursor)
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

      expect(channel.presence.syncComplete, isTrue);

      mockWs.dispose();
    });
  });

  group('RTL9, RTL9a - RealtimeChannel#presence attribute', () {
    // UTS: realtime/unit/RTL9/presence-attribute-0
    test('returns RealtimePresence and same instance each time', () {
      final channelName = testChannelName('RTL9a');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (_) {},
      );

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      final presence = channel.presence;
      expect(presence, isA<RealtimePresence>());
      // Same instance returned every time
      expect(identical(channel.presence, channel.presence), isTrue);

      mockWs.dispose();
    });
  });

  group('RTL11 - Queued presence actions fail on state changes', () {
    // UTS: realtime/unit/RTL11/queued-presence-fail-failed-2
    test('fail on FAILED (channel ERROR)', () async {
      final channelName = testChannelName('RTL11-failed');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond — leave channel in ATTACHING
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Start attach — channel goes to ATTACHING
      unawaited(channel.attach().catchError((_) {}));
      await _awaitChannelState(channel, ChannelState.attaching);

      // Queue presence while channel is ATTACHING (per RTP16b)
      Object? enterError;
      unawaited(
        channel.presence.enter('queued-enter').catchError((Object e) {
          enterError = e;
        }),
      );

      // Verify nothing sent yet
      expect(capturedPresence.length, equals(0));

      // Server sends ERROR for this channel — channel goes FAILED
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.error,
          channel: channelName,
          error: const ErrorInfo(code: 90001, message: 'Channel failed'),
        ),
      );

      await _awaitChannelState(channel, ChannelState.failed);
      // Allow error to propagate
      await Future<void>.delayed(Duration.zero);

      // No presence messages were sent
      expect(capturedPresence.length, equals(0));

      // The enter completed with an error
      expect(enterError, isA<AblyException>());

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL11/queued-presence-fail-suspended-1
    test('fail on SUSPENDED (connection suspended)', () async {
      final channelName = testChannelName('RTL11-suspended');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond — leave channel in ATTACHING
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      unawaited(channel.attach().catchError((_) {}));
      await _awaitChannelState(channel, ChannelState.attaching);

      // Queue multiple presence actions
      Object? enterError;
      Object? updateError;
      unawaited(
        channel.presence.enter('queued-enter').catchError((Object e) {
          enterError = e;
        }),
      );
      unawaited(
        channel.presence.update('queued-update').catchError((Object e) {
          updateError = e;
        }),
      );

      expect(capturedPresence.length, equals(0));

      // Channel goes SUSPENDED
      (channel as RealtimeChannelImpl).handleConnectionSuspended(
        const ErrorInfo(code: 80002, message: 'Connection suspended'),
      );
      expect(channel.state, equals(ChannelState.suspended));
      // Allow errors to propagate
      await Future<void>.delayed(Duration.zero);

      // No presence messages were sent
      expect(capturedPresence.length, equals(0));

      // Both queued futures completed with errors
      expect(enterError, isA<AblyException>());
      expect(updateError, isA<AblyException>());

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL11/queued-presence-fail-detached-0
    test('fail on DETACHED (channel detach)', () async {
      final channelName = testChannelName('RTL11-detached');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond -- leave channel in ATTACHING
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Start attach -- channel goes to ATTACHING
      unawaited(channel.attach().catchError((_) {}));
      await _awaitChannelState(channel, ChannelState.attaching);

      // Queue presence while channel is ATTACHING (per RTP16b)
      Object? enterError;
      unawaited(
        channel.presence.enter('queued-enter').catchError((Object e) {
          enterError = e;
        }),
      );

      // Verify nothing sent yet
      expect(capturedPresence.length, equals(0));

      // Server sends DETACHED for this channel -- channel goes DETACHED
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.detached,
          channel: channelName,
        ),
      );

      // Allow the DETACHED processing to propagate
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No presence messages were sent
      expect(capturedPresence.length, equals(0));

      // The enter completed with an error
      expect(enterError, isA<AblyException>());

      mockWs.dispose();
    });
  });

  group('RTL11a - ACK/NACK unaffected by channel state changes', () {
    // UTS: realtime/unit/RTL11a/ack-nack-unaffected-by-state-0
    test('ACK resolves presence after channel detached', () async {
      final channelName = testChannelName('RTL11a');

      final capturedPresence = <ProtocolMessage>[];
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
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            // Do NOT send ACK yet — hold it
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send presence — it goes to the server, but no ACK yet
      var enterCompleted = false;
      final enterFuture = channel.presence.enter('awaiting-ack').then((_) {
        enterCompleted = true;
      });
      expect(capturedPresence.length, equals(1));

      // Detach the channel
      await channel.detach();
      expect(channel.state, equals(ChannelState.detached));

      // Enter has not completed yet (no ACK)
      expect(enterCompleted, isFalse);

      // Now the server sends the ACK
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.ack(
          msgSerial: capturedPresence[0].msgSerial!,
        ),
      );

      // The enter future resolves successfully
      await enterFuture;
      expect(enterCompleted, isTrue);

      mockWs.dispose();
    });
  });
}

/// Creates ClientOptions with a clientId using authCallback to avoid real HTTP.
ClientOptions _optionsWithClientId(String clientId) {
  return ClientOptions(
    authCallback: (params) async => TokenDetails(
      token: 'fake-token-for-testing',
      expires:
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      clientId: clientId,
    ),
    clientId: clientId,
    autoConnect: false,
  );
}

/// Waits for the connection to reach the target state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState,
) async {
  if (connection.state == targetState) return;
  await connection.on().firstWhere((change) => change.current == targetState);
  await Future<void>.delayed(Duration.zero);
}

/// Waits for the channel to reach the target state.
Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState,
) async {
  if (channel.state == targetState) return;
  await channel.on().firstWhere((change) => change.current == targetState);
  await Future<void>.delayed(Duration.zero);
}

/// Decodes the first presence message from a captured ProtocolMessage.
PresenceMessage _decodePresence(ProtocolMessage protocolMessage) {
  final raw = protocolMessage.presence![0];
  if (raw is PresenceMessage) return raw;
  return PresenceMessage.fromMap(raw as Map<String, dynamic>);
}

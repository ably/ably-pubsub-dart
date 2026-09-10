import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence subscribe/unsubscribe (RTP6, RTP7).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_subscribe.md
void main() {
  group('RTP6a - Subscribe to all presence events', () {
    // UTS: realtime/unit/RTP6a/subscribe-all-presence-events-0
    test('receives ENTER, UPDATE, and LEAVE events', () async {
      final channelName = testChannelName('RTP6a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final receivedEvents = <PresenceMessage>[];
      channel.presence.subscribe((event) {
        receivedEvents.add(event);
      });

      await _awaitChannelState(channel, ChannelState.attached);

      // Server delivers ENTER, UPDATE, and LEAVE events
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        ),
      );

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.update,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:1:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
              data: 'updated',
            ),
          ],
        ),
      );

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.leave,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:2:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
            ),
          ],
        ),
      );

      expect(receivedEvents.length, equals(3));
      expect(receivedEvents[0].action, equals(PresenceAction.enter));
      expect(receivedEvents[0].clientId, equals('alice'));
      expect(receivedEvents[1].action, equals(PresenceAction.update));
      expect(receivedEvents[1].data, equals('updated'));
      expect(receivedEvents[2].action, equals(PresenceAction.leave));

      mockWs.dispose();
    });
  });

  group('RTP6b - Subscribe filtered by action', () {
    // UTS: realtime/unit/RTP6b/subscribe-filtered-by-action-0
    test('single action filter receives only matching events', () async {
      final channelName = testChannelName('RTP6b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final enterEvents = <PresenceMessage>[];
      final leaveEvents = <PresenceMessage>[];

      channel.presence.subscribe(
        (event) => enterEvents.add(event),
        action: PresenceAction.enter,
      );
      channel.presence.subscribe(
        (event) => leaveEvents.add(event),
        action: PresenceAction.leave,
      );

      // Server delivers all three action types in one ProtocolMessage
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            PresenceMessage(
              action: PresenceAction.update,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:1:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            ),
            PresenceMessage(
              action: PresenceAction.leave,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:2:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
            ),
          ],
        ),
      );

      // ENTER listener only gets ENTER events
      expect(enterEvents.length, equals(1));
      expect(enterEvents[0].action, equals(PresenceAction.enter));

      // LEAVE listener only gets LEAVE events
      expect(leaveEvents.length, equals(1));
      expect(leaveEvents[0].action, equals(PresenceAction.leave));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTP6b/subscribe-filtered-multiple-actions-1
    test('multiple action filter receives matching events', () async {
      final channelName = testChannelName('RTP6b-multi');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final enterLeaveEvents = <PresenceMessage>[];
      channel.presence.subscribe(
        (event) => enterLeaveEvents.add(event),
        actions: [PresenceAction.enter, PresenceAction.leave],
      );

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            PresenceMessage(
              action: PresenceAction.update,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:1:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            ),
            PresenceMessage(
              action: PresenceAction.leave,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:2:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
            ),
          ],
        ),
      );

      // Only ENTER and LEAVE events received — UPDATE filtered out
      expect(enterLeaveEvents.length, equals(2));
      expect(enterLeaveEvents[0].action, equals(PresenceAction.enter));
      expect(enterLeaveEvents[1].action, equals(PresenceAction.leave));

      mockWs.dispose();
    });
  });

  group('RTP6d - Subscribe implicitly attaches channel', () {
    // UTS: realtime/unit/RTP6d/subscribe-implicitly-attaches-0
    test('channel attaches when subscribe is called', () async {
      final channelName = testChannelName('RTP6d');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      // Subscribe without explicitly attaching — should trigger implicit attach
      channel.presence.subscribe((event) {});

      await _awaitChannelState(channel, ChannelState.attached);

      expect(attachCount, equals(1));
      expect(channel.state, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTP6e - Subscribe with attachOnSubscribe=false does not attach', () {
    // UTS: realtime/unit/RTP6e/subscribe-no-attach-option-0
    test('channel stays in INITIALIZED', () async {
      final channelName = testChannelName('RTP6e');
      var attachCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      // Subscribe with attachOnSubscribe=false
      channel.presence.subscribe(
        (event) {},
        attachOnSubscribe: false,
      );

      // Give time for any implicit attach to happen (it shouldn't)
      await _pumpEventQueue();

      // Channel stays in INITIALIZED — no implicit attach
      expect(channel.state, equals(ChannelState.initialized));
      expect(attachCount, equals(0));

      mockWs.dispose();
    });
  });

  group('RTP7c - Unsubscribe all listeners', () {
    // UTS: realtime/unit/RTP7c/unsubscribe-all-listeners-0
    test('no listeners receive events after unsubscribe()', () async {
      final channelName = testChannelName('RTP7c');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final eventsA = <PresenceMessage>[];
      final eventsB = <PresenceMessage>[];

      channel.presence.subscribe((event) => eventsA.add(event));
      channel.presence.subscribe((event) => eventsB.add(event));

      // Deliver first event — both listeners receive it
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        ),
      );

      expect(eventsA.length, equals(1));
      expect(eventsB.length, equals(1));

      // Unsubscribe all
      channel.presence.unsubscribe();

      // Deliver second event — no listeners receive it
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'bob',
              connectionId: 'c2',
              id: 'c2:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            ),
          ],
        ),
      );

      expect(eventsA.length, equals(1)); // No new events after unsubscribe
      expect(eventsB.length, equals(1));

      mockWs.dispose();
    });
  });

  group('RTP7a - Unsubscribe specific listener', () {
    // UTS: realtime/unit/RTP7a/unsubscribe-specific-listener-0
    test('only the unsubscribed listener stops receiving', () async {
      final channelName = testChannelName('RTP7a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final eventsA = <PresenceMessage>[];
      final eventsB = <PresenceMessage>[];

      void listenerA(PresenceMessage event) => eventsA.add(event);
      void listenerB(PresenceMessage event) => eventsB.add(event);

      channel.presence.subscribe(listenerA);
      channel.presence.subscribe(listenerB);

      // Unsubscribe only listenerA
      channel.presence.unsubscribe(listener: listenerA);

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        ),
      );

      expect(eventsA.length, equals(0)); // Unsubscribed — no events
      expect(eventsB.length, equals(1)); // Still subscribed — receives event

      mockWs.dispose();
    });
  });

  group('RTP7b - Unsubscribe listener for specific action', () {
    // UTS: realtime/unit/RTP7b/unsubscribe-for-specific-action-0
    test('unsubscribes only the action-specific subscription', () async {
      final channelName = testChannelName('RTP7b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final received = <PresenceMessage>[];
      void listener(PresenceMessage event) => received.add(event);

      // Subscribe to both ENTER and LEAVE
      channel.presence.subscribe(listener, action: PresenceAction.enter);
      channel.presence.subscribe(listener, action: PresenceAction.leave);

      // Unsubscribe only for ENTER
      channel.presence.unsubscribe(
        listener: listener,
        action: PresenceAction.enter,
      );

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            PresenceMessage(
              action: PresenceAction.leave,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:1:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
            ),
          ],
        ),
      );

      // Only LEAVE received — ENTER subscription was removed
      expect(received.length, equals(1));
      expect(received[0].action, equals(PresenceAction.leave));

      mockWs.dispose();
    });
  });

  group('RTP6 - Presence events update the PresenceMap', () {
    // UTS: realtime/unit/RTP6/presence-events-update-map-0
    test('members are stored as PRESENT after ENTER', () async {
      final channelName = testChannelName('RTP6-map');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      channel.presence.subscribe((event) {});

      // Server delivers ENTER
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
              data: 'hello',
            ),
          ],
        ),
      );

      final members = await channel.presence.get(waitForSync: false);

      expect(members.length, equals(1));
      expect(members[0].clientId, equals('alice'));
      expect(members[0].data, equals('hello'));
      expect(members[0].action, equals(PresenceAction.present)); // RTP2d2
      mockWs.dispose();
    });
  });

  group('RTP6 - Multiple presence messages in single ProtocolMessage', () {
    // UTS: realtime/unit/RTP6/multiple-presence-in-single-message-1
    test('all messages delivered to subscribers', () async {
      final channelName = testChannelName('RTP6-batch');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
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

      final received = <PresenceMessage>[];
      channel.presence.subscribe((event) => received.add(event));

      // Server delivers multiple presence events in one ProtocolMessage
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.presence,
          channel: channelName,
          presence: [
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'alice',
              connectionId: 'c1',
              id: 'c1:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'bob',
              connectionId: 'c2',
              id: 'c2:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            PresenceMessage(
              action: PresenceAction.enter,
              clientId: 'carol',
              connectionId: 'c3',
              id: 'c3:0:0',
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        ),
      );

      expect(received.length, equals(3));
      expect(received[0].clientId, equals('alice'));
      expect(received[1].clientId, equals('bob'));
      expect(received[2].clientId, equals('carol'));

      mockWs.dispose();
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) return;
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

/// Waits for channel to reach the specified state.
Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (channel.state == targetState) return;
  await channel
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel#whenState (RTL25).
///
/// These tests verify the whenState convenience function that calls
/// listeners immediately if already in state, or waits for the state.
/// Mirrors the Connection#whenState tests (RTN26).
///
/// Spec: uts/test/realtime/unit/channels/channel_when_state_test.md
void main() {
  group('RTL25a - whenState calls listener immediately if already in state',
      () {
    // UTS: realtime/unit/RTL25a/resolves-immediately-current-0
    test('invokes callback immediately with null when already in target state',
        () async {
      final channelName = testChannelName('RTL25a-immediate');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      // Channel is now ATTACHED — call whenState for current state
      var callbackInvoked = false;
      ChannelStateChange? callbackArg;

      channel.whenState(ChannelState.attached, (change) {
        callbackInvoked = true;
        callbackArg = change;
      });

      // Callback should be invoked immediately
      await Future<void>.delayed(Duration.zero);

      expect(callbackInvoked, isTrue);
      // RTL25a: callback invoked with null argument
      expect(callbackArg, isNull);

      mockWs.dispose();
    });
  });

  group('RTL25b - whenState waits for state if not already in it', () {
    // UTS: realtime/unit/RTL25b/waits-for-state-change-0
    test('waits for state transition when not currently in target state',
        () async {
      final channelName = testChannelName('RTL25b-deferred');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      // Channel is in INITIALIZED state — register whenState for ATTACHED
      var callbackInvoked = false;
      ChannelStateChange? callbackArg;

      channel.whenState(ChannelState.attached, (change) {
        callbackInvoked = true;
        callbackArg = change;
      });

      // Callback should not be invoked yet
      expect(callbackInvoked, isFalse);

      // Attach the channel
      await channel.attach();

      // Give callback a moment to execute
      await Future<void>.delayed(Duration.zero);

      // Callback was invoked after state transition
      expect(callbackInvoked, isTrue);

      // Callback was invoked with a ChannelStateChange object (not null)
      expect(callbackArg, isNotNull);
      expect(callbackArg!.current, equals(ChannelState.attached));
      expect(
        callbackArg!.previous,
        anyOf(
          equals(ChannelState.initialized),
          equals(ChannelState.attaching),
        ),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL25b/fires-once-only-1
    test('whenState only fires once', () async {
      final channelName = testChannelName('RTL25b-once');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
          if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
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

      // Register whenState for ATTACHED
      var callbackCount = 0;

      channel.whenState(ChannelState.attached, (change) {
        callbackCount++;
      });

      // First attach
      await channel.attach();
      await Future<void>.delayed(Duration.zero);

      // Verify callback was invoked once
      expect(callbackCount, equals(1));

      // Detach
      await channel.detach();

      // Second attach
      await channel.attach();
      await Future<void>.delayed(Duration.zero);

      // Callback was still only invoked once (not again on second attach)
      expect(callbackCount, equals(1));

      mockWs.dispose();
    });
  });

  group('RTL25a - whenState for past state does not fire', () {
    // UTS: realtime/unit/RTL25a/past-state-does-not-resolve-1
    test('callback not invoked for a state that was previously visited',
        () async {
      final channelName = testChannelName('RTL25a-past');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      // Attach — channel passes through ATTACHING to reach ATTACHED
      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Now call whenState for ATTACHING — a past state, not the current one
      var callbackInvoked = false;

      channel.whenState(ChannelState.attaching, (change) {
        callbackInvoked = true;
      });

      // Wait to see if callback is invoked
      await Future<void>.delayed(Duration.zero);

      // Callback should NOT be invoked
      expect(callbackInvoked, isFalse);

      mockWs.dispose();
    });
  });
}

Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) {
    return;
  }
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RTS4/RTS4a release() on a FAILED channel, and for the
/// state-change controller being closed on release.
void main() {
  late RealtimeClient client;
  late MockWebSocketClient mockWs;

  setUp(() {
    mockWs = MockWebSocketClient(
      onConnectionAttempt: (conn) {
        conn.respondWithSuccess(ProtocolMessageHelpers.connected());
      },
      onMessageFromClient: (msg) {
        if (msg.action == ProtocolAction.attach) {
          mockWs.activeConnection!.sendToClient(
            ProtocolMessageHelpers.attached(channel: msg.channel!),
          );
        } else if (msg.action == ProtocolAction.detach) {
          mockWs.activeConnection!.sendToClient(
            ProtocolMessageHelpers.detached(channel: msg.channel!),
          );
        }
      },
    );

    client = RealtimeClient.forTesting(
      options: ClientOptions(key: 'appId.keyId:keySecret', autoConnect: false),
      webSocketClient: mockWs,
    );
  });

  tearDown(() {
    mockWs.dispose();
  });

  group('RTS4a - release() on a FAILED channel', () {
    test('does not throw and removes the channel from the collection',
        () async {
      final channelName = testChannelName('RTS4a-failed');
      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      // RTL14: channel-scoped ERROR drives the channel to FAILED, from which
      // detach() raises 90001 (RTL5b).
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 40160,
          statusCode: 401,
          message: 'Not permitted',
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.failed);
      expect(channel.state, equals(ChannelState.failed));

      await client.channels.release(channelName);

      expect(client.channels.exists(channelName), isFalse);
      expect(client.channels.names, isNot(contains(channelName)));
    });
  });

  group('RTS4a - release() disposes the channel state-change controller', () {
    test('the state-change stream is closed after release', () async {
      final channelName = testChannelName('RTS4a-dispose');
      final channel = client.channels.get(channelName);

      // channel.on() with no event returns _stateChangeController.stream
      // directly, so isEmpty completing at all proves the controller was
      // closed. On a leaked controller it never completes.
      final stateStream = channel.on();

      await client.channels.release(channelName);

      await expectLater(
        stateStream.isEmpty.timeout(const Duration(seconds: 3)),
        completion(isTrue),
      );
    });
  });

  group('RTS4a - release() is idempotent', () {
    test('a second release() on the same name is a no-op', () async {
      final channelName = testChannelName('RTS4a-idempotent');
      client.channels.get(channelName);

      await client.channels.release(channelName);
      await client.channels.release(channelName);

      expect(client.channels.exists(channelName), isFalse);
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

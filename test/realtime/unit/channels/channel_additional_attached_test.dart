import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for additional ATTACHED message handling (RTL12).
///
/// These tests verify that an additional ATTACHED ProtocolMessage received
/// on an already-attached channel correctly emits (or suppresses) an UPDATE
/// event based on the RESUMED flag.
///
/// Spec: uts/test/realtime/unit/channels/channel_additional_attached.md
void main() {
  group('RTL12 - Additional ATTACHED with resumed=false emits UPDATE', () {
    // UTS: realtime/unit/RTL12/update-emits-with-error-0
    test('emits UPDATE with error reason when ATTACHED has no RESUMED flag',
        () async {
      final channelName = testChannelName('RTL12-update');

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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      final updateEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.update).listen(updateEvents.add);

      // Server sends additional ATTACHED without RESUMED flag, with an error
      // (e.g., loss of message continuity after transport resume)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.attached,
          channel: channelName,
          error: const ErrorInfo(
            code: 50000,
            statusCode: 500,
            message: 'generic serverside failure',
          ),
        ),
      );

      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.attached));
      expect(updateEvents.length, equals(1));
      expect(updateEvents[0].event, equals(ChannelEvent.update));
      expect(updateEvents[0].current, equals(ChannelState.attached));
      expect(updateEvents[0].previous, equals(ChannelState.attached));
      expect(updateEvents[0].resumed, isFalse);
      expect(updateEvents[0].reason?.code, equals(50000));

      mockWs.dispose();
    });
  });

  group('RTL12 - Additional ATTACHED with resumed=true does NOT emit UPDATE',
      () {
    // UTS: realtime/unit/RTL12/resumed-no-update-1
    test('no UPDATE event when ATTACHED has RESUMED flag', () async {
      final channelName = testChannelName('RTL12-no-update');

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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      final updateEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.update).listen(updateEvents.add);

      // Server sends additional ATTACHED WITH RESUMED flag
      // This indicates successful resume with no loss of continuity
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: channelName,
          flags: flagResumed,
        ),
      );

      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.attached));
      expect(updateEvents.length, equals(0));

      mockWs.dispose();
    });
  });

  group('RTL12 - Additional ATTACHED without error has null reason', () {
    // UTS: realtime/unit/RTL12/no-error-null-reason-2
    test('UPDATE event reason is null when ATTACHED has no error', () async {
      final channelName = testChannelName('RTL12-no-error');

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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      final updateEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.update).listen(updateEvents.add);

      // Server sends additional ATTACHED without RESUMED flag and without error
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.attached));
      expect(updateEvents.length, equals(1));
      expect(updateEvents[0].resumed, isFalse);
      expect(updateEvents[0].reason, isNull);

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

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

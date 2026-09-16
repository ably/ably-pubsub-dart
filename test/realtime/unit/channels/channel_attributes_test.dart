import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel attributes (RTL23, RTL24).
///
/// Tests the channel name attribute and errorReason lifecycle across
/// various channel state transitions.
///
/// Spec: uts/test/realtime/unit/channels/channel_attributes.md
void main() {
  group('RTL23 - RealtimeChannel name attribute', () {
    // UTS: realtime/unit/RTL23/name-attribute-0
    test('returns the name used when getting the channel', () {
      final client = PubSubClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      final channel = client.channels.get('my-channel');
      expect(channel.name, equals('my-channel'));

      // Also works with special characters
      final channel2 = client.channels.get('namespace:channel-name');
      expect(channel2.name, equals('namespace:channel-name'));
    });
  });

  group('RTL24 - errorReason set on channel error', () {
    // UTS: realtime/unit/RTL24/error-reason-channel-error-0
    test('errorReason is populated when channel receives ERROR', () async {
      final channelName = testChannelName('RTL24-error');

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

      final client = PubSubClient.forTesting(
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

      // Verify errorReason is initially null
      expect(channel.errorReason, isNull);

      // Send an ERROR ProtocolMessage for this channel
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 90001,
          message: 'Channel error occurred',
          statusCode: 500,
          channel: channelName,
        ),
      );

      await _awaitChannelState(channel, ChannelState.failed);

      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(90001));
      expect(channel.errorReason!.statusCode, equals(500));

      mockWs.dispose();
    });
  });

  group('RTL24 - errorReason set on attach failure', () {
    // UTS: realtime/unit/RTL24/error-reason-attach-failure-1
    test('errorReason is populated when attach is rejected', () async {
      final channelName = testChannelName('RTL24-attach-fail');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Reject attach with DETACHED + error
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.detached,
                channel: channelName,
                error: const ErrorInfo(
                  code: 40160,
                  message: 'Permission denied',
                  statusCode: 401,
                ),
              ),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Attach should fail
      try {
        await channel.attach();
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      // errorReason is set from the DETACHED response error
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));
      expect(channel.errorReason!.statusCode, equals(401));

      mockWs.dispose();
    });
  });

  group('RTL4c/RTL24 - errorReason cleared on successful attach', () {
    // UTS: realtime/unit/RTL4c/error-cleared-on-attach-0
    test('errorReason is null after successful attach following error',
        () async {
      final channelName = testChannelName('RTL24-clear-attach');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            if (attachCount == 1) {
              // First attach: reject
              mockWs.activeConnection!.sendToClient(
                ProtocolMessage(
                  action: ProtocolAction.detached,
                  channel: channelName,
                  error: const ErrorInfo(
                    code: 50000,
                    message: 'Temporary error',
                    statusCode: 500,
                  ),
                ),
              );
            } else {
              // Second attach: succeed
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // First attach fails — errorReason set
      try {
        await channel.attach();
        fail('Expected AblyException');
      } catch (e) {
        // expected
      }
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(50000));

      // Second attach succeeds — errorReason cleared
      await channel.attach();

      expect(channel.state, equals(ChannelState.attached));
      expect(channel.errorReason, isNull);

      mockWs.dispose();
    });
  });

  group(
      'RTL4c/RTL24 - errorReason cleared on successful attach, preserved through detach',
      () {
    // UTS: realtime/unit/RTL4c/error-cleared-preserved-detach-1
    test('errorReason cleared by reattach, stays null through detach',
        () async {
      final channelName = testChannelName('RTL24-clear-detach');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            if (attachCount == 1) {
              // First attach: succeed, then send ERROR to set errorReason
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else {
              // Second attach (after FAILED): succeed
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
          }
          if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
            );
          }
        },
      );

      final client = PubSubClient.forTesting(
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

      // Send channel ERROR — transitions to FAILED, sets errorReason
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 90002,
          message: 'Channel error',
          statusCode: 500,
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.failed);
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(90002));

      // Reattach — succeeds, then detach
      await channel.attach();
      expect(channel.errorReason, isNull);

      // Now detach — errorReason stays null
      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(channel.errorReason, isNull);

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

Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (channel.state == targetState) {
    return;
  }
  await channel
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

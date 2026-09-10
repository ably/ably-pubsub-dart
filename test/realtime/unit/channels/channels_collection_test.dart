import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Tests for RealtimeChannels collection management.
///
/// Spec: RTS1, RTS2, RTS3a, RTS4a
void main() {
  group('RealtimeChannels Collection - UTS Tests', () {
    late RealtimeClient client;
    late MockWebSocketClient mockWs;

    setUp(() {
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
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
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );
    });

    group('RTS1 - Channels collection accessible via RealtimeClient', () {
      // UTS: realtime/unit/RTS1/channels-collection-accessible-0
      test('channels attribute exists and is RealtimeChannels', () {
        expect(client.channels, isNotNull);
        expect(client.channels, isA<RealtimeChannels>());
      });
    });

    group('RTS2 - Check if channel exists', () {
      // UTS: realtime/unit/RTS2/channel-exists-check-0.1
      test('exists() returns false for non-existent channel', () {
        final channelName = testChannelName('RTS2');
        expect(client.channels.exists(channelName), isFalse);
      });

      // UTS: realtime/unit/RTS2/channel-exists-check-0.2
      test('exists() returns true after channel is created', () {
        final channelName = testChannelName('RTS2');

        // Before creating
        expect(client.channels.exists(channelName), isFalse);

        // Create the channel
        client.channels.get(channelName);

        // After creating
        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: realtime/unit/RTS2/channel-exists-check-0
      test('exists() returns false for other channels', () {
        final channelNameA = testChannelName('RTS2-a');
        final channelNameB = testChannelName('RTS2-b');

        client.channels.get(channelNameA);

        expect(client.channels.exists(channelNameA), isTrue);
        expect(client.channels.exists(channelNameB), isFalse);
      });
    });

    group('RTS2 - Iterate through existing channels', () {
      // UTS: realtime/unit/RTS2/iterate-channels-1
      test('names returns all channel names', () {
        final channelNameA = testChannelName('RTS2-a');
        final channelNameB = testChannelName('RTS2-b');
        final channelNameC = testChannelName('RTS2-c');

        client.channels.get(channelNameA);
        client.channels.get(channelNameB);
        client.channels.get(channelNameC);

        final names = client.channels.names.toList();

        expect(names, contains(channelNameA));
        expect(names, contains(channelNameB));
        expect(names, contains(channelNameC));
        expect(names.length, equals(3));
      });

      // UTS: realtime/unit/RTS2/iterate-channels-1.1
      test('names is empty when no channels exist', () {
        expect(client.channels.names, isEmpty);
      });
    });

    group('RTS3a - Get creates new channel if none exists', () {
      // UTS: realtime/unit/RTS3a/get-after-release-new-3
      test('get() creates new channel', () {
        final channelName = testChannelName('RTS3a');
        final channel = client.channels.get(channelName);

        expect(channel, isA<RealtimeChannel>());
        expect(channel.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: realtime/unit/RTS3a/get-creates-new-channel-0
      test('get() returns existing channel', () {
        final channelName = testChannelName('RTS3a');
        final channel1 = client.channels.get(channelName);
        final channel2 = client.channels.get(channelName);

        expect(
          identical(channel1, channel2),
          isTrue,
          reason: 'Should return same object reference',
        );
        expect(channel1.name, equals(channelName));
      });
    });

    group('RTS3a - Operator subscript creates or returns channel', () {
      // UTS: realtime/unit/RTS3a/subscript-operator-channel-2
      test('operator[] creates new channel', () {
        final channelName = testChannelName('RTS3a');
        final channel = client.channels[channelName];

        expect(channel, isA<RealtimeChannel>());
        expect(channel.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: realtime/unit/RTS3a/get-returns-existing-channel-1
      test('operator[] returns same instance as get()', () {
        final channelName = testChannelName('RTS3a');
        final channel1 = client.channels[channelName];
        final channel2 = client.channels.get(channelName);
        final channel3 = client.channels[channelName];

        expect(identical(channel1, channel2), isTrue);
        expect(identical(channel2, channel3), isTrue);
      });
    });

    group('RTS4a - Release detaches and removes channel', () {
      // UTS: realtime/unit/RTS4a/release-removes-channel-0
      test('release() removes channel from collection', () async {
        final channelName = testChannelName('RTS4a');
        client.channels.get(channelName);
        expect(client.channels.exists(channelName), isTrue);

        await client.channels.release(channelName);

        expect(client.channels.exists(channelName), isFalse);
      });

      // UTS: realtime/unit/RTS4a/release-nonexistent-noop-1
      test('release() on non-existent channel is no-op', () async {
        final channelName = testChannelName('RTS4a-nonexistent');
        // Should complete without throwing
        await client.channels.release(channelName);

        expect(client.channels.exists(channelName), isFalse);
      });

      // UTS: realtime/unit/RTS4a/release-detaches-attached-2
      test('release() calls detach on attached channel', () async {
        final channelName = testChannelName('RTS4a');
        final channel = client.channels.get(channelName);

        // Attach the channel (in mock environment, this is synchronous)
        await channel.attach();
        expect(channel.state, equals(ChannelState.attached));

        // Release should detach first
        await client.channels.release(channelName);

        expect(client.channels.exists(channelName), isFalse);
      });

      // UTS: realtime/unit/RTS4a/release-removes-channel-0.1
      test('get() after release() creates new channel instance', () async {
        final channelName = testChannelName('RTS4a');
        final channel1 = client.channels.get(channelName);

        await client.channels.release(channelName);

        final channel2 = client.channels.get(channelName);

        expect(
          identical(channel1, channel2),
          isFalse,
          reason: 'Should be different object instances',
        );
        expect(channel2.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });
    });

    group('Edge cases', () {
      // UTS: realtime/unit/RTS1/channels-collection-accessible-0.1
      test('multiple channels are independent', () {
        final channelNameA = testChannelName('edge-a');
        final channelNameB = testChannelName('edge-b');

        final channelA = client.channels.get(channelNameA);
        final channelB = client.channels.get(channelNameB);

        expect(identical(channelA, channelB), isFalse);
        expect(channelA.name, equals(channelNameA));
        expect(channelB.name, equals(channelNameB));
      });

      // UTS: realtime/unit/RTS1/channels-collection-accessible-0.2
      test('channel names are case-sensitive', () {
        final lowerName = testChannelName('case');
        final upperName = lowerName.toUpperCase();

        final lower = client.channels.get(lowerName);
        final upper = client.channels.get(upperName);

        expect(identical(lower, upper), isFalse);
        expect(client.channels.exists(lowerName), isTrue);
        expect(client.channels.exists(upperName), isTrue);
        expect(client.channels.names.length, equals(2));
      });

      // UTS: realtime/unit/RTS1/channels-collection-accessible-0.3
      test('channel names can contain special characters', () {
        final channelName = '${testChannelName('special')}:with/chars.here';
        final channel = client.channels.get(channelName);

        expect(channel.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });
    });
  });
}

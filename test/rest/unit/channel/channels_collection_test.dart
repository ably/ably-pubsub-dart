import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/test_channel_name.dart';

/// Tests for RestChannels collection management.
///
/// Spec: RSN1, RSN2, RSN3a, RSN3b, RSN3c, RSN4a, RSN4b
void main() {
  group('RestChannels Collection', () {
    late RestClient client;

    setUp(() {
      client = RestClient(
        options: ClientOptions(key: 'appId.keyId:keySecret'),
      );
    });

    group('RSN1 - Channels collection accessible via RestClient', () {
      // UTS: rest/unit/RSN1/channels-collection-accessible-0
      test('channels attribute exists and is RestChannels', () {
        expect(client.channels, isNotNull);
        expect(client.channels, isA<RestChannels>());
      });
    });

    group('RSN2 - Check if channel exists', () {
      // UTS: rest/unit/RSN2/check-channel-exists-0.1
      test('exists() returns false for non-existent channel', () {
        final channelName = testChannelName('RSN2');
        expect(client.channels.exists(channelName), isFalse);
      });

      // UTS: rest/unit/RSN2/check-channel-exists-0.2
      test('exists() returns true after channel is created', () {
        final channelName = testChannelName('RSN2');

        expect(client.channels.exists(channelName), isFalse);

        client.channels.get(channelName);

        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: rest/unit/RSN2/check-channel-exists-0
      test('exists() returns false for other channels', () {
        final channelName = testChannelName('RSN2-a');
        final otherName = testChannelName('RSN2-b');

        client.channels.get(channelName);

        expect(client.channels.exists(channelName), isTrue);
        expect(client.channels.exists(otherName), isFalse);
      });
    });

    group('RSN2 - Iterate through existing channels', () {
      // UTS: rest/unit/RSN2/iterate-channels-1
      test('iterating yields all channels', () {
        final nameA = testChannelName('RSN2-a');
        final nameB = testChannelName('RSN2-b');
        final nameC = testChannelName('RSN2-c');

        client.channels.get(nameA);
        client.channels.get(nameB);
        client.channels.get(nameC);

        final names = client.channels.map((ch) => ch.name).toList();

        expect(names, contains(nameA));
        expect(names, contains(nameB));
        expect(names, contains(nameC));
        expect(names.length, equals(3));
      });

      // UTS: rest/unit/RSN2/iterate-channels-1.1
      test('iterating empty collection yields nothing', () {
        expect(client.channels.toList(), isEmpty);
      });
    });

    group('RSN3a - Get creates new channel if none exists', () {
      // UTS: rest/unit/RSN3a/get-creates-new-channel-0.1
      test('get() creates new channel', () {
        final channelName = testChannelName('RSN3a');
        final channel = client.channels.get(channelName);

        expect(channel, isA<RestChannel>());
        expect(channel.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: rest/unit/RSN3a/get-creates-new-channel-0
      test('get() returns existing channel', () {
        final channelName = testChannelName('RSN3a');
        final channel1 = client.channels.get(channelName);
        final channel2 = client.channels.get(channelName);

        expect(
          identical(channel1, channel2),
          isTrue,
          reason: 'Should return same object reference',
        );
      });
    });

    group('RSN3a - Operator subscript creates or returns channel', () {
      // UTS: rest/unit/RSN3a/subscript-creates-or-returns-2
      test('operator[] creates new channel', () {
        final channelName = testChannelName('RSN3a');
        final channel = client.channels[channelName];

        expect(channel, isA<RestChannel>());
        expect(channel.name, equals(channelName));
        expect(client.channels.exists(channelName), isTrue);
      });

      // UTS: rest/unit/RSN3a/get-returns-existing-channel-1
      test('operator[] returns same instance as get()', () {
        final channelName = testChannelName('RSN3a');
        final channel1 = client.channels[channelName];
        final channel2 = client.channels.get(channelName);
        final channel3 = client.channels[channelName];

        expect(identical(channel1, channel2), isTrue);
        expect(identical(channel2, channel3), isTrue);
      });
    });

    group('RSN4a - Release removes channel', () {
      // UTS: rest/unit/RSN4a/release-removes-channel-0
      test('release() removes channel from collection', () {
        final channelName = testChannelName('RSN4a');
        client.channels.get(channelName);
        expect(client.channels.exists(channelName), isTrue);

        client.channels.release(channelName);

        expect(client.channels.exists(channelName), isFalse);
      });
    });

    group('RSN4b - Release on non-existent channel is no-op', () {
      // UTS: rest/unit/RSN4b/release-nonexistent-noop-0
      test('release() with unknown name does not throw', () {
        final channelName = testChannelName('RSN4b');

        // Should complete without throwing
        client.channels.release(channelName);

        expect(client.channels.exists(channelName), isFalse);
      });
    });

    group('RSN3a - Get after release creates new channel', () {
      // UTS: rest/unit/RSN3a/get-after-release-new-instance-3
      test('get() after release() returns new instance', () {
        final channelName = testChannelName('RSN3a-release');
        final channel1 = client.channels.get(channelName);

        client.channels.release(channelName);

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
  });
}

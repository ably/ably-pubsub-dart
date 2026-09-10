import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Tests for ChannelOptions and derived channels.
///
/// Spec: TB2, TB3, TB4, RTS3b, RTS3c, RTS3c1, RTS5, RTL16
void main() {
  group('RealtimeChannelOptions - UTS Tests', () {
    group('TB2 - ChannelOptions attributes', () {
      // UTS: realtime/unit/TB2/channel-options-attributes-0
      test('default values', () {
        const options = RealtimeChannelOptions();

        expect(options.cipherParams, isNull);
        expect(options.params, isNull);
        expect(options.modes, isNull);
        expect(options.attachOnSubscribe, isTrue);
      });

      // UTS: realtime/unit/TB2c/options-with-params-0
      test('TB2c - params attribute', () {
        const options = RealtimeChannelOptions(
          params: {'rewind': '1', 'delta': 'vcdiff'},
        );

        expect(options.params!['rewind'], equals('1'));
        expect(options.params!['delta'], equals('vcdiff'));
      });

      // UTS: realtime/unit/TB2d/options-with-modes-0
      test('TB2d - modes attribute', () {
        const options = RealtimeChannelOptions(
          modes: [ChannelMode.publish, ChannelMode.subscribe],
        );

        expect(options.modes, contains(ChannelMode.publish));
        expect(options.modes, contains(ChannelMode.subscribe));
        expect(options.modes!.length, equals(2));
      });

      // UTS: realtime/unit/TB4/attach-on-subscribe-default-0
      test('TB4 - attachOnSubscribe default is true', () {
        const options1 = RealtimeChannelOptions();
        const options2 = RealtimeChannelOptions(attachOnSubscribe: false);

        expect(options1.attachOnSubscribe, isTrue);
        expect(options2.attachOnSubscribe, isFalse);
      });
    });

    group('TB3 - withCipherKey constructor', () {
      // UTS: realtime/unit/TB3/with-cipher-key-0
      test('creates options with cipher params from base64 key', () {
        // 256-bit key (32 bytes) as base64
        final key = base64.encode(List.filled(32, 0x42));
        final options = RealtimeChannelOptions.withCipherKey(key);

        expect(options.cipherParams, isNotNull);
        expect(options.cipherParams!.algorithm, equals('aes'));
        expect(options.cipherParams!.keyLength, equals(256));
      });
    });

    group('requiresReattachment', () {
      // UTS: realtime/unit/RTS5a2/derived-with-params-0.1
      test('returns false when no params or modes', () {
        const options = RealtimeChannelOptions(
          attachOnSubscribe: false,
        );

        expect(options.requiresReattachment, isFalse);
      });

      // UTS: realtime/unit/RTS3b/options-set-on-new-0.1
      test('returns true when params is set', () {
        const options = RealtimeChannelOptions(
          params: {'rewind': '1'},
        );

        expect(options.requiresReattachment, isTrue);
      });

      // UTS: realtime/unit/RTS3b/options-set-on-new-0.2
      test('returns true when modes is set', () {
        const options = RealtimeChannelOptions(
          modes: [ChannelMode.subscribe],
        );

        expect(options.requiresReattachment, isTrue);
      });
    });
  });

  group('DeriveOptions - UTS Tests', () {
    // UTS: realtime/unit/DO2a/filter-attribute-0
    test('DO2a - filter attribute', () {
      const deriveOptions = DeriveOptions(
        filter: "name == 'event' && data.count > 10",
      );

      expect(
        deriveOptions.filter,
        equals("name == 'event' && data.count > 10"),
      );
    });
  });

  group('RealtimeChannels with options - UTS Tests', () {
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
              ProtocolMessageHelpers.attached(
                channel: msg.channel!,
              ),
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

    group('RTS3b - Options set on new channel', () {
      // UTS: realtime/unit/RTS3b/options-set-on-new-0
      test('get() with options sets them on new channel', () {
        final channelName = testChannelName('RTS3b');
        const channelOptions = RealtimeChannelOptions(
          params: {'rewind': '1'},
          modes: [ChannelMode.subscribe],
        );

        final channel = client.channels.get(channelName, channelOptions);

        expect(channel.options.params!['rewind'], equals('1'));
        expect(channel.options.modes, contains(ChannelMode.subscribe));
      });
    });

    group('RTS3c - Options updated on existing channel', () {
      // UTS: realtime/unit/RTS3c/options-updated-existing-0
      test('get() with options updates existing channel (no reattachment)', () {
        final channelName = testChannelName('RTS3c');

        // Create channel with initial options
        const initialOptions = RealtimeChannelOptions(attachOnSubscribe: false);
        final channel = client.channels.get(channelName, initialOptions);

        // Update with new options that don't require reattachment
        final key = base64.encode(List.filled(32, 0x42));
        final newOptions = RealtimeChannelOptions.withCipherKey(key).copyWith(
          attachOnSubscribe: true,
        );
        final sameChannel = client.channels.get(channelName, newOptions);

        expect(identical(sameChannel, channel), isTrue);
        expect(channel.options.cipherParams, isNotNull);
        expect(channel.options.attachOnSubscribe, isTrue);
      });
    });

    group('RTS3c1 - Error if options would trigger reattachment', () {
      // UTS: realtime/unit/RTS3c1/error-reattach-params-0
      test('throws error when params change on attached channel', () async {
        final channelName = testChannelName('RTS3c1');

        // Create and attach channel
        final channel = client.channels.get(channelName);
        await channel.attach();
        expect(channel.state, equals(ChannelState.attached));

        // Try to update with options that require reattachment
        const newOptions = RealtimeChannelOptions(
          params: {'rewind': '1'},
        );

        expect(
          () => client.channels.get(channelName, newOptions),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40000),
            ),
          ),
        );

        // Channel options should not have changed
        expect(channel.options.params, isNull);
      });

      // UTS: realtime/unit/RTS3c1/error-reattach-modes-1
      test('throws error when modes change on attaching channel', () async {
        final channelName = testChannelName('RTS3c1-modes');

        // Use a separate mock that doesn't auto-respond to ATTACH
        // so the channel stays in attaching state.
        final noRespondMockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(),
            );
          },
          onMessageFromClient: (msg) {
            // Don't respond to ATTACH — channel stays attaching
          },
        );

        final localClient = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'fake.key:secret',
            autoConnect: false,
          ),
          webSocketClient: noRespondMockWs,
        );

        localClient.connect();
        await _awaitConnectionState(
          localClient.connection,
          ConnectionState.connected,
        );

        final channel = localClient.channels.get(channelName);

        // Put channel in attaching state (don't await)
        // ignore: unawaited_futures
        channel.attach();
        await _awaitChannelState(channel, ChannelState.attaching);

        const newOptions = RealtimeChannelOptions(
          modes: [ChannelMode.subscribe],
        );

        expect(
          () => localClient.channels.get(channelName, newOptions),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40000),
            ),
          ),
        );

        noRespondMockWs.dispose();
      });

      // UTS: realtime/unit/RTS3c1/error-reattach-params-0.1
      test('allows non-reattachment options on attached channel', () async {
        final channelName = testChannelName('RTS3c1-allowed');

        final channel = client.channels.get(channelName);
        await channel.attach();

        // Options without params/modes should be allowed
        const newOptions = RealtimeChannelOptions(attachOnSubscribe: false);
        final sameChannel = client.channels.get(channelName, newOptions);

        expect(identical(sameChannel, channel), isTrue);
        expect(channel.options.attachOnSubscribe, isFalse);
      });
    });

    group('RTL16 - setOptions', () {
      // UTS: realtime/unit/RTL16/set-options-updates-0
      test('updates channel options', () async {
        final channelName = testChannelName('RTL16');
        final channel = client.channels.get(channelName);

        const newOptions = RealtimeChannelOptions(
          params: {'delta': 'vcdiff'},
          attachOnSubscribe: false,
        );
        await channel.setOptions(newOptions);

        expect(channel.options.params!['delta'], equals('vcdiff'));
        expect(channel.options.attachOnSubscribe, isFalse);
      });

      // UTS: realtime/unit/RTL16a/triggers-reattach-0
      test('RTL16a - triggers reattachment when params change on attached',
          () async {
        final channelName = testChannelName('RTL16a');
        final channel = client.channels.get(channelName);
        await channel.attach();
        expect(channel.state, equals(ChannelState.attached));

        final stateChanges = <ChannelStateChange>[];
        final subscription = channel.on().listen(stateChanges.add);

        const newOptions = RealtimeChannelOptions(
          params: {'rewind': '1'},
        );
        await channel.setOptions(newOptions);

        // Should have gone through attaching state
        expect(
          stateChanges.any((c) => c.current == ChannelState.attaching),
          isTrue,
        );
        expect(channel.state, equals(ChannelState.attached));
        expect(channel.options.params!['rewind'], equals('1'));

        await subscription.cancel();
      });

      // UTS: realtime/unit/RTL16/set-options-updates-0.1
      test('does not trigger reattachment when only cipher changes', () async {
        final channelName = testChannelName('RTL16-cipher');
        final channel = client.channels.get(channelName);
        await channel.attach();

        final stateChanges = <ChannelStateChange>[];
        final subscription = channel.on().listen(stateChanges.add);

        // Cipher-only change should not require reattachment
        final key = base64.encode(List.filled(32, 0x42));
        final newOptions = RealtimeChannelOptions.withCipherKey(key);
        await channel.setOptions(newOptions);

        // Should not have gone through attaching state
        expect(
          stateChanges.any((c) => c.current == ChannelState.attaching),
          isFalse,
        );
        expect(channel.options.cipherParams, isNotNull);

        await subscription.cancel();
      });
    });

    group('RTS5 - getDerived', () {
      // UTS: realtime/unit/RTS5a/creates-derived-channel-0
      test('RTS5a - creates derived channel', () {
        final baseChannelName = testChannelName('RTS5a');
        const deriveOptions = DeriveOptions(filter: "name == 'foo'");
        final channel =
            client.channels.getDerived(baseChannelName, deriveOptions);

        expect(channel.name, startsWith('[filter='));
        expect(channel.name, endsWith(']$baseChannelName'));
      });

      // UTS: realtime/unit/RTS5a1/filter-base64-encoded-0
      test('RTS5a1 - filter is base64 encoded in channel name', () {
        final baseChannelName = testChannelName('RTS5a1');
        const filter = "name == 'test'";
        const deriveOptions = DeriveOptions(filter: filter);
        final channel =
            client.channels.getDerived(baseChannelName, deriveOptions);

        final expectedEncoded = base64.encode(utf8.encode(filter));
        expect(
          channel.name,
          equals('[filter=$expectedEncoded]$baseChannelName'),
        );
      });

      // UTS: realtime/unit/RTS5a2/derived-with-params-0
      test('RTS5a2 - params included in derived channel name', () {
        final baseChannelName = testChannelName('RTS5a2');
        const deriveOptions = DeriveOptions(filter: "type == 'message'");
        const channelOptions = RealtimeChannelOptions(
          params: {'rewind': '1'},
        );

        final channel = client.channels.getDerived(
          baseChannelName,
          deriveOptions,
          channelOptions,
        );

        expect(channel.name, contains('[filter='));
        expect(channel.name, contains('?rewind=1'));
        expect(channel.name, endsWith(']$baseChannelName'));
      });

      // UTS: realtime/unit/RTS5a2/derived-with-params-0.2
      test('RTS5a2 - multiple params in derived channel name', () {
        final baseChannelName = testChannelName('RTS5a2-multi');
        const deriveOptions = DeriveOptions(filter: 'true');
        const channelOptions = RealtimeChannelOptions(
          params: {'rewind': '1', 'delta': 'vcdiff'},
        );

        final channel = client.channels.getDerived(
          baseChannelName,
          deriveOptions,
          channelOptions,
        );

        // Parse the channel name to verify params without depending on order
        expect(channel.name, endsWith(']$baseChannelName'));

        // Extract qualifier between [ and ]
        final qualifierMatch = RegExp(r'\[(.+)\]').firstMatch(channel.name);
        expect(qualifierMatch, isNotNull);
        final qualifier = qualifierMatch!.group(1)!;

        // Verify filter is present
        expect(qualifier, startsWith('filter='));

        // Extract and parse params
        expect(qualifier, contains('?'));
        final paramsString = qualifier.split('?')[1];
        final parsedParams = Uri.splitQueryString(paramsString);

        expect(parsedParams['rewind'], equals('1'));
        expect(parsedParams['delta'], equals('vcdiff'));
        expect(parsedParams.length, equals(2));
      });

      // UTS: realtime/unit/RTS5/get-derived-with-options-0
      test('options passed to derived channel', () {
        final baseChannelName = testChannelName('RTS5-options');
        const deriveOptions = DeriveOptions(filter: 'true');
        const channelOptions = RealtimeChannelOptions(
          modes: [ChannelMode.subscribe],
          attachOnSubscribe: false,
        );

        final channel = client.channels.getDerived(
          baseChannelName,
          deriveOptions,
          channelOptions,
        );

        expect(channel.options.modes, contains(ChannelMode.subscribe));
        expect(channel.options.attachOnSubscribe, isFalse);
      });

      // UTS: realtime/unit/RTS5/get-derived-with-options-0.1
      test('derived channel is tracked in channels collection', () {
        final baseChannelName = testChannelName('RTS5-tracked');
        const deriveOptions = DeriveOptions(filter: 'true');
        final channel =
            client.channels.getDerived(baseChannelName, deriveOptions);

        expect(client.channels.exists(channel.name), isTrue);
      });
    });
  });

  group('ChannelMode enum - UTS Tests', () {
    // UTS: realtime/unit/TB2d/options-with-modes-0.1
    test('TB2d - all modes exist', () {
      expect(ChannelMode.values, contains(ChannelMode.presence));
      expect(ChannelMode.values, contains(ChannelMode.publish));
      expect(ChannelMode.values, contains(ChannelMode.subscribe));
      expect(ChannelMode.values, contains(ChannelMode.messageSubscribe));
      expect(ChannelMode.values, contains(ChannelMode.presenceSubscribe));
      expect(ChannelMode.values, contains(ChannelMode.objectSubscribe));
      expect(ChannelMode.values, contains(ChannelMode.objectPublish));
    });
  });
}

/// Waits for connection to reach the specified state.
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

/// Waits for channel to reach the specified state.
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

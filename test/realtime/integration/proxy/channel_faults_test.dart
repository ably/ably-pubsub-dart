@Tags(['integration', 'proxy'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/jwt_helper.dart';
import '../../../helpers/poll_until.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    await ensureProxy();
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
    stopProxy();
  });

  /// Creates a Realtime client configured to go through the proxy session.
  RealtimeClient createProxyClient(
    ProxySession session, {
    int? realtimeRequestTimeout,
  }) {
    final apiKey = testApp.keys[0].keyStr;
    return RealtimeClient(
      options: ClientOptions(
        authCallback: (params) async {
          return JwtHelper.generateToken(apiKey: apiKey);
        },
        endpoint: 'localhost',
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
        autoConnect: false,
        realtimeRequestTimeout: realtimeRequestTimeout ?? 10000,
      ),
    );
  }

  group('Channel Fault Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTL4f - Attach timeout (server doesn't respond)
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL4f/attach-timeout-suppressed-0
    test('RTL4f - Attach timeout (server does not respond)', () async {
      final channelName =
          'rtl4f-attach-timeout-${DateTime.now().millisecondsSinceEpoch}';

      // Suppress ATTACH (action 10) for the specific channel
      final session = await ProxySession.create(
        rules: [
          {
            'match': {
              'type': 'ws_frame_to_server',
              'action': 'ATTACH',
              'channel': channelName,
            },
            'action': {'type': 'suppress'},
          },
        ],
      );
      addTearDown(() async => await session.close());

      final client = createProxyClient(
        session,
        realtimeRequestTimeout: 3000,
      );
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Record channel state changes
      final stateChanges = <ChannelStateChange>[];
      final subscription = channel.on().listen(stateChanges.add);
      addTearDown(() async => await subscription.cancel());

      // Attempt to attach - should fail due to timeout
      try {
        await channel.attach();
        fail('Expected attach to throw due to timeout');
      } catch (_) {
        // Expected
      }

      // Await SUSPENDED state
      await pollUntil(
        () async {
          if (channel.state == ChannelState.suspended) return true;
          return null;
        },
      );

      // Assert: channel state == SUSPENDED
      expect(channel.state, equals(ChannelState.suspended));

      // Assert: state changes contain attaching -> suspended
      final hasAttaching =
          stateChanges.any((sc) => sc.current == ChannelState.attaching);
      final hasSuspended =
          stateChanges.any((sc) => sc.current == ChannelState.suspended);
      expect(hasAttaching, isTrue, reason: 'Should have entered ATTACHING');
      expect(
        hasSuspended,
        isTrue,
        reason: 'Should have transitioned to SUSPENDED',
      );

      // Assert: connection stays CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));
    });

    // -------------------------------------------------------------------------
    // RTL14 - Server responds with ERROR to ATTACH
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL14/error-on-attach-0
    test('RTL14 - Server responds with ERROR to ATTACH', () async {
      final channelName =
          'rtl14-error-attach-${DateTime.now().millisecondsSinceEpoch}';

      // Replace ATTACHED (action 11) for channel with ERROR (action 9)
      final session = await ProxySession.create(
        rules: [
          {
            'match': {
              'type': 'ws_frame_to_client',
              'action': 'ATTACHED',
              'channel': channelName,
            },
            'action': {
              'type': 'replace',
              'message': {
                'action': 9, // ERROR
                'channel': channelName,
                'error': {
                  'code': 40160,
                  'statusCode': 403,
                  'message': 'Not permitted',
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(() async => await session.close());

      final client = createProxyClient(session);
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Attempt to attach - should throw
      try {
        await channel.attach();
        fail('Expected attach to throw due to ERROR response');
      } catch (_) {
        // Expected
      }

      // Assert: channel state == FAILED
      expect(channel.state, equals(ChannelState.failed));

      // Assert: errorReason has expected code
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));

      // Assert: connection stays CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));
    });

    // -------------------------------------------------------------------------
    // RTL5f - Detach timeout (server doesn't respond)
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL5f/detach-timeout-suppressed-0
    test('RTL5f - Detach timeout (server does not respond)', () async {
      final channelName =
          'rtl5f-detach-timeout-${DateTime.now().millisecondsSinceEpoch}';

      // Phase 1: No rules, connect and attach normally
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      final client = createProxyClient(
        session,
        realtimeRequestTimeout: 3000,
      );
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Attach successfully
      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Phase 2: Suppress DETACH (action 12) for this channel
      await session.addRules([
        {
          'match': {
            'type': 'ws_frame_to_server',
            'action': 'DETACH',
            'channel': channelName,
          },
          'action': {'type': 'suppress'},
        },
      ]);

      // Record state changes
      final stateChanges = <ChannelStateChange>[];
      final subscription = channel.on().listen(stateChanges.add);
      addTearDown(() async => await subscription.cancel());

      // Attempt to detach - should fail due to timeout
      try {
        await channel.detach();
        fail('Expected detach to throw due to timeout');
      } catch (_) {
        // Expected
      }

      // Assert: channel reverts to ATTACHED
      await pollUntil(
        () async {
          if (channel.state == ChannelState.attached) return true;
          return null;
        },
      );
      expect(channel.state, equals(ChannelState.attached));

      // Assert: state changes include detaching -> attached
      final hasDetaching =
          stateChanges.any((sc) => sc.current == ChannelState.detaching);
      final hasAttached =
          stateChanges.any((sc) => sc.current == ChannelState.attached);
      expect(hasDetaching, isTrue, reason: 'Should have entered DETACHING');
      expect(
        hasAttached,
        isTrue,
        reason: 'Should have reverted to ATTACHED',
      );
    });

    // -------------------------------------------------------------------------
    // RTL13a - Unsolicited DETACHED triggers reattach
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL13a/unsolicited-detach-reattach-0
    test('RTL13a - Unsolicited DETACHED triggers reattach', () async {
      final channelName =
          'rtl13a-unsolicited-detach-${DateTime.now().millisecondsSinceEpoch}';

      // No rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      final client = createProxyClient(session);
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Attach successfully
      await channel.attach();

      // Record state changes
      final stateChanges = <ChannelStateChange>[];
      final subscription = channel.on().listen(stateChanges.add);
      addTearDown(() async => await subscription.cancel());

      // Inject unsolicited DETACHED (action 13) with error
      await session.triggerAction({
        'type': 'inject_to_client',
        'message': {
          'action': 13, // DETACHED
          'channel': channelName,
          'error': {
            'code': 90198,
            'statusCode': 500,
            'message': 'Unsolicited detach',
          },
        },
      });

      // Await channel returning to ATTACHED
      await pollUntil(
        () async {
          // After injection, expect attaching -> attached cycle
          final reattached = stateChanges.any(
            (sc) =>
                sc.current == ChannelState.attached &&
                sc.previous == ChannelState.attaching,
          );
          if (reattached) return true;
          return null;
        },
        timeout: const Duration(seconds: 15),
      );

      // Assert: channel is back in ATTACHED state
      expect(channel.state, equals(ChannelState.attached));

      // Assert: state changes contain attaching -> attached after injection
      final hasAttachingAfterDetach = stateChanges.any(
        (sc) => sc.current == ChannelState.attaching,
      );
      expect(
        hasAttachingAfterDetach,
        isTrue,
        reason: 'Channel should have re-entered ATTACHING after '
            'unsolicited DETACHED',
      );
    });

    // -------------------------------------------------------------------------
    // RTL14 - Channel ERROR transitions to FAILED
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL14/channel-error-goes-failed-1
    test('RTL14 - Channel ERROR transitions to FAILED', () async {
      final channelName =
          'rtl14-channel-error-${DateTime.now().millisecondsSinceEpoch}';

      // No rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      final client = createProxyClient(session);
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Attach successfully
      await channel.attach();

      // Inject channel ERROR (action 9) with code 40160
      await session.triggerAction({
        'type': 'inject_to_client',
        'message': {
          'action': 9, // ERROR
          'channel': channelName,
          'error': {
            'code': 40160,
            'statusCode': 403,
            'message': 'Not permitted',
          },
        },
      });

      // Await FAILED state
      await pollUntil(
        () async {
          if (channel.state == ChannelState.failed) return true;
          return null;
        },
      );

      // Assert: channel state == FAILED
      expect(channel.state, equals(ChannelState.failed));

      // Assert: errorReason has expected code
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));

      // Assert: connection stays CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));
    });

    // -------------------------------------------------------------------------
    // RTL12 - ATTACHED with resumed=false emits update
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL12/attached-non-resumed-update-0
    test('RTL12 - ATTACHED with resumed=false emits update', () async {
      final channelName =
          'rtl12-attached-update-${DateTime.now().millisecondsSinceEpoch}';

      // No rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      final client = createProxyClient(session);
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel = client.channels.get(channelName);

      // Attach successfully
      await channel.attach();

      // Listen for update events
      final updateEvents = <ChannelStateChange>[];
      final subscription =
          channel.on(ChannelEvent.update).listen(updateEvents.add);
      addTearDown(() async => await subscription.cancel());

      // Inject ATTACHED (action 11) with flags=0 (no resumed), error 91001
      await session.triggerAction({
        'type': 'inject_to_client',
        'message': {
          'action': 11, // ATTACHED
          'channel': channelName,
          'flags': 0,
          'error': {
            'code': 91001,
            'statusCode': 500,
            'message': 'Channel reattached without resume',
          },
        },
      });

      // Poll until update event received
      await pollUntil(
        () async {
          if (updateEvents.isNotEmpty) return true;
          return null;
        },
      );

      // Assert: update event properties
      final updateEvent = updateEvents.first;
      expect(updateEvent.event, equals(ChannelEvent.update));
      expect(updateEvent.current, equals(ChannelState.attached));
      expect(updateEvent.previous, equals(ChannelState.attached));
      expect(updateEvent.resumed, isFalse);
      expect(updateEvent.reason, isNotNull);
      expect(updateEvent.reason!.code, equals(91001));
    });

    // -------------------------------------------------------------------------
    // RTL3d - Channels reattach after connection recovery
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL3d/channels-reattach-on-reconnect-0
    test('RTL3d - Channels reattach after connection recovery', () async {
      final channelName1 =
          'rtl3d-reattach1-${DateTime.now().millisecondsSinceEpoch}';
      final channelName2 =
          'rtl3d-reattach2-${DateTime.now().millisecondsSinceEpoch}';

      // No rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      final client = createProxyClient(session);
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      await client.connect();

      final channel1 = client.channels.get(channelName1);
      final channel2 = client.channels.get(channelName2);

      // Attach both channels
      await channel1.attach();
      await channel2.attach();
      await pollUntil(
        () async {
          if (channel1.state == ChannelState.attached &&
              channel2.state == ChannelState.attached) {
            return true;
          }
          return null;
        },
      );

      // Record channel state changes
      final ch1Changes = <ChannelStateChange>[];
      final ch2Changes = <ChannelStateChange>[];
      final sub1 = channel1.on().listen(ch1Changes.add);
      final sub2 = channel2.on().listen(ch2Changes.add);
      addTearDown(() async {
        await sub1.cancel();
        await sub2.cancel();
      });

      // Set up reconnection listener BEFORE triggering disconnect
      final reconnectedFuture = client.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 30));

      // Trigger disconnect by closing the WebSocket
      await session.triggerAction({
        'type': 'close',
      });

      // Await reconnection to CONNECTED
      await reconnectedFuture;

      // Await both channels re-attached
      await pollUntil(
        () async {
          if (channel1.state == ChannelState.attached &&
              channel2.state == ChannelState.attached) {
            return true;
          }
          return null;
        },
        timeout: const Duration(seconds: 15),
      );

      // Assert: both channels went through attaching -> attached after
      // disconnect
      final ch1ReattachCycle = ch1Changes.any(
        (sc) => sc.current == ChannelState.attaching,
      );
      final ch2ReattachCycle = ch2Changes.any(
        (sc) => sc.current == ChannelState.attaching,
      );
      expect(
        ch1ReattachCycle,
        isTrue,
        reason: 'Channel 1 should have re-entered ATTACHING after disconnect',
      );
      expect(
        ch2ReattachCycle,
        isTrue,
        reason: 'Channel 2 should have re-entered ATTACHING after disconnect',
      );

      // Assert: both channels are now ATTACHED
      expect(channel1.state, equals(ChannelState.attached));
      expect(channel2.state, equals(ChannelState.attached));
    });
  });
}

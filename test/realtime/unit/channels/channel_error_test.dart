import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for channel ERROR protocol message handling (RTL14).
///
/// These tests use mocked WebSocket to verify that channel-scoped ERROR
/// messages transition the channel to FAILED and complete pending operations.
///
/// Spec: uts/test/realtime/unit/channels/channel_error.md
void main() {
  group('RTL14 - Channel ERROR transitions ATTACHED channel to FAILED', () {
    // UTS: realtime/unit/RTL14/attached-to-failed-0
    test('transitions to FAILED with error info', () async {
      final channelName = testChannelName('RTL14-attached');

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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Record channel state changes
      final stateChanges = <ChannelStateChange>[];
      channel.on().listen(stateChanges.add);

      // Server sends channel-scoped ERROR
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 40160,
          message: 'Not permitted',
          statusCode: 401,
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.failed);

      // Channel transitioned to FAILED
      expect(channel.state, equals(ChannelState.failed));

      // errorReason is set
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));
      expect(channel.errorReason!.statusCode, equals(401));

      // State change event emitted
      expect(stateChanges.length, equals(1));
      expect(stateChanges[0].current, equals(ChannelState.failed));
      expect(stateChanges[0].previous, equals(ChannelState.attached));
      expect(stateChanges[0].reason, isNotNull);
      expect(stateChanges[0].reason!.code, equals(40160));

      // Connection stays open
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTL14 - Channel ERROR transitions ATTACHING channel to FAILED', () {
    // UTS: realtime/unit/RTL14/attaching-to-failed-1
    test('attach fails with the error', () async {
      final channelName = testChannelName('RTL14-attaching');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Respond with channel ERROR instead of ATTACHED
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.error(
                code: 40160,
                message: 'Not permitted',
                statusCode: 401,
                channel: channelName,
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Attach should fail
      late AblyException caughtError;
      try {
        await channel.attach();
      } on AblyException catch (e) {
        caughtError = e;
      }

      // Channel is in FAILED state
      expect(channel.state, equals(ChannelState.failed));

      // errorReason is set
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));

      // The error from attach() matches
      expect(caughtError.errorInfo?.code, equals(40160));

      // Connection stays open
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTL14 - Channel ERROR completes pending detach with error', () {
    // UTS: realtime/unit/RTL14/pending-detach-error-2
    test('detach fails when ERROR received while DETACHING', () async {
      final channelName = testChannelName('RTL14-detaching');

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
          } else if (msg.action == ProtocolAction.detach) {
            // Respond with ERROR instead of DETACHED
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.error(
                code: 90198,
                message: 'Detach failed',
                statusCode: 500,
                channel: channelName,
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Detach should fail
      late AblyException caughtError;
      try {
        await channel.detach();
      } on AblyException catch (e) {
        caughtError = e;
      }

      // Channel is in FAILED state (not DETACHED)
      expect(channel.state, equals(ChannelState.failed));

      // errorReason is set
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(90198));

      // The error from detach() matches
      expect(caughtError.errorInfo?.code, equals(90198));

      // Connection stays open
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTL14 - Channel ERROR does not affect other channels', () {
    // UTS: realtime/unit/RTL14/other-channels-unaffected-3
    test('only target channel transitions to FAILED', () async {
      final channelNameA = testChannelName('RTL14-a');
      final channelNameB = testChannelName('RTL14-b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: msg.channel!),
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

      final channelA = client.channels.get(channelNameA);
      final channelB = client.channels.get(channelNameB);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channelA.attach();
      await channelB.attach();
      expect(channelA.state, equals(ChannelState.attached));
      expect(channelB.state, equals(ChannelState.attached));

      // Send ERROR only for channel A
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 40160,
          message: 'Not permitted',
          statusCode: 401,
          channel: channelNameA,
        ),
      );
      await _awaitChannelState(channelA, ChannelState.failed);

      // Channel A is FAILED
      expect(channelA.state, equals(ChannelState.failed));
      expect(channelA.errorReason, isNotNull);

      // Channel B is unaffected
      expect(channelB.state, equals(ChannelState.attached));

      // Connection stays open
      expect(client.connection.state, equals(ConnectionState.connected));

      mockWs.dispose();
    });
  });

  group('RTL14 - Channel ERROR cancels pending timers', () {
    // UTS: realtime/unit/RTL14/cancels-pending-timers-4
    test('channel retry timer cancelled by ERROR', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL14-timers');
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
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: channelName),
                );
              }
              // Don't respond to subsequent attaches
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
            channelRetryTimeout: 200,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        await channel.attach();
        expect(attachCount, equals(1));

        // Trigger server-initiated DETACHED -> reattach -> timeout -> SUSPENDED
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90198,
              statusCode: 500,
              message: 'Detach',
            ),
          ),
        );
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));

        // Channel retry timer is now pending (channelRetryTimeout = 200ms)
        // Send ERROR before the retry fires
        mockWs.activeConnection!.sendToClient(
          ProtocolMessageHelpers.error(
            code: 40160,
            message: 'Not permitted',
            statusCode: 401,
            channel: channelName,
          ),
        );
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.failed));

        final attachCountAfterError = attachCount;

        // Advance well past the channelRetryTimeout
        fakeTimers.elapseTime(const Duration(milliseconds: 500));
        await _pumpEventQueue();

        // Channel remains FAILED — no retry attempted
        expect(channel.state, equals(ChannelState.failed));
        expect(attachCount, equals(attachCountAfterError));

        mockWs.dispose();
      });
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

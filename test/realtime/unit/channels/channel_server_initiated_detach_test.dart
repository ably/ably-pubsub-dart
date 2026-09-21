import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for server-initiated DETACHED and channel retry (RTL13).
///
/// These tests use mocked WebSocket and fake timers to verify that
/// server-initiated DETACHED messages trigger appropriate reattach
/// or SUSPENDED behavior.
///
/// Spec: uts/test/realtime/unit/channels/channel_server_initiated_detach.md
void main() {
  group('RTL13a - Server DETACHED on ATTACHED channel triggers reattach', () {
    // UTS: realtime/unit/RTL13a/attached-reattach-triggered-0
    test('transitions to ATTACHING with error and reattaches', () async {
      final channelName = testChannelName('RTL13a-attached');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final client = PubSubClient.forTesting(
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
      expect(attachCount, equals(1));

      // Record state changes
      final stateChanges = <ChannelStateChange>[];
      channel.on().listen(stateChanges.add);

      // Server sends unsolicited DETACHED with error
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.detached,
          channel: channelName,
          error: const ErrorInfo(
            code: 90198,
            statusCode: 500,
            message: 'Server detached channel',
          ),
        ),
      );

      // Channel should reattach automatically
      await _awaitChannelState(channel, ChannelState.attached);
      await _pumpEventQueue();

      // Two ATTACH messages total: initial + reattach
      expect(attachCount, equals(2));

      // State change sequence: ATTACHING (with error) -> ATTACHED
      expect(stateChanges.length, greaterThanOrEqualTo(2));
      expect(stateChanges[0].current, equals(ChannelState.attaching));
      expect(stateChanges[0].previous, equals(ChannelState.attached));
      expect(stateChanges[0].reason, isNotNull);
      expect(stateChanges[0].reason!.code, equals(90198));
      expect(stateChanges[1].current, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTL13a - Server DETACHED on SUSPENDED channel triggers reattach', () {
    // UTS: realtime/unit/RTL13a/suspended-reattach-triggered-1
    test('reattaches from SUSPENDED state', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL13a-suspended');
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
                // First attach succeeds
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: channelName),
                );
              } else if (attachCount == 2) {
                // Second attach (after first DETACHED) — don't respond
                // (causes timeout -> SUSPENDED)
              } else {
                // Third attach (after second DETACHED from SUSPENDED)
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
            realtimeRequestTimeout: 100,
            channelRetryTimeout: 60000,
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
        expect(channel.state, equals(ChannelState.attached));

        // Server sends DETACHED to trigger RTL13a reattach
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90198,
              statusCode: 500,
              message: 'Detach 1',
            ),
          ),
        );
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.attaching));

        // Let the reattach timeout -> SUSPENDED
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));

        // Now send another server-initiated DETACHED while SUSPENDED
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90199,
              statusCode: 500,
              message: 'Detach 2',
            ),
          ),
        );

        // Channel should reattach and succeed
        await _awaitChannelState(channel, ChannelState.attached);

        expect(channel.state, equals(ChannelState.attached));
        // 3 total ATTACH messages
        expect(attachCount, equals(3));

        mockWs.dispose();
      });
    });
  });

  group('RTL13b - Failed reattach transitions to SUSPENDED with retry', () {
    // UTS: realtime/unit/RTL13b/failed-reattach-suspended-retry-0
    test('timeout causes SUSPENDED then auto-retry succeeds', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL13b');
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
                // First attach succeeds
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: channelName),
                );
              } else if (attachCount == 2) {
                // Reattach after server DETACHED — don't respond (timeout)
              } else if (attachCount == 3) {
                // Auto retry from SUSPENDED — succeed
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

        // Record state changes
        final stateChanges = <ChannelStateChange>[];
        channel.on().listen(stateChanges.add);

        // Server sends unsolicited DETACHED
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90198,
              statusCode: 500,
              message: 'Server detached',
            ),
          ),
        );
        await _pumpEventQueue();

        // Channel should be ATTACHING (RTL13a)
        expect(channel.state, equals(ChannelState.attaching));
        expect(attachCount, equals(2));

        // Let reattach timeout -> SUSPENDED (RTL13b)
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));

        // Wait for channelRetryTimeout to trigger auto retry and succeed
        fakeTimers.elapseTime(const Duration(milliseconds: 250));
        await _pumpEventQueue();
        await _awaitChannelState(channel, ChannelState.attached);

        expect(channel.state, equals(ChannelState.attached));
        expect(attachCount, equals(3));

        // Verify state sequence
        final states = stateChanges.map((c) => c.current).toList();
        expect(
          states,
          containsAllInOrder([
            ChannelState.attaching,
            ChannelState.suspended,
            ChannelState.attaching,
            ChannelState.attached,
          ]),
        );

        mockWs.dispose();
      });
    });
  });

  group('RTL13b - Server DETACHED while ATTACHING transitions to SUSPENDED',
      () {
    // UTS: realtime/unit/RTL13b/attaching-detached-to-suspended-1
    test('goes directly to SUSPENDED without another reattach', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL13b-attaching');
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
                // First attach — don't respond, leave in ATTACHING
              } else if (attachCount == 2) {
                // Auto retry from SUSPENDED — succeed
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
            realtimeRequestTimeout: 500,
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

        // Start attach but don't await (mock won't respond)
        unawaited(channel.attach().catchError((_) {}));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.attaching));

        // Record state changes
        final stateChanges = <ChannelStateChange>[];
        channel.on().listen(stateChanges.add);

        // Server sends DETACHED while ATTACHING
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90198,
              statusCode: 500,
              message: 'Server detached',
            ),
          ),
        );
        await _pumpEventQueue();

        // Channel should go directly to SUSPENDED (RTL13b)
        expect(channel.state, equals(ChannelState.suspended));
        expect(attachCount, equals(1)); // Only the original attach

        // Wait for channelRetryTimeout — auto retry should succeed
        fakeTimers.elapseTime(const Duration(milliseconds: 250));
        await _pumpEventQueue();
        await _awaitChannelState(channel, ChannelState.attached);

        expect(attachCount, equals(2));

        // Verify direct transition to SUSPENDED
        expect(stateChanges[0].current, equals(ChannelState.suspended));
        expect(stateChanges[0].previous, equals(ChannelState.attaching));
        expect(stateChanges[0].reason, isNotNull);
        expect(stateChanges[0].reason!.code, equals(90198));

        mockWs.dispose();
      });
    });
  });

  group('RTL13b - Repeated failures cycle SUSPENDED -> ATTACHING', () {
    // UTS: realtime/unit/RTL13b/repeated-failure-cycle-2
    test('cycles indefinitely until success', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL13b-repeat');
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
              } else if (attachCount <= 3) {
                // Attempts 2 and 3 — don't respond (timeout)
              } else {
                // Attempt 4 — succeed
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

        // Record state changes
        final stateChanges = <ChannelStateChange>[];
        channel.on().listen(stateChanges.add);

        // Server sends DETACHED
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

        // Cycle 1: ATTACHING -> timeout -> SUSPENDED -> retry
        expect(channel.state, equals(ChannelState.attaching));
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));
        fakeTimers.elapseTime(const Duration(milliseconds: 250));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.attaching));
        expect(attachCount, equals(3));

        // Cycle 2: ATTACHING -> timeout -> SUSPENDED -> retry -> success
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));
        fakeTimers.elapseTime(const Duration(milliseconds: 250));
        await _pumpEventQueue();
        await _awaitChannelState(channel, ChannelState.attached);

        expect(attachCount, equals(4));

        // Verify repeated cycling
        final states = stateChanges.map((c) => c.current).toList();
        expect(
          states,
          containsAllInOrder([
            ChannelState.attaching,
            ChannelState.suspended,
            ChannelState.attaching,
            ChannelState.suspended,
            ChannelState.attaching,
            ChannelState.attached,
          ]),
        );

        mockWs.dispose();
      });
    });
  });

  group('RTL13c - Retry cancelled when connection not CONNECTED', () {
    // UTS: realtime/unit/RTL13c/retry-cancelled-disconnected-0
    test('no retry after disconnect', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL13c');
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
              // Don't respond to reattach attempts
            }
          },
        );

        final client = PubSubClient.forTesting(
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

        // Server sends DETACHED
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

        // Reattach triggered (RTL13a) but will timeout
        expect(channel.state, equals(ChannelState.attaching));
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));

        // Disconnect BEFORE the channelRetryTimeout fires
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        final attachCountAfterDisconnect = attachCount;

        // Advance well past the channelRetryTimeout
        fakeTimers.elapseTime(const Duration(milliseconds: 500));
        await _pumpEventQueue();

        // No additional ATTACH messages should have been sent
        expect(attachCount, equals(attachCountAfterDisconnect));

        mockWs.dispose();
      });
    });
  });

  group('RTB1 - Channel retry delay when SUSPENDED', () {
    // UTS: realtime/unit/RTB1/suspended-channel-retry-delay-1
    test('retry happens after channelRetryTimeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTB1-retry');
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
                // First attach succeeds
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: channelName),
                );
              } else if (attachCount == 2) {
                // Reattach after DETACHED -- don't respond (timeout)
              } else if (attachCount == 3) {
                // Retry from SUSPENDED -- succeed
                mockWs.activeConnection!.sendToClient(
                  ProtocolMessageHelpers.attached(channel: channelName),
                );
              }
            }
          },
        );

        const channelRetryTimeout = 5000;

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
            channelRetryTimeout: channelRetryTimeout,
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

        // Server sends DETACHED -> triggers reattach that times out
        mockWs.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.detached,
            channel: channelName,
            error: const ErrorInfo(
              code: 90198,
              statusCode: 500,
              message: 'Detached',
            ),
          ),
        );
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.attaching));

        // Let reattach timeout -> SUSPENDED
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));

        // Advance less than channelRetryTimeout -- should not retry yet
        fakeTimers.elapseTime(const Duration(milliseconds: 3000));
        await _pumpEventQueue();
        expect(channel.state, equals(ChannelState.suspended));
        expect(attachCount, equals(2)); // No new attach attempt

        // Advance past channelRetryTimeout -- should trigger retry
        fakeTimers.elapseTime(const Duration(milliseconds: 3000));
        await _pumpEventQueue();
        await _awaitChannelState(channel, ChannelState.attached);

        expect(channel.state, equals(ChannelState.attached));
        expect(attachCount, equals(3));

        mockWs.dispose();
      });
    });
  });

  group('RTL13 - DETACHED while DETACHING is normal detach flow', () {
    // UTS: realtime/unit/RTL13a/detaching-not-server-initiated-2
    test('completes detach without triggering reattach', () async {
      final channelName = testChannelName('RTL13-detaching');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.detach) {
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      await channel.detach();

      // Channel should be cleanly DETACHED, not re-attached
      expect(channel.state, equals(ChannelState.detached));
      expect(attachCount, equals(1));

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

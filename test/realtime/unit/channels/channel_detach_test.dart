import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel detach (RTL5).
///
/// These tests use mocked WebSocket to verify channel detach behavior
/// including state transitions, protocol messages, and error handling.
///
/// Spec: uts/test/realtime/unit/channels/channel_detach.md
void main() {
  group('RTL5a - Detach when initialized is no-op', () {
    // UTS: realtime/unit/RTL5a/detach-initialized-noop-0
    test('returns immediately from initialized state', () async {
      final channelName = testChannelName('RTL5a');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
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
      expect(channel.state, equals(ChannelState.initialized));

      // Detach from initialized state - should be no-op
      await channel.detach();

      // Should remain initialized or transition to detached
      expect(
        channel.state,
        anyOf(
          equals(ChannelState.initialized),
          equals(ChannelState.detached),
        ),
      );

      mockWs.dispose();
    });
  });

  group('RTL5a - Detach when already detached is no-op', () {
    // UTS: realtime/unit/RTL5a/detach-already-detached-noop-1
    test('does not send additional DETACH message', () async {
      final channelName = testChannelName('RTL5a-detached');
      var detachMessageCount = 0;

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
          } else if (msg.action == ProtocolAction.detach) {
            detachMessageCount++;
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

      // Attach then detach
      await channel.attach();
      await channel.detach();
      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(1));

      // Second detach - should be no-op
      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(1));

      mockWs.dispose();
    });
  });

  group('RTL5i - Detach while detaching waits for completion', () {
    // UTS: realtime/unit/RTL5i/detach-while-detaching-0
    test('only sends one DETACH message', () async {
      final channelName = testChannelName('RTL5i');
      var detachMessageCount = 0;

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
          } else if (msg.action == ProtocolAction.detach) {
            detachMessageCount++;
            // Don't respond immediately
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

      // Start first detach (don't await)
      final detachFuture1 = channel.detach();

      // Wait for detaching state
      await _awaitChannelState(channel, ChannelState.detaching);

      // Start second detach while first is pending
      final detachFuture2 = channel.detach();

      // Now send DETACHED response
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.detached(channel: channelName),
      );

      // Both should complete
      await detachFuture1;
      await detachFuture2;

      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(1));

      mockWs.dispose();
    });
  });

  group('RTL5i - Detach while attaching waits then detaches', () {
    // UTS: realtime/unit/RTL5i/detach-while-attaching-1
    test('sends DETACH after ATTACH completes', () async {
      final channelName = testChannelName('RTL5i-attaching');
      final messagesFromClient = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          messagesFromClient.add(msg);
          if (msg.action == ProtocolAction.attach) {
            // Don't auto-respond - we'll do it manually
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

      // Start attach (don't await)
      final attachFuture = channel.attach();
      await _awaitChannelState(channel, ChannelState.attaching);

      // Start detach while attaching
      final detachFuture = channel.detach();

      // Send ATTACHED response - attach completes
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      // Wait for both operations
      await attachFuture;
      await detachFuture;

      expect(channel.state, equals(ChannelState.detached));
      // Should have: ATTACH, DETACH
      expect(messagesFromClient.length, equals(2));
      expect(messagesFromClient[0].action, equals(ProtocolAction.attach));
      expect(messagesFromClient[1].action, equals(ProtocolAction.detach));

      mockWs.dispose();
    });
  });

  group('RTL5b - Detach from failed state results in error', () {
    // UTS: realtime/unit/RTL5b/detach-failed-errors-0
    test('returns error when channel is in failed state', () async {
      final channelName = testChannelName('RTL5b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Fail the attachment
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.error,
                channel: channelName,
                error: const ErrorInfo(code: 40160, message: 'Not permitted'),
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Attach fails - channel enters failed state
      try {
        await channel.attach();
      } catch (_) {
        // Expected
      }
      expect(channel.state, equals(ChannelState.failed));

      // Try to detach from failed state
      expect(
        () => channel.detach(),
        throwsA(isA<AblyException>()),
      );

      expect(channel.state, equals(ChannelState.failed));

      mockWs.dispose();
    });
  });

  group('RTL5j - Detach from suspended transitions to detached', () {
    // UTS: realtime/unit/RTL5j/detach-suspended-to-detached-0
    test('transitions directly without sending DETACH message', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL5j');
        var detachMessageCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(),
            );
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              // Don't respond - let it timeout to suspended
            } else if (msg.action == ProtocolAction.detach) {
              detachMessageCount++;
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
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

        // Start attach — capture future and register error handler immediately
        // so the completeError from the timeout doesn't become unhandled.
        Object? attachError;
        final attachFuture =
            channel.attach().catchError((Object e) => attachError = e);

        // Let it timeout to suspended
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        await attachFuture;

        expect(attachError, isA<AblyException>());
        expect(channel.state, equals(ChannelState.suspended));

        // Detach from suspended
        await channel.detach();

        expect(channel.state, equals(ChannelState.detached));
        expect(
          detachMessageCount,
          equals(0),
          reason: 'No DETACH message should be sent - immediate transition',
        );

        mockWs.dispose();
      });
    });
  });

  group('RTL5l - Detach when connection not connected transitions immediately',
      () {
    // UTS: realtime/unit/RTL5l/detach-not-connected-immediate-0
    test('transitions to detached without sending DETACH', () async {
      final channelName = testChannelName('RTL5l');
      var detachMessageCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          // Don't respond - leave connection in connecting state
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.detach) {
            detachMessageCount++;
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

      // Start connecting but don't complete
      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connecting,
      );

      // Put channel into attaching state
      // ignore: unawaited_futures
      channel.attach();
      await _awaitChannelState(channel, ChannelState.attaching);

      // Now detach while connection is still connecting
      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(0));

      mockWs.dispose();
    });
  });

  group('RTL5d - Normal detach flow', () {
    // UTS: realtime/unit/RTL5d/normal-detach-flow-0
    test('sends DETACH and transitions through detaching to detached',
        () async {
      final channelName = testChannelName('RTL5d');
      ProtocolMessage? capturedDetachMessage;

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
          } else if (msg.action == ProtocolAction.detach) {
            capturedDetachMessage = msg;
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

      final stateChanges = <ChannelStateChange>[];
      channel.on().listen(stateChanges.add);

      await channel.detach();
      await _pumpEventQueue();

      // Verify detaching transition occurred
      final detachingEvent = stateChanges
          .where((c) => c.current == ChannelState.detaching)
          .toList();
      expect(detachingEvent.length, equals(1));
      expect(channel.state, equals(ChannelState.detached));
      expect(capturedDetachMessage, isNotNull);
      expect(capturedDetachMessage!.action, equals(ProtocolAction.detach));
      expect(capturedDetachMessage!.channel, equals(channelName));

      mockWs.dispose();
    });
  });

  group('RTL5f - Detach timeout returns to previous state', () {
    // UTS: realtime/unit/RTL5f/timeout-returns-previous-state-0
    test('returns to attached state on timeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL5f');

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
            } else if (msg.action == ProtocolAction.detach) {
              // Don't respond - simulate timeout
            }
          },
        );

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
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

        // Register error handler immediately so completeError from the
        // async timeout callback doesn't become unhandled.
        Object? detachError;
        final detachFuture =
            channel.detach().catchError((Object e) => detachError = e);

        // Advance time past timeout
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();
        await detachFuture;

        expect(detachError, isA<AblyException>());
        expect(
          channel.state,
          equals(ChannelState.attached),
          reason: 'Should return to previous state on timeout',
        );

        mockWs.dispose();
      });
    });
  });

  group('RTL5k - ATTACHED received while detaching sends new DETACH', () {
    // UTS: realtime/unit/RTL5k/attached-while-detaching-0
    test('sends another DETACH when ATTACHED received during detach', () async {
      final channelName = testChannelName('RTL5k');
      var detachMessageCount = 0;

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
          } else if (msg.action == ProtocolAction.detach) {
            detachMessageCount++;
            if (detachMessageCount == 1) {
              // First DETACH: server sends ATTACHED instead of DETACHED
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            } else {
              // Second DETACH: respond correctly
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.detached(channel: channelName),
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      // Start detach
      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(2));

      mockWs.dispose();
    });
  });

  group('RTL5k - ATTACHED received while detached sends DETACH', () {
    // UTS: realtime/unit/RTL5k/attached-while-detached-1
    test('sends DETACH when unexpected ATTACHED received', () async {
      final channelName = testChannelName('RTL5k-detached');
      var detachMessageCount = 0;

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
          } else if (msg.action == ProtocolAction.detach) {
            detachMessageCount++;
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
      await channel.detach();
      expect(channel.state, equals(ChannelState.detached));
      expect(detachMessageCount, equals(1));

      // Server unexpectedly sends ATTACHED while detached
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      // Wait for client to process and respond
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        detachMessageCount,
        equals(2),
        reason: 'Client should send another DETACH',
      );
      expect(channel.state, equals(ChannelState.detached));

      mockWs.dispose();
    });
  });

  group('RTL5 - Detach emits state change events', () {
    // UTS: realtime/unit/RTL5/detach-state-change-events-0
    test('emits detaching and detached events', () async {
      final channelName = testChannelName('RTL5-events');

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

      final stateChanges = <ChannelStateChange>[];
      channel.on().listen(stateChanges.add);

      await channel.detach();
      await _pumpEventQueue();

      expect(stateChanges.length, greaterThanOrEqualTo(2));

      // First event: detaching
      expect(stateChanges[0].current, equals(ChannelState.detaching));
      expect(stateChanges[0].previous, equals(ChannelState.attached));
      expect(stateChanges[0].event, equals(ChannelEvent.detaching));

      // Second event: detached
      expect(stateChanges[1].current, equals(ChannelState.detached));
      expect(stateChanges[1].previous, equals(ChannelState.detaching));
      expect(stateChanges[1].event, equals(ChannelEvent.detached));

      mockWs.dispose();
    });
  });

  group('RTL5 - Detach clears errorReason', () {
    // UTS: realtime/unit/RTL5/detach-state-change-events-0.1
    test('errorReason is cleared after successful detach', () async {
      final channelName = testChannelName('RTL5-error');
      var attachCount = 0;

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachCount++;
            if (attachCount == 1) {
              // First attach fails
              mockWs.activeConnection!.sendToClient(
                ProtocolMessage(
                  action: ProtocolAction.error,
                  channel: channelName,
                  error: const ErrorInfo(code: 40160, message: 'Denied'),
                ),
              );
            } else {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
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

      // First attach fails
      try {
        await channel.attach();
      } catch (_) {
        // Expected
      }
      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason, isNotNull);

      // Attach again succeeds
      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Detach
      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(channel.errorReason, isNull);

      mockWs.dispose();
    });
  });

  group('RTL5l - Detach ATTACHED channel when connection disconnected', () {
    // UTS: realtime/unit/RTL5l/detach-attached-when-disconnected-1
    test('transitions directly to DETACHED without sending DETACH', () async {
      final channelName = testChannelName('RTL5l');
      final messagesSent = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          messagesSent.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: msg.channel!),
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

      // Attach the channel
      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Disconnect the transport
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Clear sent messages to track what's sent during detach
      messagesSent.clear();

      // Now detach while disconnected
      await channel.detach();

      // Channel transitions directly to DETACHED
      expect(channel.state, equals(ChannelState.detached));

      // No DETACH message was sent (transport is unavailable)
      final detachMessages =
          messagesSent.where((m) => m.action == ProtocolAction.detach);
      expect(detachMessages.length, equals(0));

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

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

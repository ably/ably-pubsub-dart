import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel state and events (RTL2).
///
/// These tests use mocked WebSocket to verify channel state attributes,
/// state change events, and ChannelStateChange object structure.
///
/// Spec: uts/test/realtime/unit/channels/channel_state_events.md
void main() {
  group('RTL2b - Channel state attribute', () {
    // UTS: realtime/unit/RTL2b/channel-state-attribute-0
    test('channel has state of type ChannelState', () {
      final client = PubSubClient(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
      );
      final channelName = testChannelName('RTL2b');
      final channel = client.channels.get(channelName);

      expect(channel.state, isA<ChannelState>());
    });

    // UTS: realtime/unit/RTL2b/initial-state-initialized-1
    test('initial state is initialized', () {
      final client = PubSubClient(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
      );
      final channelName = testChannelName('RTL2b-init');
      final channel = client.channels.get(channelName);

      expect(channel.state, equals(ChannelState.initialized));
    });
  });

  group('RTL2a - State change events emitted for every state change', () {
    // UTS: realtime/unit/RTL2a/state-change-events-emitted-0
    test('emits attaching and attached events during attach', () async {
      final channelName = testChannelName('RTL2a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Respond with ATTACHED after a microtask to allow
            // the attaching state to be observed
            scheduleMicrotask(() {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            });
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

      final stateChanges = <ChannelStateChange>[];
      channel.on().listen(stateChanges.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      expect(stateChanges.length, greaterThanOrEqualTo(2));
      expect(stateChanges[0].current, equals(ChannelState.attaching));
      expect(stateChanges[0].previous, equals(ChannelState.initialized));
      expect(stateChanges[1].current, equals(ChannelState.attached));
      expect(stateChanges[1].previous, equals(ChannelState.attaching));

      mockWs.dispose();
    });
  });

  group('RTL2d, TH1, TH2, TH5 - ChannelStateChange object structure', () {
    // UTS: realtime/unit/RTL2d/state-change-object-structure-0
    test('contains current, previous, and event fields', () async {
      final channelName = testChannelName('RTL2d');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      ChannelStateChange? capturedChange;
      channel.on().listen((change) {
        if (change.current == ChannelState.attaching) {
          capturedChange = change;
        }
      });

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      expect(capturedChange, isNotNull);
      expect(capturedChange, isA<ChannelStateChange>());
      expect(capturedChange!.current, equals(ChannelState.attaching));
      expect(capturedChange!.previous, equals(ChannelState.initialized));
      expect(capturedChange!.event, equals(ChannelEvent.attaching));

      mockWs.dispose();
    });
  });

  group('RTL2d, TH3 - ChannelStateChange includes error reason', () {
    // UTS: realtime/unit/RTL2d/state-change-error-reason-1
    test('error is included in state change when channel fails', () async {
      final channelName = testChannelName('RTL2d-error');

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
              ProtocolMessage(
                action: ProtocolAction.error,
                channel: channelName,
                error: const ErrorInfo(
                  code: 40160,
                  statusCode: 401,
                  message: 'Channel denied',
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

      ChannelStateChange? capturedChange;
      channel.on(ChannelEvent.failed).listen((change) {
        capturedChange = change;
      });

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      try {
        await channel.attach();
      } catch (_) {
        // Expected to fail
      }

      // Allow async broadcast events to be delivered
      await _pumpEventQueue();

      expect(capturedChange, isNotNull);
      expect(capturedChange!.current, equals(ChannelState.failed));
      expect(capturedChange!.reason, isNotNull);
      expect(capturedChange!.reason!.code, equals(40160));
      expect(capturedChange!.reason!.message, equals('Channel denied'));

      mockWs.dispose();
    });
  });

  group('RTL2 - Filtered event subscription', () {
    // UTS: realtime/unit/RTL2/filtered-event-subscription-0
    test('subscribing to specific event only receives that event', () async {
      final channelName = testChannelName('RTL2-filtered');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      final attachedEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.attached).listen(attachedEvents.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      // Allow async broadcast events to be delivered
      await _pumpEventQueue();

      // Should only receive attached event, not attaching
      expect(attachedEvents.length, equals(1));
      expect(attachedEvents[0].current, equals(ChannelState.attached));
      expect(attachedEvents[0].event, equals(ChannelEvent.attached));

      mockWs.dispose();
    });
  });

  group('RTL2g - UPDATE event for condition changes without state change', () {
    // UTS: realtime/unit/RTL2g/no-duplicate-state-events-1
    test('emits UPDATE when ATTACHED received while already attached',
        () async {
      final channelName = testChannelName('RTL2g');

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

      final updateEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.update).listen(updateEvents.add);

      // Server sends another ATTACHED without RESUMED flag
      // (e.g., loss of message continuity after transport resume)
      // Per RTL12, this triggers UPDATE because resumed=false
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      // Allow event to be processed
      await Future<void>.delayed(Duration.zero);

      expect(channel.state, equals(ChannelState.attached));
      expect(updateEvents.length, equals(1));
      expect(updateEvents[0].event, equals(ChannelEvent.update));
      expect(updateEvents[0].current, equals(ChannelState.attached));
      expect(updateEvents[0].previous, equals(ChannelState.attached));
      expect(updateEvents[0].resumed, isFalse);

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL2g/update-event-condition-change-0
    test('does not emit duplicate state events', () async {
      final channelName = testChannelName('RTL2g-nodup');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      final allEvents = <ChannelStateChange>[];
      channel.on().listen(allEvents.add);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();

      // Server sends another ATTACHED message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      await Future<void>.delayed(Duration.zero);

      // Count state events where current == attached AND event == attached
      final attachedStateEvents = allEvents
          .where(
            (e) =>
                e.current == ChannelState.attached &&
                e.event == ChannelEvent.attached,
          )
          .toList();
      expect(
        attachedStateEvents.length,
        equals(1),
        reason: 'Only one ATTACHED state event should be emitted',
      );

      mockWs.dispose();
    });
  });

  group('RTL2i, TH6 - hasBacklog flag in ChannelStateChange', () {
    // UTS: realtime/unit/RTL2i/has-backlog-flag-true-0
    test('hasBacklog is true when ATTACHED has HAS_BACKLOG flag', () async {
      final channelName = testChannelName('RTL2i');
      // HAS_BACKLOG flag (TR3b)
      const hasBacklogFlag = flagHasBacklog;

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
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: hasBacklogFlag,
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

      ChannelStateChange? capturedChange;
      channel.on(ChannelEvent.attached).listen((change) {
        capturedChange = change;
      });

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      await _pumpEventQueue();

      expect(capturedChange, isNotNull);
      expect(capturedChange!.hasBacklog, isTrue);

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL2i/has-backlog-flag-false-1
    test('hasBacklog is false when flag is not present', () async {
      final channelName = testChannelName('RTL2i-false');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      ChannelStateChange? capturedChange;
      channel.on(ChannelEvent.attached).listen((change) {
        capturedChange = change;
      });

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      await _pumpEventQueue();

      expect(capturedChange, isNotNull);
      expect(capturedChange!.hasBacklog, isNull);

      mockWs.dispose();
    });
  });

  group('RTL2d - resumed flag in ChannelStateChange', () {
    // UTS: realtime/unit/RTL2d/resumed-flag-propagated-2
    test('resumed is true when ATTACHED has RESUMED flag', () async {
      final channelName = testChannelName('RTL2d-resumed');
      // RESUMED flag (TR3c)
      const resumedFlag = flagResumed;

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
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: resumedFlag,
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

      ChannelStateChange? capturedChange;
      channel.on(ChannelEvent.attached).listen((change) {
        capturedChange = change;
      });

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      await _pumpEventQueue();

      expect(capturedChange, isNotNull);
      expect(capturedChange!.resumed, isTrue);

      mockWs.dispose();
    });
  });

  group('Channel errorReason attribute', () {
    // UTS: realtime/unit/RTL24/error-reason-populated-0
    test('errorReason is populated when channel enters failed state', () async {
      final channelName = testChannelName('errorReason');

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
              ProtocolMessage(
                action: ProtocolAction.error,
                channel: channelName,
                error: const ErrorInfo(
                  code: 40160,
                  statusCode: 401,
                  message: 'Not authorized',
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      try {
        await channel.attach();
      } catch (_) {
        // Expected to fail
      }

      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40160));
      expect(channel.errorReason!.message, equals('Not authorized'));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL4c/error-reason-cleared-attach-0
    test('errorReason is cleared on successful attach after failure', () async {
      final channelName = testChannelName('errorReason-clear');
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
                  error: const ErrorInfo(
                    code: 40160,
                    message: 'Denied',
                  ),
                ),
              );
            } else {
              // Second attach succeeds
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
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // First attach fails
      try {
        await channel.attach();
      } catch (_) {
        // Expected
      }
      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason, isNotNull);

      // Second attach succeeds
      await channel.attach();

      expect(channel.state, equals(ChannelState.attached));
      expect(channel.errorReason, isNull);

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

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

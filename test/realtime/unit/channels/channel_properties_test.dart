import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for channel properties (RTL15).
///
/// These tests verify that attachSerial and channelSerial properties
/// are correctly maintained across channel lifecycle events.
///
/// Spec: uts/test/realtime/unit/channels/channel_properties.md
void main() {
  group('RTL15a - attachSerial updated from ATTACHED message', () {
    // UTS: realtime/unit/RTL15a/attach-serial-from-attached-0
    test('initially unset, set on attach, updated on reattach', () async {
      final channelName = testChannelName('RTL15a');
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
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'attach-serial-$attachCount',
              ),
            );
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
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

      // Before connecting, attachSerial should be unset
      expect(channel.properties.attachSerial, isNull);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Attach
      await channel.attach();
      expect(channel.properties.attachSerial, equals('attach-serial-1'));

      // Detach and reattach
      await channel.detach();
      await channel.attach();
      expect(channel.properties.attachSerial, equals('attach-serial-2'));

      mockWs.dispose();
    });
  });

  group('RTL15a - attachSerial updated on server-initiated reattach', () {
    // UTS: realtime/unit/RTL15a/attach-serial-server-reattach-1
    test('updated when unsolicited ATTACHED received', () async {
      final channelName = testChannelName('RTL15a-update');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'initial-serial',
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
      expect(channel.properties.attachSerial, equals('initial-serial'));

      // Server sends unsolicited ATTACHED (RTL2g update)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: channelName,
          channelSerial: 'updated-serial',
        ),
      );
      await _pumpEventQueue();

      expect(channel.properties.attachSerial, equals('updated-serial'));

      mockWs.dispose();
    });
  });

  group('RTL15b - channelSerial updated from ATTACHED message', () {
    // UTS: realtime/unit/RTL15b/channel-serial-from-attached-0
    test('set from ATTACHED response channelSerial', () async {
      final channelName = testChannelName('RTL15b-attached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
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

      // Before attach, channelSerial should be unset
      expect(channel.properties.channelSerial, isNull);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.properties.channelSerial, equals('serial-001'));

      mockWs.dispose();
    });
  });

  group('RTL15b - channelSerial updated from MESSAGE and PRESENCE', () {
    // UTS: realtime/unit/RTL15b/channel-serial-from-messages-1
    test('updated by MESSAGE and PRESENCE protocol messages', () async {
      final channelName = testChannelName('RTL15b-messages');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
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
      expect(channel.properties.channelSerial, equals('serial-001'));

      // Server sends MESSAGE with channelSerial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'event',
          data: 'data',
          channelSerial: 'serial-002',
        ),
      );
      await _pumpEventQueue();
      expect(channel.properties.channelSerial, equals('serial-002'));

      // Server sends PRESENCE with channelSerial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.presence(
          channel: channelName,
          channelSerial: 'serial-003',
        ),
      );
      await _pumpEventQueue();
      expect(channel.properties.channelSerial, equals('serial-003'));

      mockWs.dispose();
    });
  });

  group('RTL15b - channelSerial not updated when field not populated', () {
    // UTS: realtime/unit/RTL15b/serial-not-updated-empty-2
    test('MESSAGE without channelSerial does not change it', () async {
      final channelName = testChannelName('RTL15b-noupdate');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
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
      expect(channel.properties.channelSerial, equals('serial-001'));

      // Server sends MESSAGE without channelSerial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.message(
          channel: channelName,
          name: 'event',
          data: 'data',
        ),
      );
      await _pumpEventQueue();

      // channelSerial should remain unchanged
      expect(channel.properties.channelSerial, equals('serial-001'));

      mockWs.dispose();
    });
  });

  group('RTL15b - channelSerial not updated by irrelevant messages', () {
    // UTS: realtime/unit/RTL15b/serial-not-updated-irrelevant-3
    test('HEARTBEAT and ACK do not update channelSerial', () async {
      final channelName = testChannelName('RTL15b-irrelevant');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
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
      expect(channel.properties.channelSerial, equals('serial-001'));

      // Send HEARTBEAT -- should not update channelSerial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.heartbeat(),
      );
      await _pumpEventQueue();
      expect(channel.properties.channelSerial, equals('serial-001'));

      // Send ACK -- should not update channelSerial
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.ack,
          msgSerial: 0,
          count: 1,
        ),
      );
      await _pumpEventQueue();
      expect(channel.properties.channelSerial, equals('serial-001'));

      mockWs.dispose();
    });
  });

  group('RTL15b1 - channelSerial cleared on DETACHED', () {
    // UTS: realtime/unit/RTL15b1/serial-cleared-detached-0
    test('cleared when channel detaches', () async {
      final channelName = testChannelName('RTL15b1-detached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
              ),
            );
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: channelName),
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
      expect(channel.properties.channelSerial, equals('serial-001'));

      await channel.detach();

      expect(channel.state, equals(ChannelState.detached));
      expect(channel.properties.channelSerial, isNull);

      mockWs.dispose();
    });
  });

  group('RTL15b1 - channelSerial cleared on SUSPENDED', () {
    // UTS: realtime/unit/RTL15b1/serial-cleared-suspended-1
    test('cleared when channel enters SUSPENDED via attach timeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL15b1-suspended');
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
                  ProtocolMessageHelpers.attached(
                    channel: channelName,
                    channelSerial: 'serial-001',
                  ),
                );
              }
              // Don't respond to second attach (causes timeout)
            }
          },
        );

        final client = RealtimeClient.forTesting(
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
        expect(channel.properties.channelSerial, equals('serial-001'));

        // Trigger server-initiated DETACHED -> reattach that will timeout
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

        // Let attach timeout -> SUSPENDED
        fakeTimers.elapseTime(const Duration(milliseconds: 150));
        await _pumpEventQueue();

        expect(channel.state, equals(ChannelState.suspended));
        expect(channel.properties.channelSerial, isNull);

        mockWs.dispose();
      });
    });
  });

  group('RTL15b1 - channelSerial cleared on FAILED', () {
    // UTS: realtime/unit/RTL15b1/serial-cleared-failed-2
    test('cleared when channel enters FAILED via ERROR', () async {
      final channelName = testChannelName('RTL15b1-failed');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                channelSerial: 'serial-001',
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
      expect(channel.properties.channelSerial, equals('serial-001'));

      // Server sends channel ERROR -> FAILED
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.error(
          code: 40160,
          message: 'Not permitted',
          statusCode: 401,
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.failed);

      expect(channel.state, equals(ChannelState.failed));
      expect(channel.properties.channelSerial, isNull);

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

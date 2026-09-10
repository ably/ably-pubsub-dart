import 'dart:async';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Creates a mock HTTP client that returns 'yes' for connectivity checks.
http.Client _createMockHttpClient() {
  return http_testing.MockClient((request) async {
    return http.Response('yes', 200);
  });
}

/// Unit tests for RealtimeChannel connection state side effects (RTL3).
///
/// These tests verify that channel states are correctly updated when
/// the connection state changes (FAILED, CLOSED, SUSPENDED, DISCONNECTED,
/// CONNECTED).
///
/// Spec: uts/test/realtime/unit/channels/channel_connection_state.md
void main() {
  // ---- RTL3e: DISCONNECTED has no effect on channels ----

  group('RTL3e - DISCONNECTED has no effect on ATTACHED channel', () {
    // UTS: realtime/unit/RTL3e/disconnected-attached-noop-0
    test('channel remains ATTACHED when connection becomes DISCONNECTED',
        () async {
      final channelName = testChannelName('RTL3e-attached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
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

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Record channel state changes from this point
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Simulate transport failure - connection goes to DISCONNECTED
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Channel state must remain ATTACHED
      expect(channel.state, equals(ChannelState.attached));

      // No channel state change events should have been emitted
      expect(channelStateChanges, isEmpty);

      mockWs.dispose();
    });
  });

  group('RTL3e - DISCONNECTED has no effect on ATTACHING channel', () {
    // UTS: realtime/unit/RTL3e/disconnected-attaching-noop-1
    test('channel remains ATTACHING when connection becomes DISCONNECTED',
        () async {
      final channelName = testChannelName('RTL3e-attaching');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond - leave channel in ATTACHING state
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

      // Start attach but don't await - server won't respond
      // ignore: unawaited_futures
      channel.attach();
      await _awaitChannelState(channel, ChannelState.attaching);

      // Record channel state changes from this point
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Simulate transport failure - connection goes to DISCONNECTED
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Channel state must remain ATTACHING
      expect(channel.state, equals(ChannelState.attaching));

      // No channel state change events should have been emitted
      expect(channelStateChanges, isEmpty);

      mockWs.dispose();
    });
  });

  // ---- RTL3a: FAILED connection transitions channels to FAILED ----

  group('RTL3a - FAILED connection transitions ATTACHED channel to FAILED', () {
    // UTS: realtime/unit/RTL3a/failed-attached-to-failed-0
    test('attached channel moves to FAILED with error from connection',
        () async {
      final channelName = testChannelName('RTL3a-attached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
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

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Record channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Server sends a fatal connection-level ERROR
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 40198,
          statusCode: 403,
          message: 'Account disabled',
        ),
      );

      await _awaitConnectionState(client.connection, ConnectionState.failed);
      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason, isNotNull);
      expect(channel.errorReason!.code, equals(40198));

      // Channel state change event was emitted
      expect(channelStateChanges, isNotEmpty);
      final failedChange = channelStateChanges
          .where((c) => c.current == ChannelState.failed)
          .first;
      expect(failedChange.previous, equals(ChannelState.attached));
      expect(failedChange.reason, isNotNull);
      expect(failedChange.reason!.code, equals(40198));

      mockWs.dispose();
    });
  });

  group('RTL3a - FAILED connection transitions ATTACHING channel to FAILED',
      () {
    // UTS: realtime/unit/RTL3a/failed-attaching-to-failed-1
    test('attaching channel moves to FAILED with error from connection',
        () async {
      final channelName = testChannelName('RTL3a-attaching');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond - leave channel in ATTACHING state
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

      // Start attach but don't await - server won't respond.
      // Register error handler immediately to prevent unhandled error.
      Object? attachError;
      final attachFuture =
          channel.attach().catchError((Object e) => attachError = e);

      await _awaitChannelState(channel, ChannelState.attaching);

      // Record channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Server sends a fatal connection-level ERROR
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 40198,
          statusCode: 403,
          message: 'Account disabled',
        ),
      );

      await _awaitConnectionState(client.connection, ConnectionState.failed);

      // The pending attach should fail
      await attachFuture;
      expect(attachError, isNotNull);

      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason, isNotNull);

      final failedChange = channelStateChanges
          .where((c) => c.current == ChannelState.failed)
          .first;
      expect(failedChange.previous, equals(ChannelState.attaching));

      mockWs.dispose();
    });
  });

  group('RTL3a - Channels in other states unaffected by FAILED connection', () {
    // UTS: realtime/unit/RTL3a/other-states-unaffected-2
    test('INITIALIZED and DETACHED channels are not affected', () async {
      final initializedName = testChannelName('RTL3a-init');
      final detachedName = testChannelName('RTL3a-detached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final initializedChannel = client.channels.get(initializedName);
      final detachedChannel = client.channels.get(detachedName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Leave initializedChannel in INITIALIZED state
      expect(initializedChannel.state, equals(ChannelState.initialized));

      // Attach then detach to get to DETACHED state
      await detachedChannel.attach();
      await detachedChannel.detach();
      expect(detachedChannel.state, equals(ChannelState.detached));

      // Record state changes on both channels
      final initChanges = <ChannelStateChange>[];
      final detachedChanges = <ChannelStateChange>[];
      initializedChannel.on().listen(initChanges.add);
      detachedChannel.on().listen(detachedChanges.add);

      // Server sends a fatal connection-level ERROR
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 40198,
          statusCode: 403,
          message: 'Account disabled',
        ),
      );

      await _awaitConnectionState(client.connection, ConnectionState.failed);

      // Channels not in ATTACHING/ATTACHED should be unaffected
      expect(initializedChannel.state, equals(ChannelState.initialized));
      expect(detachedChannel.state, equals(ChannelState.detached));
      expect(initChanges, isEmpty);
      expect(detachedChanges, isEmpty);

      mockWs.dispose();
    });
  });

  // ---- RTL3b: CLOSED connection transitions channels to DETACHED ----

  group('RTL3b - CLOSED connection transitions ATTACHED channel to DETACHED',
      () {
    // UTS: realtime/unit/RTL3c/suspended-attached-to-suspended-0
    test('attached channel moves to DETACHED when connection is closed',
        () async {
      final channelName = testChannelName('RTL3b-attached');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
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

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));

      // Record channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Close the connection
      await client.close();
      await _pumpEventQueue();
      expect(client.connection.state, equals(ConnectionState.closed));

      expect(channel.state, equals(ChannelState.detached));

      final detachedChange = channelStateChanges
          .where((c) => c.current == ChannelState.detached)
          .first;
      expect(detachedChange.previous, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTL3b - CLOSED connection transitions ATTACHING channel to DETACHED',
      () {
    // UTS: realtime/unit/RTL3b/closed-attaching-to-detached-1
    test('attaching channel moves to DETACHED when connection is closed',
        () async {
      final channelName = testChannelName('RTL3b-attaching');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Do NOT respond - leave channel in ATTACHING state
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

      // Start attach but don't await - server won't respond.
      // Register error handler immediately.
      Object? attachError;
      final attachFuture =
          channel.attach().catchError((Object e) => attachError = e);

      await _awaitChannelState(channel, ChannelState.attaching);

      // Record channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Close the connection
      await client.close();
      expect(client.connection.state, equals(ConnectionState.closed));

      // The pending attach should fail
      await attachFuture;
      expect(attachError, isNotNull);

      expect(channel.state, equals(ChannelState.detached));

      final detachedChange = channelStateChanges
          .where((c) => c.current == ChannelState.detached)
          .first;
      expect(detachedChange.previous, equals(ChannelState.attaching));

      mockWs.dispose();
    });
  });

  // ---- RTL3c: SUSPENDED connection transitions channels to SUSPENDED ----

  group(
      'RTL3c - SUSPENDED connection transitions ATTACHED channel to SUSPENDED',
      () {
    // UTS: realtime/unit/RTL3b/closed-attached-to-detached-0
    test('attached channel moves to SUSPENDED when connection is SUSPENDED',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL3c-attached');
        var connectionAttemptCount = 0;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            if (connectionAttemptCount == 1) {
              // First connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // All reconnection attempts fail
              conn.respondWithRefused();
            }
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
            disconnectedRetryTimeout: 1000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
          httpClient: _createMockHttpClient(),
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        await channel.attach();
        expect(channel.state, equals(ChannelState.attached));

        // Record channel state changes
        final channelStateChanges = <ChannelStateChange>[];
        channel.on().listen(channelStateChanges.add);

        // Simulate disconnect - reconnection attempts will fail
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Advance time past connectionStateTtl to reach SUSPENDED
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 5000));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.suspended) {
            break;
          }
        }

        await _awaitConnectionState(
          client.connection,
          ConnectionState.suspended,
        );

        expect(channel.state, equals(ChannelState.suspended));

        final suspendedChange = channelStateChanges
            .where((c) => c.current == ChannelState.suspended)
            .toList();
        expect(suspendedChange, isNotEmpty);
        expect(suspendedChange.first.previous, equals(ChannelState.attached));

        mockWs.dispose();
      });
    });
  });

  group(
      'RTL3c - SUSPENDED connection transitions ATTACHING channel to SUSPENDED',
      () {
    // UTS: realtime/unit/RTL3c/suspended-attaching-to-suspended-1
    test('attaching channel moves to SUSPENDED when connection is SUSPENDED',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL3c-attaching');
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            if (connectionAttemptCount == 1) {
              // First connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              // All reconnection attempts fail
              conn.respondWithRefused();
            }
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              // Do NOT respond - leave channel in ATTACHING state
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
          httpClient: _createMockHttpClient(),
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // Start attach but don't await - server won't respond
        // ignore: unawaited_futures
        channel.attach().catchError((Object _) {});

        await _awaitChannelState(channel, ChannelState.attaching);

        // Record channel state changes
        final channelStateChanges = <ChannelStateChange>[];
        channel.on().listen(channelStateChanges.add);

        // Simulate disconnect - reconnection attempts will fail
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Advance time past connectionStateTtl to reach SUSPENDED
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 5000));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.suspended) {
            break;
          }
        }

        await _awaitConnectionState(
          client.connection,
          ConnectionState.suspended,
        );

        expect(channel.state, equals(ChannelState.suspended));

        final suspendedChange = channelStateChanges
            .where((c) => c.current == ChannelState.suspended)
            .toList();
        expect(suspendedChange, isNotEmpty);
        expect(suspendedChange.first.previous, equals(ChannelState.attaching));

        mockWs.dispose();
      });
    });
  });

  // ---- RTL3d: CONNECTED connection re-attaches eligible channels ----

  group(
      'RTL3d, RTL4c1 - CONNECTED re-attaches ATTACHED channels with channelSerial',
      () {
    // UTS: realtime/unit/RTL3d/reattach-attached-with-serial-0
    test('re-attaches channel with channelSerial from previous attachment',
        () async {
      final channelName = testChannelName('RTL3d-attached');
      final attachMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: msg.channel!,
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
          disconnectedRetryTimeout: 100,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));
      expect(attachMessages.length, equals(1));

      // Record channel state changes
      final channelStateChanges = <ChannelStateChange>[];
      channel.on().listen(channelStateChanges.add);

      // Simulate disconnect and wait for reconnection
      mockWs.activeConnection!.simulateDisconnect();

      await _awaitConnectionState(client.connection, ConnectionState.connected);
      await _awaitChannelState(channel, ChannelState.attached);
      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.attached));

      // A second ATTACH message was sent for the re-attach
      expect(attachMessages.length, equals(2));

      // RTL4c1: The re-attach ATTACH message must include the channelSerial
      // from the previous ATTACHED response
      expect(attachMessages[1].channelSerial, equals('serial-001'));

      // Channel transitioned through ATTACHING during re-attach
      final stateSequence = channelStateChanges.map((c) => c.current).toList();
      expect(
        stateSequence,
        containsAllInOrder([
          ChannelState.attaching,
          ChannelState.attached,
        ]),
      );

      mockWs.dispose();
    });
  });

  group('RTL3d - CONNECTED re-attaches SUSPENDED channels', () {
    // UTS: realtime/unit/RTL3d/reattach-suspended-channels-1
    test('suspended channel is re-attached when connection is restored',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL3d-suspended');
        var attachMessageCount = 0;
        var shouldSucceed = true;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            if (shouldSucceed) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-1',
                  connectionKey: 'key-1',
                ),
              );
            } else {
              conn.respondWithRefused();
            }
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              attachMessageCount++;
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
            disconnectedRetryTimeout: 1000,
            suspendedRetryTimeout: 2000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
          httpClient: _createMockHttpClient(),
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        await channel.attach();
        expect(channel.state, equals(ChannelState.attached));
        expect(attachMessageCount, equals(1));

        // Simulate disconnect - reconnection attempts will fail
        shouldSucceed = false;
        mockWs.activeConnection!.simulateDisconnect();
        await _pumpEventQueue();

        // Advance time past connectionStateTtl to reach SUSPENDED
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 5000));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.suspended) {
            break;
          }
        }

        await _awaitConnectionState(
          client.connection,
          ConnectionState.suspended,
        );
        expect(channel.state, equals(ChannelState.suspended));

        // Record channel state changes from this point
        final channelStateChanges = <ChannelStateChange>[];
        channel.on().listen(channelStateChanges.add);

        // Allow reconnection to succeed
        shouldSucceed = true;
        // Advance time past suspendedRetryTimeout to trigger retry
        for (var i = 0; i < 10; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 2500));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.connected) {
            break;
          }
        }

        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );
        await _awaitChannelState(channel, ChannelState.attached);
        await _pumpEventQueue();

        expect(channel.state, equals(ChannelState.attached));

        // An ATTACH message was sent for the re-attach
        expect(attachMessageCount, greaterThanOrEqualTo(2));

        // Channel transitioned from SUSPENDED through ATTACHING to ATTACHED
        final stateSequence =
            channelStateChanges.map((c) => c.current).toList();
        expect(
          stateSequence,
          containsAllInOrder([
            ChannelState.attaching,
            ChannelState.attached,
          ]),
        );

        mockWs.dispose();
      });
    });
  });

  group(
      'RTL3d - Channels in INITIALIZED or DETACHED are not re-attached on CONNECTED',
      () {
    // UTS: realtime/unit/RTL3d/init-detached-not-reattached-2
    test('INITIALIZED and DETACHED channels are unaffected by reconnection',
        () async {
      final initializedName = testChannelName('RTL3d-init');
      final detachedName = testChannelName('RTL3d-detached');
      final attachMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
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

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          disconnectedRetryTimeout: 100,
        ),
        webSocketClient: mockWs,
      );

      final initializedChannel = client.channels.get(initializedName);
      final detachedChannel = client.channels.get(detachedName);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Leave initializedChannel in INITIALIZED state
      expect(initializedChannel.state, equals(ChannelState.initialized));

      // Attach then detach to get to DETACHED state
      await detachedChannel.attach();
      await detachedChannel.detach();
      expect(detachedChannel.state, equals(ChannelState.detached));

      final attachCountBefore = attachMessages.length;

      // Record state changes
      final initChanges = <ChannelStateChange>[];
      final detachedChanges = <ChannelStateChange>[];
      initializedChannel.on().listen(initChanges.add);
      detachedChannel.on().listen(detachedChanges.add);

      // Simulate disconnect and reconnect
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      // Neither channel should have been re-attached
      expect(initializedChannel.state, equals(ChannelState.initialized));
      expect(detachedChannel.state, equals(ChannelState.detached));
      expect(initChanges, isEmpty);
      expect(detachedChanges, isEmpty);

      // No new ATTACH messages for these channels
      final newAttachChannels =
          attachMessages.skip(attachCountBefore).map((m) => m.channel).toList();
      expect(newAttachChannels, isNot(contains(initializedName)));
      expect(newAttachChannels, isNot(contains(detachedName)));

      mockWs.dispose();
    });
  });

  group('RTL3d - Multiple channels re-attached on CONNECTED', () {
    // UTS: realtime/unit/RTL3d/multiple-channels-reattached-3
    test('all eligible channels are re-attached after reconnection', () async {
      final channel1Name = testChannelName('RTL3d-multi1');
      final channel2Name = testChannelName('RTL3d-multi2');
      final attachMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
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
          disconnectedRetryTimeout: 100,
        ),
        webSocketClient: mockWs,
      );

      final channel1 = client.channels.get(channel1Name);
      final channel2 = client.channels.get(channel2Name);

      client.connect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await channel1.attach();
      await channel2.attach();
      expect(channel1.state, equals(ChannelState.attached));
      expect(channel2.state, equals(ChannelState.attached));

      final attachCountBefore = attachMessages.length;

      // Simulate disconnect and reconnect
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(client.connection, ConnectionState.connected);

      await _awaitChannelState(channel1, ChannelState.attached);
      await _awaitChannelState(channel2, ChannelState.attached);

      expect(channel1.state, equals(ChannelState.attached));
      expect(channel2.state, equals(ChannelState.attached));

      // Both channels should have received new ATTACH messages
      final newAttachChannels =
          attachMessages.skip(attachCountBefore).map((m) => m.channel).toList();
      expect(newAttachChannels, contains(channel1Name));
      expect(newAttachChannels, contains(channel2Name));

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

import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence automatic re-entry
/// (RTP17a, RTP17e, RTP17g, RTP17g1, RTP17i).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_reentry.md
void main() {
  group('RTP17i - Automatic re-entry on ATTACHED (non-RESUMED)', () {
    // UTS: realtime/unit/RTP17i/auto-reentry-on-attached-0
    test('re-enters after disconnect and reconnect', () async {
      final channelName = testChannelName('RTP17i');

      var connectionCount = 0;
      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-$connectionCount',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Enter presence
      await channel.presence.enter('hello');
      expect(capturedPresence.length, equals(1));

      // Simulate disconnect and reconnect (new connectionId)
      capturedPresence.clear();
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Reconnect — triggers reattach with new ATTACHED (non-RESUMED)
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await _awaitChannelState(channel, ChannelState.attached);

      // Allow re-entry to complete
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // RTP17i: Automatic re-entry sends ENTER for the member
      expect(
        capturedPresence.isNotEmpty,
        isTrue,
        reason: 'Re-entry should have sent ENTER',
      );

      final reentryMsg = capturedPresence.firstWhere(
        (m) => m.action == ProtocolAction.presence,
      );
      final pm = _decodePresence(reentryMsg);
      expect(pm.action, equals(PresenceAction.enter));

      mockWs.dispose();
    });
  });

  group('RTP17g - Re-entry preserves clientId and data', () {
    // UTS: realtime/unit/RTP17g/reentry-publishes-enter-with-data-0
    test('re-enters multiple members with original data', () async {
      final channelName = testChannelName('RTP17g');

      var connectionCount = 0;
      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-$connectionCount',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      // Wildcard client to test enterClient with multiple members
      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('*'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Enter multiple members
      await channel.presence.enterClient('alice', 'alice-data');
      await channel.presence.enterClient('bob', 'bob-data');
      expect(capturedPresence.length, equals(2));

      // Simulate disconnect and reconnect
      capturedPresence.clear();
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await _awaitChannelState(channel, ChannelState.attached);

      // Allow re-entry to complete
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Both members re-entered with ENTER action and original data
      final presenceItems = <PresenceMessage>[];
      for (final msg in capturedPresence) {
        if (msg.action == ProtocolAction.presence) {
          for (final raw in msg.presence!) {
            final p = raw is PresenceMessage
                ? raw
                : PresenceMessage.fromMap(raw as Map<String, dynamic>);
            presenceItems.add(p);
          }
        }
      }

      expect(presenceItems.length, greaterThanOrEqualTo(2));

      final aliceReentry =
          presenceItems.where((p) => p.clientId == 'alice').firstOrNull;
      final bobReentry =
          presenceItems.where((p) => p.clientId == 'bob').firstOrNull;

      expect(aliceReentry, isNotNull);
      expect(aliceReentry!.action, equals(PresenceAction.enter));
      expect(aliceReentry.data, equals('alice-data'));

      expect(bobReentry, isNotNull);
      expect(bobReentry!.action, equals(PresenceAction.enter));
      expect(bobReentry.data, equals('bob-data'));

      mockWs.dispose();
    });
  });

  group('RTP17g1 - Re-entry omits id when connectionId changed', () {
    // UTS: realtime/unit/RTP17g1/reentry-omits-id-new-connid-0
    test('id is null on re-entered message with new connectionId', () async {
      final channelName = testChannelName('RTP17g1');

      var connectionCount = 0;
      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-$connectionCount',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.presence.enter('hello');

      // First connection is conn-1
      expect(connectionCount, equals(1));

      // Disconnect and reconnect — new connectionId (conn-2)
      capturedPresence.clear();
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      expect(connectionCount, equals(2));
      await _awaitChannelState(channel, ChannelState.attached);

      // Allow re-entry to complete
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Re-entry message should NOT have id set because connectionId changed
      final reentry = capturedPresence.firstWhere(
        (m) => m.action == ProtocolAction.presence,
      );
      final pm = _decodePresence(reentry);
      expect(pm.action, equals(PresenceAction.enter));
      expect(
        pm.id,
        isNull,
        reason: 'RTP17g1: id not set when connectionId changed',
      );
      expect(pm.data, equals('hello'));

      mockWs.dispose();
    });
  });

  group('RTP17i - No re-entry when ATTACHED with RESUMED flag', () {
    // UTS: realtime/unit/RTP17i/no-reentry-with-resumed-flag-1
    test('RESUMED flag suppresses automatic re-entry', () async {
      final channelName = testChannelName('RTP17i-resumed');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-1',
              connectionKey: 'key-1',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.presence.enter('hello');

      // Clear captured
      capturedPresence.clear();

      // Server sends ATTACHED with RESUMED flag while already attached
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.attached,
          channel: channelName,
          flags: flagResumed,
        ),
      );

      // Allow any potential re-entry to fire
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No re-entry — RESUMED flag means the server still has our presence
      expect(capturedPresence.length, equals(0));

      mockWs.dispose();
    });
  });

  group('RTP17e - Failed re-entry emits UPDATE with error', () {
    // UTS: realtime/unit/RTP17e/failed-reentry-emits-update-error-0
    test('NACK on re-entry emits channel UPDATE with error 91004', () async {
      final channelName = testChannelName('RTP17e');

      var connectionCount = 0;
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-$connectionCount',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
            if (connectionCount == 1) {
              // First connection: ACK the enter
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
              );
            } else {
              // Second connection: NACK the re-entry
              mockWs.activeConnection!.sendToClient(
                ProtocolMessage(
                  action: ProtocolAction.nack,
                  msgSerial: msg.msgSerial,
                  count: 1,
                  error: const ErrorInfo(
                    code: 40160,
                    statusCode: 401,
                    message: 'Presence denied',
                  ),
                ),
              );
            }
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.presence.enter('hello');

      // Listen for channel UPDATE events
      final channelEvents = <ChannelStateChange>[];
      channel.on(ChannelEvent.update).listen(channelEvents.add);

      // Disconnect and reconnect — re-entry will be NACKed
      mockWs.activeConnection!.simulateDisconnect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.disconnected,
      );

      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await _awaitChannelState(channel, ChannelState.attached);

      // Wait for the re-entry NACK to be processed
      // Re-entry is fire-and-forget, so we need to wait a bit
      for (var i = 0; i < 5 && channelEvents.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        channelEvents.isNotEmpty,
        isTrue,
        reason: 'Should have received UPDATE event for failed re-entry',
      );

      final updateEvent = channelEvents.first;
      expect(updateEvent.resumed, isTrue);
      expect(updateEvent.reason, isNotNull);
      expect(updateEvent.reason!.code, equals(91004));
      expect(updateEvent.reason!.message, contains('my-client'));
      expect(updateEvent.reason!.cause, isA<ErrorInfo>());
      expect((updateEvent.reason!.cause! as ErrorInfo).code, equals(40160));

      mockWs.dispose();
    });
  });

  group('RTP17a - Server publishes member regardless of subscribe capability',
      () {
    // UTS: realtime/unit/RTP17a/server-publishes-without-subscribe-0
    test('member present in public map via get', () async {
      final channelName = testChannelName('RTP17a');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Channel with PRESENCE mode flag but not SUBSCRIBE
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: ChannelMode.presence.flagBit,
              ),
            );
          } else if (msg.action == ProtocolAction.presence) {
            // ACK the enter
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
            // Server delivers the presence event back to the client
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.presence,
                channel: channelName,
                presence: [
                  PresenceMessage(
                    action: PresenceAction.enter,
                    clientId: 'my-client',
                    connectionId: 'conn-1',
                    id: 'conn-1:0:0',
                    timestamp: DateTime.now(),
                  ),
                ],
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: _optionsWithClientId('my-client'),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.presence.enter();

      // Check public presence map
      final members = await channel.presence.get(waitForSync: false);

      expect(members.length, equals(1));
      expect(members[0].clientId, equals('my-client'));

      mockWs.dispose();
    });
  });
}

/// Creates ClientOptions with a clientId using authCallback to avoid real HTTP.
ClientOptions _optionsWithClientId(String clientId) {
  return ClientOptions(
    authCallback: (params) async => TokenDetails(
      token: 'fake-token-for-testing',
      expires:
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      clientId: clientId,
    ),
    clientId: clientId,
    autoConnect: false,
  );
}

/// Waits for the connection to reach the target state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState,
) async {
  if (connection.state == targetState) return;
  await connection.on().firstWhere((change) => change.current == targetState);
  await Future<void>.delayed(Duration.zero);
}

/// Waits for the channel to reach the target state.
Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState,
) async {
  if (channel.state == targetState) return;
  await channel.on().firstWhere((change) => change.current == targetState);
  await Future<void>.delayed(Duration.zero);
}

/// Decodes the first presence message from a captured ProtocolMessage.
PresenceMessage _decodePresence(ProtocolMessage protocolMessage) {
  final raw = protocolMessage.presence![0];
  if (raw is PresenceMessage) return raw;
  return PresenceMessage.fromMap(raw as Map<String, dynamic>);
}

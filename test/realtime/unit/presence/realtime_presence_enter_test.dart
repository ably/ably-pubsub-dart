import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence enter/update/leave (RTP8, RTP9, RTP10,
/// RTP14, RTP15, RTP16).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_enter.md
void main() {
  group('RTP8a, RTP8c - enter sends PRESENCE with ENTER action', () {
    // UTS: realtime/unit/RTP8a/enter-sends-presence-enter-0
    test('sends ENTER without clientId in PresenceMessage', () async {
      final channelName = testChannelName('RTP8a');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
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

      await channel.presence.enter();

      expect(capturedPresence.length, equals(1));
      expect(capturedPresence[0].action, equals(ProtocolAction.presence));
      expect(capturedPresence[0].channel, equals(channelName));

      final presenceList = capturedPresence[0].presence!;
      expect(presenceList.length, equals(1));

      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.enter));
      // RTP8c: clientId must NOT be present in the PresenceMessage
      expect(pm.clientId, isNull);

      mockWs.dispose();
    });
  });

  group('RTP8e - enter with data', () {
    // UTS: realtime/unit/RTP8e/enter-with-data-0
    test('data is included in the presence message', () async {
      final channelName = testChannelName('RTP8e');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
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

      await channel.presence.enter('hello world');

      expect(capturedPresence.length, equals(1));
      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.enter));
      expect(pm.data, equals('hello world'));

      mockWs.dispose();
    });
  });

  group('RTP8d - enter implicitly attaches channel', () {
    // UTS: realtime/unit/RTP8d/enter-implicitly-attaches-0
    test('INITIALIZED channel becomes ATTACHED', () async {
      final channelName = testChannelName('RTP8d');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          } else if (msg.action == ProtocolAction.presence) {
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

      expect(channel.state, equals(ChannelState.initialized));

      // enter() on INITIALIZED channel triggers implicit attach
      await channel.presence.enter();

      expect(channel.state, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTP8g - enter on FAILED channel errors', () {
    // UTS: realtime/unit/RTP8g/enter-detached-failed-errors-0
    test('errors immediately on FAILED channel', () async {
      final channelName = testChannelName('RTP8g');

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
                error: const ErrorInfo(code: 90001, message: 'Channel failed'),
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

      // Put channel into FAILED state
      try {
        await channel.attach();
      } catch (_) {}
      expect(channel.state, equals(ChannelState.failed));

      // enter() on FAILED channel should error immediately
      expect(
        () => channel.presence.enter(),
        throwsA(isA<AblyException>()),
      );

      mockWs.dispose();
    });
  });

  group('RTP8j - enter with null clientId errors', () {
    // UTS: realtime/unit/RTP8j/enter-wildcard-clientid-errors-1
    test('errors immediately for anonymous client', () async {
      final channelName = testChannelName('RTP8j');

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

      // No clientId — anonymous client (basic auth, no HTTP needed)
      final client = RealtimeClient.forTesting(
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
      await channel.attach();

      // enter() without clientId should error
      expect(
        () => channel.presence.enter(),
        throwsA(isA<AblyException>()),
      );

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTP8j/enter-null-clientid-errors-0
    test('errors immediately for wildcard clientId', () async {
      final channelName = testChannelName('RTP8j-wild');

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

      expect(
        () => channel.presence.enter(),
        throwsA(isA<AblyException>()),
      );

      mockWs.dispose();
    });
  });

  group('RTP8h - NACK for missing presence permission', () {
    // UTS: realtime/unit/RTP8h/nack-presence-permission-denied-0
    test('NACK results in error with correct code', () async {
      final channelName = testChannelName('RTP8h');

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
          } else if (msg.action == ProtocolAction.presence) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.nack,
                msgSerial: msg.msgSerial,
                count: 1,
                error: const ErrorInfo(
                  code: 40160,
                  statusCode: 401,
                  message: 'Presence permission denied',
                ),
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

      try {
        await channel.presence.enter();
        fail('Should have thrown');
      } on AblyException catch (e) {
        expect(e.errorInfo?.code, equals(40160));
      }

      mockWs.dispose();
    });
  });

  group('RTP9a, RTP9d - update sends PRESENCE with UPDATE action', () {
    // UTS: realtime/unit/RTP9a/update-sends-presence-update-0
    test('sends UPDATE without clientId', () async {
      final channelName = testChannelName('RTP9a');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
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

      await channel.presence.update('new-status');

      expect(capturedPresence.length, equals(1));
      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.update));
      expect(pm.data, equals('new-status'));
      expect(pm.clientId, isNull); // RTP9d

      mockWs.dispose();
    });
  });

  group('RTP10a, RTP10c - leave sends PRESENCE with LEAVE action', () {
    // UTS: realtime/unit/RTP10a/leave-sends-presence-leave-0
    test('sends LEAVE without clientId', () async {
      final channelName = testChannelName('RTP10a');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
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

      await channel.presence.leave();

      expect(capturedPresence.length, equals(1));
      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.leave));
      expect(pm.clientId, isNull); // RTP10c

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTP10a/leave-with-data-1
    test('leave with data updates member data', () async {
      final channelName = testChannelName('RTP10a-data');

      final capturedPresence = <ProtocolMessage>[];
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

      await channel.presence.leave('goodbye');

      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.leave));
      expect(pm.data, equals('goodbye'));

      mockWs.dispose();
    });
  });

  group('RTP14a - enterClient enters on behalf of another clientId', () {
    // UTS: realtime/unit/RTP14a/enterclient-on-behalf-0
    test('sends ENTER with specified clientId', () async {
      final channelName = testChannelName('RTP14a');

      final capturedPresence = <ProtocolMessage>[];
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
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

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

      await channel.presence.enterClient('user-alice', 'alice-data');
      await channel.presence.enterClient('user-bob', 'bob-data');

      expect(capturedPresence.length, equals(2));

      final pm1 = _decodePresence(capturedPresence[0]);
      expect(pm1.action, equals(PresenceAction.enter));
      expect(pm1.clientId, equals('user-alice'));
      expect(pm1.data, equals('alice-data'));

      final pm2 = _decodePresence(capturedPresence[1]);
      expect(pm2.action, equals(PresenceAction.enter));
      expect(pm2.clientId, equals('user-bob'));
      expect(pm2.data, equals('bob-data'));

      mockWs.dispose();
    });
  });

  group('RTP15a - updateClient and leaveClient', () {
    // UTS: realtime/unit/RTP15a/updateclient-leaveclient-0
    test('sends UPDATE and LEAVE with specified clientId', () async {
      final channelName = testChannelName('RTP15a');

      final capturedPresence = <ProtocolMessage>[];
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
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

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

      await channel.presence.enterClient('user-1', 'entered');
      await channel.presence.updateClient('user-1', 'updated');
      await channel.presence.leaveClient('user-1', 'leaving');

      expect(capturedPresence.length, equals(3));

      final pm1 = _decodePresence(capturedPresence[0]);
      expect(pm1.action, equals(PresenceAction.enter));
      expect(pm1.clientId, equals('user-1'));
      expect(pm1.data, equals('entered'));

      final pm2 = _decodePresence(capturedPresence[1]);
      expect(pm2.action, equals(PresenceAction.update));
      expect(pm2.clientId, equals('user-1'));
      expect(pm2.data, equals('updated'));

      final pm3 = _decodePresence(capturedPresence[2]);
      expect(pm3.action, equals(PresenceAction.leave));
      expect(pm3.clientId, equals('user-1'));
      expect(pm3.data, equals('leaving'));

      mockWs.dispose();
    });
  });

  group('RTP15e - enterClient implicitly attaches channel', () {
    // UTS: realtime/unit/RTP15e/enterclient-implicitly-attaches-0
    test('INITIALIZED channel becomes ATTACHED', () async {
      final channelName = testChannelName('RTP15e');

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
          } else if (msg.action == ProtocolAction.presence) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

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

      expect(channel.state, equals(ChannelState.initialized));

      await channel.presence.enterClient('user-1');

      expect(channel.state, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTP15f - enterClient with mismatched clientId errors', () {
    // UTS: realtime/unit/RTP15f/enterclient-mismatched-clientid-0
    test('errors when connection clientId does not match', () async {
      final channelName = testChannelName('RTP15f');

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

      // enterClient with a different clientId than the connection's clientId
      expect(
        () => channel.presence.enterClient('other-client'),
        throwsA(isA<AblyException>()),
      );

      // Connection and channel remain available
      expect(client.connection.state, equals(ConnectionState.connected));
      expect(channel.state, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  group('RTP16a - Presence message sent when channel is ATTACHED', () {
    // UTS: realtime/unit/RTP16a/presence-sent-when-attached-0
    test('message is sent immediately', () async {
      final channelName = testChannelName('RTP16a');

      final capturedPresence = <ProtocolMessage>[];
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

      await channel.presence.enter();

      // Message was sent immediately
      expect(capturedPresence.length, equals(1));

      mockWs.dispose();
    });
  });

  group('RTP16b - Presence message queued when channel is ATTACHING', () {
    // UTS: realtime/unit/RTP16b/presence-queued-when-attaching-0
    test('queued messages sent after attach completes', () async {
      final channelName = testChannelName('RTP16b');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Delay the ATTACHED response — don't respond immediately
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

      // Start attach but don't complete it
      unawaited(channel.attach());
      await _awaitChannelState(channel, ChannelState.attaching);

      // Queue presence while ATTACHING
      final enterFuture = channel.presence.enter();

      // No messages sent yet
      expect(capturedPresence.length, equals(0));

      // Now complete the attach
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(channel: channelName),
      );

      await enterFuture;

      // Queued presence message was sent after attach completed
      expect(capturedPresence.length, equals(1));
      final pm = _decodePresence(capturedPresence[0]);
      expect(pm.action, equals(PresenceAction.enter));

      mockWs.dispose();
    });
  });

  group('RTP16c - Presence message errors in other channel states', () {
    // UTS: realtime/unit/RTP16c/presence-errors-other-states-0
    test('errors when channel is DETACHED', () async {
      final channelName = testChannelName('RTP16c');

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
              ProtocolMessageHelpers.detached(
                channel: channelName,
                error: const ErrorInfo(code: 90001, message: 'Detached'),
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

      // Put channel in non-attached state
      try {
        await channel.attach();
      } catch (_) {}

      // Whether DETACHED or SUSPENDED, enter() should error
      expect(
        channel.state,
        anyOf(
          equals(ChannelState.detached),
          equals(ChannelState.suspended),
        ),
      );

      expect(
        () => channel.presence.enter(),
        throwsA(isA<AblyException>()),
      );

      mockWs.dispose();
    });
  });

  group('RTP15c - enterClient has no side effects on normal enter', () {
    // UTS: realtime/unit/RTP15c/enterclient-no-side-effects-0
    test('enterClient/leaveClient do not affect normal enter', () async {
      final channelName = testChannelName('RTP15c');

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
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

      // Normal enter for the wildcard client
      await channel.presence.enterClient('*', 'main-client');

      // enterClient for a different user
      await channel.presence.enterClient('other-user', 'other-data');

      // leaveClient for the other user
      await channel.presence.leaveClient('other-user');

      // Three presence messages sent
      expect(capturedPresence.length, equals(3));

      final pm1 = _decodePresence(capturedPresence[0]);
      expect(pm1.action, equals(PresenceAction.enter));
      expect(pm1.data, equals('main-client'));
      expect(pm1.clientId, equals('*'));

      final pm2 = _decodePresence(capturedPresence[1]);
      expect(pm2.action, equals(PresenceAction.enter));
      expect(pm2.clientId, equals('other-user'));

      final pm3 = _decodePresence(capturedPresence[2]);
      expect(pm3.action, equals(PresenceAction.leave));
      expect(pm3.clientId, equals('other-user'));

      mockWs.dispose();
    });
  });

  group('RTP4 - Bulk enterClient (same connection)', () {
    // UTS: realtime/unit/RTP4/bulk-enterclient-same-connection-0
    test('50 members via enterClient with SYNC and get', () async {
      final channelName = testChannelName('RTP4-same');
      const memberCount = 50;

      final capturedPresence = <ProtocolMessage>[];
      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-1'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresence.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );

            // Server echoes back the ENTER as a PRESENCE event
            final presenceList = msg.presence!;
            for (var idx = 0; idx < presenceList.length; idx++) {
              final raw = presenceList[idx];
              final p = raw is PresenceMessage
                  ? raw
                  : PresenceMessage.fromMap(raw as Map<String, dynamic>);
              mockWs.activeConnection!.sendToClient(
                ProtocolMessage(
                  action: ProtocolAction.presence,
                  channel: channelName,
                  presence: [
                    PresenceMessage(
                      action: PresenceAction.enter,
                      clientId: p.clientId,
                      connectionId: 'conn-1',
                      id: 'conn-1:${msg.msgSerial}:$idx',
                      timestamp: DateTime.now(),
                      data: p.data,
                    ),
                  ],
                ),
              );
            }
          }
        },
      );

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

      // Track ENTER events received by subscriber
      final receivedEnters = <PresenceMessage>[];
      channel.presence.subscribe(
        (event) => receivedEnters.add(event),
        action: PresenceAction.enter,
      );

      // Enter 50 members
      for (var i = 0; i < memberCount; i++) {
        await channel.presence.enterClient('user-$i', 'data-$i');
      }

      // Send a complete SYNC with all 50 members as PRESENT
      final syncMembers = <PresenceMessage>[];
      for (var i = 0; i < memberCount; i++) {
        syncMembers.add(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'user-$i',
            connectionId: 'conn-1',
            id: 'conn-1:$i:0',
            timestamp: DateTime.now(),
            data: 'data-$i',
          ),
        );
      }

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.sync,
          channel: channelName,
          channelSerial: 'seq1:',
          presence: syncMembers,
        ),
      );

      // Get all members after sync
      final members = await channel.presence.get();

      // All 50 members entered
      expect(capturedPresence.length, equals(memberCount));

      // All 50 ENTER events received by subscriber
      expect(receivedEnters.length, equals(memberCount));

      // All 50 members present after sync
      expect(members.length, equals(memberCount));

      // Verify each member exists with correct data
      for (var i = 0; i < memberCount; i++) {
        final member = members.where((m) => m.clientId == 'user-$i');
        expect(
          member.isNotEmpty,
          isTrue,
          reason: 'Member user-$i should be present',
        );
        expect(member.first.data, equals('data-$i'));
      }

      mockWs.dispose();
    });
  });

  group('RTP4 - Bulk enterClient (different connections)', () {
    // UTS: realtime/unit/RTP4/bulk-enterclient-diff-connections-1
    test('client A enters 50 members, client B observes via subscribe and get',
        () async {
      final channelName = testChannelName('RTP4-diff');
      const memberCount = 50;

      // --- Connection A: the entering client ---
      final capturedPresenceA = <ProtocolMessage>[];
      late final MockWebSocketClient mockWsA;
      mockWsA = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-A'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWsA.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
          } else if (msg.action == ProtocolAction.presence) {
            capturedPresenceA.add(msg);
            mockWsA.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(msgSerial: msg.msgSerial!),
            );
          }
        },
      );

      // --- Connection B: the observing client ---
      late final MockWebSocketClient mockWsB;
      mockWsB = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(connectionId: 'conn-B'),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWsB.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: flagHasPresence,
              ),
            );
          }
        },
      );

      final clientA = RealtimeClient.forTesting(
        options: _optionsWithClientId('*'),
        webSocketClient: mockWsA,
      );
      final clientB = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWsB,
      );

      final channelA = clientA.channels.get(channelName);
      final channelB = clientB.channels.get(channelName);

      // Connect and attach both clients
      clientA.connect();
      await _awaitConnectionState(
        clientA.connection,
        ConnectionState.connected,
      );
      await channelA.attach();

      clientB.connect();
      await _awaitConnectionState(
        clientB.connection,
        ConnectionState.connected,
      );
      await channelB.attach();

      // Subscribe on client B to observe remote presence events
      final receivedEntersB = <PresenceMessage>[];
      channelB.presence.subscribe(
        (event) => receivedEntersB.add(event),
        action: PresenceAction.enter,
      );

      // Client A enters 50 members
      for (var i = 0; i < memberCount; i++) {
        await channelA.presence.enterClient('user-$i', 'data-$i');
      }

      // Server delivers those ENTER events to client B as PRESENCE messages
      for (var i = 0; i < memberCount; i++) {
        mockWsB.activeConnection!.sendToClient(
          ProtocolMessage(
            action: ProtocolAction.presence,
            channel: channelName,
            presence: [
              PresenceMessage(
                action: PresenceAction.enter,
                clientId: 'user-$i',
                connectionId: 'conn-A',
                id: 'conn-A:$i:0',
                timestamp: DateTime.now(),
                data: 'data-$i',
              ),
            ],
          ),
        );
      }

      // Server sends a SYNC to client B with all 50 members
      final syncMembers = <PresenceMessage>[];
      for (var i = 0; i < memberCount; i++) {
        syncMembers.add(
          PresenceMessage(
            action: PresenceAction.present,
            clientId: 'user-$i',
            connectionId: 'conn-A',
            id: 'conn-A:$i:0',
            timestamp: DateTime.now(),
            data: 'data-$i',
          ),
        );
      }

      mockWsB.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.sync,
          channel: channelName,
          channelSerial: 'seq1:',
          presence: syncMembers,
        ),
      );

      // Client B gets all members
      final members = await channelB.presence.get();

      // Client A sent all 50 presence messages
      expect(capturedPresenceA.length, equals(memberCount));

      // Client B received all 50 ENTER events
      expect(receivedEntersB.length, equals(memberCount));

      // All 50 members present via get() on client B
      expect(members.length, equals(memberCount));

      // Verify each member has correct data and connectionId from conn-A
      for (var i = 0; i < memberCount; i++) {
        final member = members.where((m) => m.clientId == 'user-$i');
        expect(
          member.isNotEmpty,
          isTrue,
          reason: 'Member user-$i should be present',
        );
        expect(member.first.data, equals('data-$i'));
        expect(member.first.connectionId, equals('conn-A'));
      }

      mockWsA.dispose();
      mockWsB.dispose();
    });
  });
}

/// Creates ClientOptions with a clientId using authCallback to avoid real HTTP
/// requests. Setting clientId on ClientOptions triggers token auth (RSA4b),
/// which would normally make HTTP requests to obtain a token. The authCallback
/// provides a fake token locally instead.
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

/// Decodes the first presence message from a captured ProtocolMessage.
PresenceMessage _decodePresence(ProtocolMessage protocolMessage) {
  final raw = protocolMessage.presence![0];
  if (raw is PresenceMessage) return raw;
  return PresenceMessage.fromMap(raw as Map<String, dynamic>);
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

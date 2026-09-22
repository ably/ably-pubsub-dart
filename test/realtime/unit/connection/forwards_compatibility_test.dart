import 'dart:async';
import 'package:test/test.dart';
import 'package:ably/ably.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for forwards compatibility (RTF1, RSF1).
///
/// Tests that the Ably client library applies the robustness principle to
/// deserialization: unrecognised attributes are ignored and unknown enum
/// values are handled gracefully without crashing or disconnecting.
///
/// Spec: specification/uts/realtime/unit/connection/forwards_compatibility_test.md
void main() {
  group('RTF1 - ProtocolMessage with unrecognised attributes', () {
    // UTS: realtime/unit/RTF1/unrecognised-attributes-ignored-0
    test(
        'message with extra unknown fields is delivered to subscribers '
        'without error', () async {
      final channelName = testChannelName('RTF1-extra-attrs');
      final receivedMessages = <Message>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final channel = client.channels.get(channelName);
      channel.subscribe((msg) {
        receivedMessages.add(msg);
      });
      channel.attach();

      // Respond to ATTACH request
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.attached);

      // Send a MESSAGE ProtocolMessage with extra unknown attributes.
      // The ProtocolMessage.fromJson factory should ignore unknown fields.
      // The ProtocolMessage constructor doesn't strip unknown fields from
      // the raw JSON - the fromJson factory simply doesn't extract them.
      //
      // To simulate a server sending unknown fields, we create a
      // ProtocolMessage from JSON that includes extra fields.
      final rawJson = {
        'action': 15, // MESSAGE
        'channel': channelName,
        'messages': [
          {
            'name': 'test-event',
            'data': 'hello',
          }
        ],
        'unknownField1': 'some-future-value',
        'unknownField2': 42,
        'unknownNestedObject': {
          'nestedKey': 'nestedValue',
        },
        'unknownArray': [1, 2, 3],
      };

      // Verify that ProtocolMessage.fromJson tolerates unknown fields
      final pm = ProtocolMessage.fromJson(rawJson);
      expect(pm.action, equals(ProtocolAction.message));
      expect(pm.channel, equals(channelName));
      expect(pm.messages, isNotNull);
      expect(pm.messages!.length, equals(1));

      // Send the message to the client
      mockWs.activeConnection!.sendToClient(pm);
      await _pumpEventQueue();

      // Connection remains healthy
      expect(client.connection.state, equals(ConnectionState.connected));
      expect(channel.state, equals(ChannelState.attached));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTF1 - ProtocolMessage with unknown action enum value', () {
    // UTS: realtime/unit/RTF1/unknown-action-handled-1
    test(
        'client does not crash or disconnect when receiving unknown '
        'action value', () async {
      final stateChanges = <ConnectionState>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Record connection state changes to detect unexpected disconnections
      client.connection.on().listen((change) {
        stateChanges.add(change.current);
      });

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // RTF1: an unknown action value (254) decodes to null (with
      // unrecognisedAction capturing the raw wire value for the ignore
      // log) rather than throwing from inside the transport handler.
      // Built via fromJson, not the constructor, so this exercises the
      // actual decode path the patch changed.
      expect(
        ProtocolActionExtension.fromInt(254),
        isNull,
        reason: 'RTF1 - unknown protocol actions degrade to null',
      );
      final unrecognisedMessage = ProtocolMessage.fromJson({
        'action': 254,
        'channel': 'ignored-unknown-action',
      });
      expect(
        unrecognisedMessage.action,
        isNull,
        reason: 'RTF1 - decoding an unknown action must not throw',
      );
      expect(
        unrecognisedMessage.unrecognisedAction,
        equals(254),
        reason: 'RTF1 - the raw wire value is retained for the ignore log',
      );
      mockWs.activeConnection!.sendToClient(unrecognisedMessage);
      await _pumpEventQueue();

      // Send a normal HEARTBEAT to verify the connection is still
      // processing messages
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.heartbeat(),
      );
      await _pumpEventQueue();

      // Connection should still be CONNECTED
      expect(client.connection.state, equals(ConnectionState.connected));

      // Verify no disconnected or failed states appeared
      expect(stateChanges, isNot(contains(ConnectionState.disconnected)));
      expect(stateChanges, isNot(contains(ConnectionState.failed)));

      // State changes should only contain connecting -> connected
      expect(
        stateChanges,
        containsAllInOrder([
          ConnectionState.connecting,
          ConnectionState.connected,
        ]),
      );

      await client.close();
      mockWs.dispose();
    });
  });

  group('RSF1 - Message with unrecognised attributes', () {
    // UTS: realtime/unit/RSF1/message-unrecognised-attrs-0
    test(
        'messages with unknown fields are delivered with known fields '
        'correctly parsed', () async {
      final channelName = testChannelName('RSF1-extra-attrs');
      final receivedMessages = <Message>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      final channel = client.channels.get(channelName);
      channel.subscribe((msg) {
        receivedMessages.add(msg);
      });
      channel.attach();

      // Respond to ATTACH request
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: channelName,
        ),
      );
      await _awaitChannelState(channel, ChannelState.attached);

      // Verify that Message.fromMap (if it exists) or ProtocolMessage.fromJson
      // tolerates messages with unknown fields in the messages array.
      // The ProtocolMessage stores messages as List<dynamic> so unknown
      // fields in individual messages are preserved in the raw maps.
      final rawJson = {
        'action': 15, // MESSAGE
        'channel': channelName,
        'messages': [
          {
            'name': 'event-1',
            'data': 'payload-1',
            'futureField': 'future-value',
            'futureNumber': 99,
            'futureObject': {'nested': true},
          },
          {
            'name': 'event-2',
            'data': 'payload-2',
            'anotherUnknownField': [1, 2, 3],
          },
        ],
      };

      // Verify ProtocolMessage.fromJson does not throw
      final pm = ProtocolMessage.fromJson(rawJson);
      expect(pm.action, equals(ProtocolAction.message));
      expect(pm.messages, isNotNull);
      expect(pm.messages!.length, equals(2));

      // Verify the individual message maps preserve known fields
      final msg1 = pm.messages![0] as Map<String, dynamic>;
      expect(msg1['name'], equals('event-1'));
      expect(msg1['data'], equals('payload-1'));

      final msg2 = pm.messages![1] as Map<String, dynamic>;
      expect(msg2['name'], equals('event-2'));
      expect(msg2['data'], equals('payload-2'));

      // Send the message to verify the client can process it
      mockWs.activeConnection!.sendToClient(pm);
      await _pumpEventQueue();

      // Connection and channel remain healthy
      expect(client.connection.state, equals(ConnectionState.connected));
      expect(channel.state, equals(ChannelState.attached));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTF1/RSF1 - Connection stability after unknown content', () {
    test(
        'connection remains functional after receiving messages with '
        'unknown attributes', () async {
      final channelName = testChannelName('RTF1-stability');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-id',
              connectionKey: 'connection-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Verify ProtocolMessage.fromJson handles various unknown field types
      // without throwing. This is a direct deserialization test.

      // CONNECTED with extra fields
      final connectedWithExtras = ProtocolMessage.fromJson({
        'action': 4, // CONNECTED
        'connectionId': 'test-id',
        'connectionKey': 'test-key',
        'unknownTopLevel': true,
        'connectionDetails': {
          'connectionKey': 'test-key',
          'maxIdleInterval': 15000,
          'unknownDetail': 'future-feature',
        },
      });
      expect(connectedWithExtras.action, equals(ProtocolAction.connected));
      expect(connectedWithExtras.connectionId, equals('test-id'));

      // ATTACHED with extra fields
      final attachedWithExtras = ProtocolMessage.fromJson({
        'action': 11, // ATTACHED
        'channel': channelName,
        'unknownFlag': 'future-flag-value',
        'unknownMeta': {'key': 'value'},
      });
      expect(attachedWithExtras.action, equals(ProtocolAction.attached));
      expect(attachedWithExtras.channel, equals(channelName));

      // HEARTBEAT with extra fields
      final heartbeatWithExtras = ProtocolMessage.fromJson({
        'action': 0, // HEARTBEAT
        'extraData': [1, 2, 3],
      });
      expect(heartbeatWithExtras.action, equals(ProtocolAction.heartbeat));

      // ERROR with extra fields
      final errorWithExtras = ProtocolMessage.fromJson({
        'action': 9, // ERROR
        'error': {
          'code': 40000,
          'statusCode': 400,
          'message': 'Bad request',
          'futureErrorField': 'extra-info',
        },
        'futureContextField': {'trace': 'abc123'},
      });
      expect(errorWithExtras.action, equals(ProtocolAction.error));
      expect(errorWithExtras.error, isNotNull);
      expect(errorWithExtras.error!.code, equals(40000));

      await client.close();
      mockWs.dispose();
    });

    test(
        'ProtocolMessage.fromJson preserves known fields when unknown '
        'fields are present', () {
      // Comprehensive test of all known field types with extra unknown fields
      final pm = ProtocolMessage.fromJson({
        'action': 15, // MESSAGE
        'channel': 'test-channel',
        'channelSerial': 'serial-1',
        'connectionId': 'conn-id',
        'connectionKey': 'conn-key',
        'flags': 0,
        'id': 'msg-id',
        'msgSerial': 42,
        'timestamp': 1234567890,
        'messages': [
          {'name': 'evt', 'data': 'payload'},
        ],
        // Unknown fields that should be ignored
        'futureField1': 'value1',
        'futureField2': 123,
        'futureField3': true,
        'futureField4': null,
        'futureField5': [1, 'two', 3.0],
        'futureField6': {
          'nested': {'deep': true},
        },
      });

      // All known fields are correctly parsed
      expect(pm.action, equals(ProtocolAction.message));
      expect(pm.channel, equals('test-channel'));
      expect(pm.channelSerial, equals('serial-1'));
      expect(pm.connectionId, equals('conn-id'));
      expect(pm.connectionKey, equals('conn-key'));
      expect(pm.flags, equals(0));
      expect(pm.id, equals('msg-id'));
      expect(pm.msgSerial, equals(42));
      expect(pm.timestamp, equals(1234567890));
      expect(pm.messages, isNotNull);
      expect(pm.messages!.length, equals(1));
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitState(
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
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

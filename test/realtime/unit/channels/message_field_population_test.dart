import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for message field population from ProtocolMessage
/// (TM2a, TM2c, TM2f).
///
/// When a realtime client receives a ProtocolMessage containing messages,
/// certain fields on individual messages may be absent. The spec requires
/// the SDK to populate these from the encapsulating ProtocolMessage before
/// delivering to subscribers:
///
/// | Spec | Field        | Fallback                                    |
/// |------|--------------|---------------------------------------------|
/// | TM2a | id           | `protocolMsgId:index` (0-based)             |
/// | TM2c | connectionId | ProtocolMessage `connectionId`              |
/// | TM2f | timestamp    | ProtocolMessage `timestamp`                 |
///
/// Spec: specification/uts/realtime/unit/channels/message_field_population.md
void main() {
  // ---------------------------------------------------------------------------
  // TM2a - Message id populated from ProtocolMessage id and index
  // ---------------------------------------------------------------------------

  group('TM2a - Message id populated from ProtocolMessage id and index', () {
    // UTS: realtime/unit/TM2a/id-from-protocol-message-0
    test('computes id as protocolMessageId:index for each message', () async {
      final channelName = testChannelName('TM2a-id');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send a ProtocolMessage with 3 messages that have no id field.
      // The ProtocolMessage itself has id "abc123:5".
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'abc123:5',
          connectionId: 'abc123',
          timestamp: 1700000000000,
          messages: [
            const Message(name: 'first', data: 'a'),
            const Message(name: 'second', data: 'b'),
            const Message(name: 'third', data: 'c'),
          ],
        ),
      );

      expect(received, hasLength(3));

      // Each message id is computed as protocolMessageId:index
      expect(received[0].id, equals('abc123:5:0'));
      expect(received[1].id, equals('abc123:5:1'));
      expect(received[2].id, equals('abc123:5:2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2a - Message with existing id is not overwritten
  // ---------------------------------------------------------------------------

  group('TM2a - Message with existing id is not overwritten', () {
    // UTS: realtime/unit/TM2a/existing-id-not-overwritten-1
    test('retains original id when message already has one', () async {
      final channelName = testChannelName('TM2a-existing');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message already has its own id -- should not be overwritten
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'proto-id:0',
          messages: [
            const Message(id: 'my-custom-id', name: 'msg', data: 'hello'),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].id, equals('my-custom-id'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2a - No id when ProtocolMessage has no id
  // ---------------------------------------------------------------------------

  group('TM2a - No id when ProtocolMessage has no id', () {
    // UTS: realtime/unit/TM2a/no-id-without-protocol-id-2
    test('message id remains null when ProtocolMessage has no id', () async {
      final channelName = testChannelName('TM2a-no-proto-id');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // ProtocolMessage has no id field -- messages should not get computed ids
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          connectionId: 'abc123',
          messages: [
            const Message(name: 'msg', data: 'hello'),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].id, isNull);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2c - Message connectionId populated from ProtocolMessage
  // ---------------------------------------------------------------------------

  group('TM2c - Message connectionId populated from ProtocolMessage', () {
    // UTS: realtime/unit/TM2c/connectionid-from-protocol-0
    test('inherits connectionId from ProtocolMessage when absent', () async {
      final channelName = testChannelName('TM2c-connId');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message has no connectionId -- should inherit from ProtocolMessage
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg:0',
          connectionId: 'server-conn-xyz',
          messages: [
            const Message(name: 'msg', data: 'hello'),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].connectionId, equals('server-conn-xyz'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2c - Message with existing connectionId is not overwritten
  // ---------------------------------------------------------------------------

  group('TM2c - Message with existing connectionId is not overwritten', () {
    // UTS: realtime/unit/TM2c/existing-connectionid-kept-1
    test('retains original connectionId when message already has one',
        () async {
      final channelName = testChannelName('TM2c-existing');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message already has its own connectionId -- should not be overwritten
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg:0',
          connectionId: 'proto-conn',
          messages: [
            const Message(
              connectionId: 'msg-conn',
              name: 'msg',
              data: 'hello',
            ),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].connectionId, equals('msg-conn'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2f - Message timestamp populated from ProtocolMessage
  // ---------------------------------------------------------------------------

  group('TM2f - Message timestamp populated from ProtocolMessage', () {
    // UTS: realtime/unit/TM2f/timestamp-from-protocol-0
    test('inherits timestamp from ProtocolMessage when absent', () async {
      final channelName = testChannelName('TM2f-timestamp');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message has no timestamp -- should inherit from ProtocolMessage
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg:0',
          timestamp: 1700000000000,
          messages: [
            const Message(name: 'msg', data: 'hello'),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].timestamp, equals(1700000000000));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2f - Message with existing timestamp is not overwritten
  // ---------------------------------------------------------------------------

  group('TM2f - Message with existing timestamp is not overwritten', () {
    // UTS: realtime/unit/TM2f/existing-timestamp-kept-1
    test('retains original timestamp when message already has one', () async {
      final channelName = testChannelName('TM2f-existing');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message already has its own timestamp -- should not be overwritten
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg:0',
          timestamp: 1700000000000,
          messages: [
            const Message(timestamp: 1600000000000, name: 'msg', data: 'hello'),
          ],
        ),
      );

      expect(received, hasLength(1));
      expect(received[0].timestamp, equals(1600000000000));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // TM2a, TM2c, TM2f - All fields populated together
  // ---------------------------------------------------------------------------

  group('TM2a, TM2c, TM2f - All fields populated together', () {
    // UTS: realtime/unit/TM2a/all-fields-populated-together-3
    test(
        'populates id, connectionId, and timestamp from ProtocolMessage '
        'for multiple messages', () async {
      final channelName = testChannelName('TM2-all-fields');

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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final received = <Message>[];
      channel.subscribe((message) => received.add(message));

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // ProtocolMessage with all parent fields set, messages with none
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'connId:7',
          connectionId: 'connId',
          timestamp: 1700000000000,
          messages: [
            const Message(name: 'first', data: 'a'),
            const Message(name: 'second', data: 'b'),
          ],
        ),
      );

      expect(received, hasLength(2));

      // First message
      expect(received[0].id, equals('connId:7:0'));
      expect(received[0].connectionId, equals('connId'));
      expect(received[0].timestamp, equals(1700000000000));
      expect(received[0].name, equals('first'));
      expect(received[0].data, equals('a'));

      // Second message -- same connectionId and timestamp, different id index
      expect(received[1].id, equals('connId:7:1'));
      expect(received[1].connectionId, equals('connId'));
      expect(received[1].timestamp, equals(1700000000000));
      expect(received[1].name, equals('second'));
      expect(received[1].data, equals('b'));

      mockWs.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Private helpers (copied per project convention)
// ---------------------------------------------------------------------------

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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_vcdiff.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for vcdiff delta decoding on realtime channels.
///
/// Spec: RTL18, RTL18a, RTL18b, RTL18c, RTL19, RTL19a, RTL19b, RTL19c,
///       RTL20, RTL21, PC3, PC3a
///
/// UTS spec: uts/test/realtime/unit/channels/channel_delta_decoding.md
void main() {
  group('RTL21 - Messages in array decoded in ascending index order', () {
    // UTS: realtime/unit/RTL21/ascending-index-order-0
    test('multi-message ProtocolMessage with chained deltas decodes correctly',
        () async {
      final channelName = testChannelName('RTL21-order');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // 3 messages: non-delta base, then two chained deltas
      const baseData = 'first message';
      const secondData = 'second message';
      const thirdData = 'third message';

      final delta1To2 = encoder.encodeString(baseData, secondData);
      final delta2To3 = encoder.encodeString(secondData, thirdData);

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'serial:0',
          messages: [
            {'id': 'serial:0', 'data': baseData},
            {
              'id': 'serial:1',
              'data': delta1To2,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'serial:0', 'format': 'vcdiff'},
              },
            },
            {
              'id': 'serial:2',
              'data': delta2To3,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'serial:1', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedMessages.length, equals(3));
      expect(receivedMessages[0].data, equals('first message'));
      expect(receivedMessages[1].data, equals('second message'));
      expect(receivedMessages[2].data, equals('third message'));
    });
  });

  group('RTL19b - Non-delta message stores base payload', () {
    // UTS: realtime/unit/RTL19b/stores-base-payload-0
    test('non-delta message data used as base for subsequent delta', () async {
      final channelName = testChannelName('RTL19b-base');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send non-delta to establish base
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          messages: [
            {'id': 'msg-1:0', 'data': 'base payload'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // Send delta referencing the base
      final delta = encoder.encodeString('base payload', 'updated payload');

      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': delta,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedMessages.length, equals(2));
      expect(receivedMessages[0].data, equals('base payload'));
      expect(receivedMessages[1].data, equals('updated payload'));
    });
  });

  group('RTL19a - Base64 encoding decoded before storing base payload', () {
    // UTS: realtime/unit/RTL19a/base64-decoded-before-store-0
    test('base64-encoded binary base used for subsequent delta', () async {
      final channelName = testChannelName('RTL19a-base64');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Binary base data: "Hello" as bytes
      final baseBinary = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
      final baseAsBase64 = base64.encode(baseBinary);

      // Send base64-encoded non-delta message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          messages: [
            {'id': 'msg-1:0', 'data': baseAsBase64, 'encoding': 'base64'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // New binary value: "World" as bytes
      final newBinary = Uint8List.fromList([0x57, 0x6F, 0x72, 0x6C, 0x64]);
      final delta = encoder.encodeBinary(baseBinary, newBinary);

      // Send delta with vcdiff/base64 encoding (base64 outermost)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': base64.encode(delta),
              'encoding': 'vcdiff/base64',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedMessages.length, equals(2));
      expect(receivedMessages[0].data, equals(baseBinary));
      expect(receivedMessages[1].data, equals(newBinary));
    });
  });

  group('RTL19c - Delta result stored as new base payload', () {
    // UTS: realtime/unit/RTL19c/delta-result-becomes-base-0
    test('chained deltas across separate ProtocolMessages', () async {
      final channelName = testChannelName('RTL19c-chain');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Message 1: non-delta base
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          messages: [
            {'id': 'msg-1:0', 'data': 'value-A'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // Message 2: delta A→B
      final deltaAToB = encoder.encodeString('value-A', 'value-B');
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': deltaAToB,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(2));

      // Message 3: delta B→C (base should now be value-B)
      final deltaBToC = encoder.encodeString('value-B', 'value-C');
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-3:0',
          messages: [
            {
              'id': 'msg-3:0',
              'data': deltaBToC,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'msg-2:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedMessages.length, equals(3));
      expect(receivedMessages[0].data, equals('value-A'));
      expect(receivedMessages[1].data, equals('value-B'));
      expect(receivedMessages[2].data, equals('value-C'));
    });
  });

  group('RTL20 - Delta with mismatched base message ID triggers recovery', () {
    // UTS: realtime/unit/RTL20/mismatched-id-triggers-recovery-0
    test('mismatched delta.from triggers ATTACHING with correct channelSerial',
        () async {
      final channelName = testChannelName('RTL20-mismatch');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final stateChanges = <ChannelStateChange>[];
      final attachMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.on().listen(stateChanges.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Establish base with msg-1
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          channelSerial: 'serial-1',
          messages: [
            {'id': 'msg-1:0', 'data': 'base payload'},
          ],
        ),
      );

      await _pumpEventQueue();

      // Clear tracking
      stateChanges.clear();
      final initialAttachCount = attachMessages.length;

      // Send delta referencing wrong message ID
      final delta = encoder.encodeString('base payload', 'new payload');
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': delta,
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-999:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      // Recovery: ATTACHING → ATTACHED (auto-responded by mock)
      await _pumpEventQueue();

      // A new ATTACH was sent for recovery
      expect(attachMessages.length, greaterThan(initialAttachCount));

      // The recovery ATTACH includes channelSerial from previous message
      final recoveryAttach = attachMessages.last;
      expect(recoveryAttach.channelSerial, equals('serial-1'));

      // Channel went through ATTACHING with error code 40018
      final attachingChange =
          stateChanges.where((c) => c.current == ChannelState.attaching).first;
      expect(attachingChange.reason?.code, equals(40018));
    });
  });

  group('RTL20 - Last message ID updated after successful decode', () {
    // UTS: realtime/unit/RTL20/last-id-updated-on-decode-1
    test('stored ID is last message in ProtocolMessage array', () async {
      final channelName = testChannelName('RTL20-id-update');
      final encoder = MockVCDiffEncoder();
      final decoder = MockVCDiffDecoder();

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send ProtocolMessage with 2 messages — stored ID should be serial:1
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'serial:0',
          messages: [
            {'id': 'serial:0', 'data': 'first'},
            {'id': 'serial:1', 'data': 'second'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(2));

      // Send delta referencing serial:1 — should succeed
      final delta = encoder.encodeString('second', 'third');
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': delta,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'serial:1', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedMessages.length, equals(3));
      expect(receivedMessages[0].data, equals('first'));
      expect(receivedMessages[1].data, equals('second'));
      expect(receivedMessages[2].data, equals('third'));
    });
  });

  group('PC3, PC3a - VCDiff plugin decodes delta messages', () {
    // UTS: realtime/unit/PC3/vcdiff-plugin-decodes-0
    test('string base is UTF-8 encoded before passing to decoder', () async {
      final channelName = testChannelName('PC3-decode');
      final encoder = MockVCDiffEncoder();

      final decodeCalls = <({Uint8List delta, Uint8List base})>[];
      final decoder = MockVCDiffDecoder(
        onDecode: (delta, base) {
          decodeCalls.add(
            (delta: Uint8List.fromList(delta), base: Uint8List.fromList(base)),
          );
        },
      );

      final receivedMessages = <Message>[];

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
          plugins: {'vcdiff': decoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send string non-delta message (establishes string base)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          messages: [
            {'id': 'msg-1:0', 'data': 'hello world'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // Send delta referencing string base
      final delta = encoder.encodeString('hello world', 'goodbye world');
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': delta,
              'encoding': 'utf-8/vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // PC3: Decoder was called
      expect(decodeCalls.length, equals(1));

      // PC3a: Base was UTF-8 encoded from string
      expect(
        decodeCalls[0].base,
        equals(Uint8List.fromList(utf8.encode('hello world'))),
      );

      // The decoded message was delivered
      expect(receivedMessages.length, equals(2));
      expect(receivedMessages[1].data, equals('goodbye world'));
    });
  });

  group('PC3 - No vcdiff plugin causes FAILED state', () {
    // UTS: realtime/unit/PC3/no-plugin-fails-1
    test('delta message without plugin transitions channel to FAILED',
        () async {
      final channelName = testChannelName('PC3-no-plugin');

      final stateChanges = <ChannelStateChange>[];

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

      // No vcdiff plugin
      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.on().listen(stateChanges.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Send non-delta to establish _lastPayloadMessageId
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-0:0',
          messages: [
            {'id': 'msg-0:0', 'data': 'base'},
          ],
        ),
      );

      await _pumpEventQueue();
      stateChanges.clear();

      // Send delta-encoded message without plugin
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          messages: [
            {
              'id': 'msg-1:0',
              'data': 'some-delta-data',
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-0:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.failed));
      expect(channel.errorReason?.code, equals(40019));
    });
  });

  group('RTL18 - Decode failure triggers recovery', () {
    // UTS: realtime/unit/RTL18/decode-failure-recovery-0
    test('RTL18a/b/c: failed decode discards message and sends recovery ATTACH',
        () async {
      final channelName = testChannelName('RTL18-recovery');

      final stateChanges = <ChannelStateChange>[];
      final attachMessages = <ProtocolMessage>[];
      final receivedMessages = <Message>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: channelName),
            );
          }
        },
      );

      // Decoder that always fails
      final failingDecoder = FailingMockVCDiffDecoder();

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          plugins: {'vcdiff': failingDecoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.on().listen(stateChanges.add);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Establish base with non-delta message
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          channelSerial: 'serial-100',
          messages: [
            {'id': 'msg-1:0', 'data': 'base payload'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // Clear tracking
      stateChanges.clear();
      final initialAttachCount = attachMessages.length;

      // Send delta — failing decoder will throw
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          channelSerial: 'serial-200',
          messages: [
            {
              'id': 'msg-2:0',
              'data': 'fake-delta-payload',
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // RTL18b: Failed delta was NOT delivered
      expect(receivedMessages.length, equals(1));
      expect(receivedMessages[0].data, equals('base payload'));

      // RTL18c: New ATTACH was sent for recovery
      expect(attachMessages.length, greaterThan(initialAttachCount));
      final recoveryAttach = attachMessages.last;

      // RTL18c: ATTACH includes channelSerial from previous successful message
      expect(recoveryAttach.channelSerial, equals('serial-100'));

      // RTL18c: Channel went to ATTACHING with error code 40018
      final attachingChange =
          stateChanges.where((c) => c.current == ChannelState.attaching).first;
      expect(attachingChange.reason?.code, equals(40018));
    });
  });

  group('RTL18c - Recovery completes when server sends ATTACHED', () {
    // UTS: realtime/unit/RTL18c/recovery-completes-on-attached-0
    test('channel returns to ATTACHED and receives new messages after recovery',
        () async {
      final channelName = testChannelName('RTL18c-complete');

      final receivedMessages = <Message>[];
      var decodeAttempt = 0;

      // Decoder that fails on first call, succeeds afterwards
      final conditionalDecoder = MockVCDiffDecoder(
        onDecode: (delta, base) {
          decodeAttempt++;
          if (decodeAttempt == 1) {
            throw Exception('Simulated decode failure');
          }
        },
      );

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
          plugins: {'vcdiff': conditionalDecoder},
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(channelName);
      channel.subscribe(receivedMessages.add);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Establish base
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          channelSerial: 'serial-1',
          messages: [
            {'id': 'msg-1:0', 'data': 'original base'},
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedMessages.length, equals(1));

      // Send delta that will fail on first decode attempt
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          channelSerial: 'serial-2',
          messages: [
            {
              'id': 'msg-2:0',
              'data': 'bad-delta',
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      // Recovery: mock auto-responds to ATTACH with ATTACHED
      await _pumpEventQueue();
      expect(channel.state, equals(ChannelState.attached));

      // After recovery, server resends with fresh non-delta
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-3:0',
          channelSerial: 'serial-3',
          messages: [
            {'id': 'msg-3:0', 'data': 'fresh after recovery'},
          ],
        ),
      );

      await _pumpEventQueue();

      expect(channel.state, equals(ChannelState.attached));
      expect(receivedMessages.length, equals(2));
      expect(receivedMessages[0].data, equals('original base'));
      expect(receivedMessages[1].data, equals('fresh after recovery'));
    });
  });

  group('RTL18 - Only one recovery in progress at a time', () {
    // UTS: realtime/unit/RTL18/single-recovery-at-time-1
    test('multiple decode failures trigger only one recovery ATTACH', () async {
      final channelName = testChannelName('RTL18-single');

      final attachMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            attachMessages.add(msg);
            // Only respond to the initial attach — leave recovery in progress
            if (attachMessages.length == 1) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
          }
        },
      );

      final failingDecoder = FailingMockVCDiffDecoder();

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          plugins: {'vcdiff': failingDecoder},
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

      final initialAttachCount = attachMessages.length;

      // Establish base
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-1:0',
          channelSerial: 'serial-1',
          messages: [
            {'id': 'msg-1:0', 'data': 'base'},
          ],
        ),
      );

      await _pumpEventQueue();

      // First delta fails — triggers recovery
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-2:0',
          messages: [
            {
              'id': 'msg-2:0',
              'data': 'bad-delta-1',
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-1:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();
      expect(channel.state, equals(ChannelState.attaching));

      // Second delta also fails — but recovery already in progress
      // (Channel is ATTACHING, so _handleMessage returns early per RTL17)
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.message,
          channel: channelName,
          id: 'msg-3:0',
          messages: [
            {
              'id': 'msg-3:0',
              'data': 'bad-delta-2',
              'encoding': 'vcdiff',
              'extras': {
                'delta': {'from': 'msg-2:0', 'format': 'vcdiff'},
              },
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // Only one recovery ATTACH was sent
      final recoveryAttaches = attachMessages.length - initialAttachCount;
      expect(recoveryAttaches, equals(1));
    });
  });
}

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

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

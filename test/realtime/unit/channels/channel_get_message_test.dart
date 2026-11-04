import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel getMessage (RTL28).
///
/// RTL28 states that RealtimeChannel#getMessage is identical to
/// RestChannel#getMessage — it uses the same underlying REST endpoint.
/// These tests verify the same behavior applies when called on a
/// RealtimeChannel instance.
///
/// Spec: uts/test/realtime/unit/channels/channel_get_message.md
void main() {
  group('RTL28 - RealtimeChannel#getMessage sends GET to correct endpoint', () {
    // UTS: realtime/unit/RTL28/identical-to-rest-0
    test('sends GET to /channels/{channelName}/messages/{serial}', () async {
      final channelName = testChannelName('RTL28');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'name': 'evt',
            'data': 'hello',
            'serial': 'msg-serial-123',
            'timestamp': 1700000000000,
          });
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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.getMessage('msg-serial-123');

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-123',
        ),
      );

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  group('RTL28 - RealtimeChannel#getMessage returns decoded Message', () {
    // UTS: rest/unit/RSL11c/returns-decoded-message-0.1
    test('returns Message with all fields populated', () async {
      final channelName = testChannelName('RTL28-decode');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'id': 'msg-id-1',
            'name': 'test-event',
            'data': 'hello world',
            'serial': 'serial-xyz',
            'clientId': 'client-1',
            'timestamp': 1700000000000,
            'version': {
              'serial': 'version-serial-1',
              'timestamp': 1700000000000,
              'clientId': 'client-1',
            },
          });
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

      final client = PubSubClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final msg = await channel.getMessage('serial-xyz');

      expect(msg, isA<Message>());
      expect(msg.id, equals('msg-id-1'));
      expect(msg.name, equals('test-event'));
      expect(msg.data, equals('hello world'));
      expect(msg.serial, equals('serial-xyz'));
      expect(msg.clientId, equals('client-1'));
      expect(msg.version!.serial, equals('version-serial-1'));

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  group('RTL28 - getMessage serial validation', () {
    // UTS: rest/unit/RSL11a/missing-serial-error-0.1
    test('empty serial throws AblyException with code 40003', () async {
      final channelName = testChannelName('RTL28-validate');

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

      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      try {
        await channel.getMessage('');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      mockWs.dispose();
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

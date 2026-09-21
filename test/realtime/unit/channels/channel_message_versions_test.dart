import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel getMessageVersions (RTL31).
///
/// RTL31 states that RealtimeChannel#getMessageVersions is identical to
/// RestChannel#getMessageVersions — it uses the same underlying REST endpoint.
/// These tests verify the same behavior applies when called on a
/// RealtimeChannel instance.
///
/// Spec: uts/test/realtime/unit/channels/channel_message_versions.md
void main() {
  group(
      'RTL31 - RealtimeChannel#getMessageVersions sends GET to correct endpoint',
      () {
    // UTS: rest/unit/RSL14b/get-correct-endpoint-0.1
    test('sends GET to /channels/{channelName}/messages/{serial}/versions',
        () async {
      final channelName = testChannelName('RTL31');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'name': 'evt',
              'data': 'v2-data',
              'serial': 'msg-serial-1',
              'action': 1,
              'version': {'serial': 'vs2', 'timestamp': 1700000002000},
            },
            {
              'name': 'evt',
              'data': 'v1-data',
              'serial': 'msg-serial-1',
              'action': 0,
              'version': {'serial': 'vs1', 'timestamp': 1700000001000},
            },
          ]);
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

      await channel.getMessageVersions('msg-serial-1');

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1/versions',
        ),
      );

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  group('RTL31 - RealtimeChannel#getMessageVersions returns PaginatedResult',
      () {
    // UTS: realtime/unit/RTL31/identical-to-rest-0
    test('parses response into paginated result with decoded messages',
        () async {
      final channelName = testChannelName('RTL31-decode');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'name': 'evt',
              'data': 'updated-data',
              'serial': 'msg-serial-1',
              'action': 1,
              'version': {
                'serial': 'vs2',
                'timestamp': 1700000002000,
                'clientId': 'user-1',
                'description': 'edit',
              },
            },
            {
              'name': 'evt',
              'data': 'original-data',
              'serial': 'msg-serial-1',
              'action': 0,
              'version': {
                'serial': 'vs1',
                'timestamp': 1700000001000,
              },
            },
          ]);
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

      final result = await channel.getMessageVersions('msg-serial-1');

      expect(result, isA<PaginatedResult<Message>>());
      expect(result.items.length, equals(2));

      expect(result.items[0].data, equals('updated-data'));
      expect(result.items[0].action, equals(MessageAction.messageUpdate));
      expect(result.items[0].version!.serial, equals('vs2'));
      expect(result.items[0].version!.description, equals('edit'));

      expect(result.items[1].data, equals('original-data'));
      expect(result.items[1].action, equals(MessageAction.messageCreate));

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  group('RTL31 - RealtimeChannel#getMessageVersions passes params', () {
    // UTS: rest/unit/RSL14a/params-as-querystring-0.1
    test('optional params sent as query parameters', () async {
      final channelName = testChannelName('RTL31-params');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, []);
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

      await channel.getMessageVersions(
        'msg-serial-1',
        params: {'direction': 'backwards', 'limit': '10'},
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.url.queryParameters['direction'], equals('backwards'));
      expect(request.url.queryParameters['limit'], equals('10'));

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  group('RTL31 - getMessageVersions serial validation', () {
    // UTS: realtime/unit/RTL31/identical-to-rest-0.1
    test('empty serial throws AblyException with code 40003', () async {
      final channelName = testChannelName('RTL31-validate');

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
        await channel.getMessageVersions('');
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

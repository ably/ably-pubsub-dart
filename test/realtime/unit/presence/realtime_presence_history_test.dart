import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimePresence.history (RTP12).
///
/// Spec: uts/test/realtime/unit/presence/realtime_presence_history.md
void main() {
  group('RTP12a - history supports same params as RestPresence#history', () {
    // UTS: realtime/unit/RTP12a/history-supports-rest-params-0
    test('passes start, end, direction, limit to REST endpoint', () async {
      final channelName = testChannelName('RTP12a');

      final capturedRequests = <CapturedRequest>[];

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
          }
        },
      );

      final mockHttp = MockHttpClient(
        onRequest: (req) {
          capturedRequests.add(
            CapturedRequest(
              method: req.method,
              url: req.url,
              headers: req.headers,
              body: req.bodyAsString,
            ),
          );
          req.respondWith(200, []);
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
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

      await channel.presence.history(
        const RestHistoryParams(
          start: 1000,
          end: 2000,
          limit: 50,
        ),
      );

      expect(capturedRequests.length, equals(1));
      final request = capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/presence/history',
        ),
      );
      expect(request.url.queryParameters['start'], equals('1000'));
      expect(request.url.queryParameters['end'], equals('2000'));
      expect(request.url.queryParameters['direction'], equals('backwards'));
      expect(request.url.queryParameters['limit'], equals('50'));

      mockWs.dispose();
      mockHttp.dispose();
    });
  });

  group('RTP12c - history returns PaginatedResult', () {
    // UTS: realtime/unit/RTP12c/history-returns-paginated-result-0
    test('returns PaginatedResult with presence messages', () async {
      final channelName = testChannelName('RTP12c');

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
          }
        },
      );

      final mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, [
            {
              'id': 'hist-1',
              'action': 'enter',
              'clientId': 'alice',
              'timestamp': 1000,
            },
            {
              'id': 'hist-2',
              'action': 'update',
              'clientId': 'alice',
              'timestamp': 2000,
            },
            {
              'id': 'hist-3',
              'action': 'leave',
              'clientId': 'alice',
              'timestamp': 3000,
            },
          ]);
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
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

      final result = await channel.presence.history();

      expect(result, isA<PaginatedResult<PresenceMessage>>());
      expect(result.items.length, equals(3));
      expect(result.items[0].clientId, equals('alice'));
      expect(result.items[0].action, equals(PresenceAction.enter));
      expect(result.items[2].action, equals(PresenceAction.leave));

      mockWs.dispose();
      mockHttp.dispose();
    });
  });
}

/// Waits for the connection to reach the target state.
Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState,
) async {
  if (connection.state == targetState) return;
  await connection.on().firstWhere((change) => change.current == targetState);
  // Defer to event queue to avoid re-entrant issues
  await Future<void>.delayed(Duration.zero);
}

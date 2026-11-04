import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Tests for RealtimeChannel history and status (RTL10, RSL8).
///
/// These use a mock WebSocket for connection and a mock HTTP client
/// for the REST API calls that history() and status() make.
void main() {
  // ---------------------------------------------------------------------------
  // RTL10a - RealtimeChannel#history supports same params as RestChannel
  // ---------------------------------------------------------------------------

  group('RTL10a - RealtimeChannel#history returns PaginatedResult', () {
    // UTS: realtime/unit/RTL10a/supports-rest-params-0
    test('returns messages from REST API', () async {
      final channelName = testChannelName('RTL10a');
      final capturedRequests = <CapturedRequest>[];

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
          req.respondWith(200, [
            {
              'id': 'msg1',
              'name': 'event1',
              'data': 'data1',
              'timestamp': 1000,
            },
            {
              'id': 'msg2',
              'name': 'event2',
              'data': 'data2',
              'timestamp': 2000,
            },
          ]);
        },
      );

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final result = await channel.history();

      expect(result, isA<PaginatedResult<Message>>());
      expect(result.items, hasLength(2));
      expect(result.items[0].name, equals('event1'));
      expect(result.items[1].name, equals('event2'));

      // Verify the REST request was made to the correct endpoint
      expect(capturedRequests, hasLength(1));
      expect(capturedRequests[0].method, equals('GET'));
      expect(
        capturedRequests[0].url.path,
        equals('/channels/${Uri.encodeComponent(channelName)}/messages'),
      );

      mockWs.dispose();
    });

    // UTS: rest/unit/RSL2b/query-parameters-0.1
    test('passes query parameters through', () async {
      final channelName = testChannelName('RTL10a-params');
      final capturedRequests = <CapturedRequest>[];

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

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      await channel.history(
        const RestHistoryParams(
          start: 1000,
          end: 2000,
          direction: HistoryDirection.forwards,
          limit: 50,
        ),
      );

      expect(capturedRequests, hasLength(1));
      final url = capturedRequests[0].url;
      expect(url.queryParameters['start'], equals('1000'));
      expect(url.queryParameters['end'], equals('2000'));
      expect(url.queryParameters['direction'], equals('forwards'));
      expect(url.queryParameters['limit'], equals('50'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL10b - untilAttach parameter
  // ---------------------------------------------------------------------------

  group('RTL10b - untilAttach adds fromSerial query parameter', () {
    // UTS: realtime/unit/RTL10b/adds-from-serial-0
    test('adds fromSerial when channel is attached', () async {
      final channelName = testChannelName('RTL10b');
      final capturedRequests = <CapturedRequest>[];
      const attachSerial = 'serial-abc:0';

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
                channelSerial: attachSerial,
              ),
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await client.connection
          .on()
          .firstWhere((c) => c.current == ConnectionState.connected)
          .timeout(const Duration(seconds: 5));
      await channel.attach();

      expect(channel.state, equals(ChannelState.attached));

      await channel.history(
        const RealtimeHistoryParams(untilAttach: true),
      );

      expect(capturedRequests, hasLength(1));
      final url = capturedRequests[0].url;
      expect(url.queryParameters['fromSerial'], equals(attachSerial));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL10b/errors-when-not-attached-1
    test('throws when channel has no attachSerial', () async {
      final channelName = testChannelName('RTL10b-err');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      // Channel is INITIALIZED — no attachSerial
      expect(channel.state, equals(ChannelState.initialized));

      try {
        await channel.history(
          const RealtimeHistoryParams(untilAttach: true),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final err = e as AblyException;
        expect(err.errorInfo?.code, equals(91000));
      }

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTL10b/adds-from-serial-0.1
    test('untilAttach false does not add fromSerial', () async {
      final channelName = testChannelName('RTL10b-false');
      final capturedRequests = <CapturedRequest>[];

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

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      await channel.history(
        const RealtimeHistoryParams(),
      );

      expect(capturedRequests, hasLength(1));
      final url = capturedRequests[0].url;
      expect(url.queryParameters.containsKey('fromSerial'), isFalse);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTL10c - Returns PaginatedResult
  // ---------------------------------------------------------------------------

  group('RTL10c - Returns PaginatedResult with items', () {
    // UTS: rest/unit/RSL2a/returns-paginated-result-0.1
    test('empty history returns empty PaginatedResult', () async {
      final channelName = testChannelName('RTL10c');

      final mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, []);
        },
      );

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final result = await channel.history();

      expect(result.items, isEmpty);
      expect(result.isLast(), isTrue);

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RSL8 - RealtimeChannel#status via REST API
  // ---------------------------------------------------------------------------

  group('RSL8 - RealtimeChannel#status returns ChannelDetails', () {
    // UTS: rest/unit/RSL2/request-url-format-0.1
    test('makes GET request to channel status endpoint', () async {
      final channelName = testChannelName('RSL8');
      final capturedRequests = <CapturedRequest>[];

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
          req.respondWith(200, {
            'channelId': channelName,
            'name': channelName,
            'status': {
              'isActive': true,
              'occupancy': {
                'metrics': {
                  'connections': 1,
                  'publishers': 0,
                  'subscribers': 1,
                  'presenceConnections': 0,
                  'presenceMembers': 0,
                  'presenceSubscribers': 0,
                },
              },
            },
          });
        },
      );

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      final details = await channel.status();

      expect(details, isA<ChannelDetails>());
      expect(details.channelId, equals(channelName));

      // Verify REST endpoint
      expect(capturedRequests, hasLength(1));
      expect(capturedRequests[0].method, equals('GET'));
      expect(
        capturedRequests[0].url.path,
        equals('/channels/${Uri.encodeComponent(channelName)}'),
      );

      mockWs.dispose();
    });
  });
}

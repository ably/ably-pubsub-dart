import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel getMessageVersions (RSL14a, RSL14b, RSL14c).
///
/// These tests use a mocked HTTP client to verify getMessageVersions()
/// request formation and response parsing.
///
/// Spec: uts/test/rest/unit/channel/message_versions.md
void main() {
  group('RSL14b - getMessageVersions sends GET to correct endpoint', () {
    // UTS: rest/unit/RSL14b/get-correct-endpoint-0
    test('sends GET to /channels/{channelName}/messages/{serial}/versions',
        () async {
      const channelName = 'test-RSL14b';
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

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
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
    });
  });

  group('RSL14c - getMessageVersions returns PaginatedResult of Messages', () {
    // UTS: rest/unit/RSL14c/returns-paginated-result-0
    test('parses response into paginated result with decoded messages',
        () async {
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

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL14c');
      final result = await channel.getMessageVersions('msg-serial-1');

      expect(result, isA<PaginatedResult<Message>>());
      expect(result.items.length, equals(2));

      expect(result.items[0], isA<Message>());
      expect(result.items[0].data, equals('updated-data'));
      expect(result.items[0].action, equals(MessageAction.messageUpdate));
      expect(result.items[0].version!.serial, equals('vs2'));
      expect(result.items[0].version!.description, equals('edit'));

      expect(result.items[1].data, equals('original-data'));
      expect(result.items[1].action, equals(MessageAction.messageCreate));

      mockHttp.dispose();
    });
  });

  group('RSL14a - getMessageVersions passes params as querystring', () {
    // UTS: rest/unit/RSL14a/params-as-querystring-0
    test('optional params sent as query parameters', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, []);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL14a-params');
      await channel.getMessageVersions(
        'msg-serial-1',
        params: {'direction': 'backwards', 'limit': '10'},
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.url.queryParameters['direction'], equals('backwards'));
      expect(request.url.queryParameters['limit'], equals('10'));

      mockHttp.dispose();
    });
  });
}

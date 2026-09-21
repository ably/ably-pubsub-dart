import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel getMessage (RSL11a, RSL11b, RSL11c).
///
/// These tests use a mocked HTTP client to verify getMessage()
/// request formation and response parsing.
///
/// Spec: uts/test/rest/unit/channel/get_message.md
void main() {
  group('RSL11b - getMessage sends GET to correct endpoint', () {
    // UTS: rest/unit/RSL11b/get-correct-endpoint-0
    test('sends GET to /channels/{channelName}/messages/{serial}', () async {
      const channelName = 'test-RSL11b';
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

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
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
    });
  });

  group('RSL11c - getMessage returns decoded Message', () {
    // UTS: rest/unit/RSL11c/returns-decoded-message-0
    test('returns Message with all fields populated', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'id': 'msg-id-1',
            'name': 'test-event',
            'data': 'hello world',
            'serial': 'serial-xyz',
            'clientId': 'client-1',
            'timestamp': 1700000000000,
            'extras': {
              'push': {
                'notification': {'title': 'Test'},
              },
            },
            'version': {
              'serial': 'version-serial-1',
              'timestamp': 1700000000000,
              'clientId': 'client-1',
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL11c');
      final msg = await channel.getMessage('serial-xyz');

      expect(msg, isA<Message>());
      expect(msg.id, equals('msg-id-1'));
      expect(msg.name, equals('test-event'));
      expect(msg.data, equals('hello world'));
      expect(msg.serial, equals('serial-xyz'));
      expect(msg.clientId, equals('client-1'));
      expect(msg.timestamp, equals(1700000000000));
      expect(msg.version!.serial, equals('version-serial-1'));

      mockHttp.dispose();
    });
  });

  group('RSL11b - getMessage URL-encodes serial in path', () {
    // UTS: rest/unit/RSL11b/url-encodes-serial-1
    test('special characters in serial are URL-encoded', () async {
      const channelName = 'test-RSL11b-encode';
      const serialWithSpecialChars = 'serial/with:special+chars';

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'name': 'evt',
            'data': 'hello',
            'serial': serialWithSpecialChars,
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
      await channel.getMessage(serialWithSpecialChars);

      final request = mockHttp.capturedRequests[0];
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/${Uri.encodeComponent(serialWithSpecialChars)}',
        ),
      );

      mockHttp.dispose();
    });
  });

  group('RSL11a - getMessage with missing serial throws error', () {
    // UTS: rest/unit/RSL11a/missing-serial-error-0
    test('empty serial throws AblyException with code 40003', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL11a-error');

      try {
        await channel.getMessage('');
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      mockHttp.dispose();
    });
  });
}

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel publish result (RSL1n, PBR1, PBR2a).
///
/// These tests use a mocked HTTP client to verify that publish()
/// returns a PublishResult with correct serials.
///
/// Spec: uts/test/rest/unit/channel/publish_result.md
void main() {
  group('RSL1n - publish() returns PublishResult with serials', () {
    // UTS: rest/unit/RSL1n/publish-result-single-message-0
    test('single message returns single serial', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {
            'serials': ['serial-abc'],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL1n-single');
      final result = await channel.publish(name: 'event', data: 'hello');

      expect(result, isA<PublishResult>());
      expect(result.serials, isList);
      expect(result.serials.length, equals(1));
      expect(result.serials[0], equals('serial-abc'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSL1n/publish-result-batch-serials-1
    test('batch publish returns serials matching each message', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {
            'serials': ['s1', 's2', 's3'],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL1n-batch');
      final messages = [
        const Message(name: 'event1', data: 'data1'),
        const Message(name: 'event2', data: 'data2'),
        const Message(name: 'event3', data: 'data3'),
      ];
      final result = await channel.publish(messages: messages);

      expect(result, isA<PublishResult>());
      expect(result.serials.length, equals(3));
      expect(result.serials[0], equals('s1'));
      expect(result.serials[1], equals('s2'));
      expect(result.serials[2], equals('s3'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSL1n/publish-result-null-serial-2
    test('null serial preserved for conflated message', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {
            'serials': [null, 's2'],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL1n-null');
      final messages = [
        const Message(name: 'event1', data: 'data1'),
        const Message(name: 'event2', data: 'data2'),
      ];
      final result = await channel.publish(messages: messages);

      expect(result.serials.length, equals(2));
      expect(result.serials[0], isNull);
      expect(result.serials[1], equals('s2'));

      mockHttp.dispose();
    });
  });
}

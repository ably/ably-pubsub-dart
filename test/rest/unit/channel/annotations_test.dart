import 'dart:convert';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel annotations (RSL10, RSAN1, RSAN2, RSAN3).
///
/// These tests use a mocked HTTP client to verify annotation
/// publish, delete, and get operations.
///
/// Spec: uts/test/rest/unit/channel/annotations.md
void main() {
  group('RSL10 - channel.annotations returns RestAnnotations', () {
    // UTS: rest/unit/RSL10/annotations-attribute-type-0
    test('exposes annotations attribute', () {
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'fake.key:secret',
          useBinaryProtocol: false,
        ),
      );

      final channel = client.channels.get('test-RSL10');
      expect(channel.annotations, isA<RestAnnotations>());
    });
  });

  group('RSAN1c6, RSAN1c1, RSAN1c2 - publish sends POST with ANNOTATION_CREATE',
      () {
    // UTS: rest/unit/RSAN1c6/publish-post-annotation-create-0
    test('sends POST to correct endpoint with correct body', () async {
      const channelName = 'test-RSAN1-publish';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction', name: 'like'),
      );

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1/annotations',
        ),
      );

      final body = request.jsonBody as List;
      expect(body.length, equals(1));

      final annotation = body[0] as Map<String, dynamic>;
      expect(annotation['action'], equals(0)); // ANNOTATION_CREATE
      expect(annotation['messageSerial'], equals('msg-serial-1'));
      expect(annotation['type'], equals('com.example.reaction'));
      expect(annotation['name'], equals('like'));

      mockHttp.dispose();
    });
  });

  group('RSAN1a3 - publish validates type is required', () {
    // UTS: rest/unit/RSAN1a3/publish-type-required-0
    test('throws error code 40003 when type is missing', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSAN1a3');

      try {
        await channel.annotations.publish(
          'msg-serial-1',
          const Annotation(name: 'like'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      mockHttp.dispose();
    });
  });

  group('RSAN1c3 - annotation data encoded per RSL4', () {
    // UTS: rest/unit/RSAN1c3/annotation-data-encoded-0
    test('JSON data encoded as string with encoding field', () async {
      const channelName = 'test-RSAN1c3';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(
          type: 'com.example.data',
          data: {
            'key': 'value',
            'nested': {'a': 1},
          },
        ),
      );

      final body = mockHttp.capturedRequests[0].jsonBody as List;
      final annotation = body[0] as Map<String, dynamic>;

      expect(annotation['data'], isA<String>());
      expect(annotation['encoding'], equals('json'));
      expect(
        json.decode(annotation['data'] as String),
        equals({
          'key': 'value',
          'nested': {'a': 1},
        }),
      );

      mockHttp.dispose();
    });
  });

  group('RSAN1c4 - idempotent ID generated when enabled', () {
    // UTS: rest/unit/RSAN1c4/idempotent-id-generated-0
    test('auto-generates ID with format base64:0', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSAN1c4-enabled');
      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction'),
      );

      final body = mockHttp.capturedRequests[0].jsonBody as List;
      final annotation = body[0] as Map<String, dynamic>;

      expect(annotation.containsKey('id'), isTrue);
      final annotationId = annotation['id'] as String;

      final parts = annotationId.split(':');
      expect(parts.length, equals(2));
      expect(parts[0].length, greaterThanOrEqualTo(12));
      expect(parts[1], equals('0'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSAN1c4/idempotent-id-not-generated-1
    test('does not generate ID when disabled', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          idempotentRestPublishing: false,
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSAN1c4-disabled');
      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction'),
      );

      final body = mockHttp.capturedRequests[0].jsonBody as List;
      final annotation = body[0] as Map<String, dynamic>;

      expect(annotation.containsKey('id'), isFalse);

      mockHttp.dispose();
    });
  });

  group('RSAN2a - delete sends POST with ANNOTATION_DELETE', () {
    // UTS: rest/unit/RSAN1c6/publish-post-annotation-create-0.1
    test('sends POST with action 1 to correct endpoint', () async {
      const channelName = 'test-RSAN2-delete';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(201, {});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
      await channel.annotations.delete(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction', name: 'like'),
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('POST'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1/annotations',
        ),
      );

      final body = request.jsonBody as List;
      expect(body.length, equals(1));
      final annotation = body[0] as Map<String, dynamic>;
      expect(annotation['action'], equals(1)); // ANNOTATION_DELETE
      expect(annotation['messageSerial'], equals('msg-serial-1'));
      expect(annotation['type'], equals('com.example.reaction'));
      expect(annotation['name'], equals('like'));

      mockHttp.dispose();
    });
  });

  group('RSAN3b - get sends GET to correct endpoint', () {
    // UTS: rest/unit/RSAN1c6/publish-post-annotation-create-0.2
    test('sends GET to annotations endpoint', () async {
      const channelName = 'test-RSAN3-get';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'ann-1',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'clientId': 'user-1',
              'serial': 'ann-serial-1',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000000000,
            },
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get(channelName);
      await channel.annotations.get('msg-serial-1');

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('GET'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1/annotations',
        ),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSAN1c6/publish-post-annotation-create-0.3
    test('passes params as querystring', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, []);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSAN3b-params');
      await channel.annotations.get(
        'msg-serial-1',
        params: {'limit': '50'},
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.url.queryParameters['limit'], equals('50'));

      mockHttp.dispose();
    });
  });

  group('RSAN3c - get returns PaginatedResult of Annotations', () {
    // UTS: rest/unit/RSL10/annotations-attribute-type-0.1
    test('parses response with all annotation fields', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'ann-1',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'clientId': 'user-1',
              'count': 1,
              'data': 'thumbs-up',
              'serial': 'ann-serial-1',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000000000,
              'extras': {'custom': 'metadata'},
            },
            {
              'id': 'ann-2',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'heart',
              'clientId': 'user-2',
              'serial': 'ann-serial-2',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000001000,
            },
          ]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSAN3c');
      final result = await channel.annotations.get('msg-serial-1');

      expect(result, isA<PaginatedResult<Annotation>>());
      expect(result.items.length, equals(2));

      final ann1 = result.items[0];
      expect(ann1, isA<Annotation>());
      expect(ann1.id, equals('ann-1'));
      expect(ann1.action, equals(AnnotationAction.annotationCreate));
      expect(ann1.type, equals('com.example.reaction'));
      expect(ann1.name, equals('like'));
      expect(ann1.clientId, equals('user-1'));
      expect(ann1.count, equals(1));
      expect(ann1.data, equals('thumbs-up'));
      expect(ann1.serial, equals('ann-serial-1'));
      expect(ann1.messageSerial, equals('msg-serial-1'));
      expect(ann1.timestamp, equals(1700000000000));

      final ann2 = result.items[1];
      expect(ann2.name, equals('heart'));
      expect(ann2.clientId, equals('user-2'));

      mockHttp.dispose();
    });
  });
}

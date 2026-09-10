import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Idempotent Publishing Tests
///
/// Spec points: RSL1k, RSL1k1, RSL1k2, RSL1k3, RSL1k4, RSL1k5
void main() {
  group('Idempotent Publishing', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSL1k1 - idempotentRestPublishing default', () {
      // UTS: rest/unit/RSL1k1/idempotent-default-true-0
      test('defaults to true', () {
        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(client.options.idempotentRestPublishing, isTrue);
      });
    });

    group('RSL1k2 - Message ID format when idempotent publishing enabled', () {
      // UTS: rest/unit/RSL1k2/message-id-format-0
      test('generates ID in <base64>:<serial> format', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k2-format');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 'data');

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        expect(body[0].containsKey('id'), isTrue);
        final messageId = body[0]['id'] as String;

        // Format: <base64>:<serial>
        final parts = messageId.split(':');
        expect(parts.length, equals(2));

        // First part is base64-encoded
        expect(parts[0], matches(RegExp(r'^[A-Za-z0-9+/=]+$')));
        expect(parts[0].length, greaterThanOrEqualTo(12));

        // Second part is a serial number (starting from 0)
        expect(parts[1], equals('0'));
      });
    });

    group('RSL1k2 - Serial increments for batch publish', () {
      // UTS: rest/unit/RSL1k2/serial-increments-batch-1
      test('increments serial for each message in batch', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k2-batch');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1', 's2', 's3'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final messages = [
          const Message(name: 'event1', data: 'data1'),
          const Message(name: 'event2', data: 'data2'),
          const Message(name: 'event3', data: 'data3'),
        ];
        await channel.publish(messages: messages);

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        // All messages should share the same base but different serials
        final baseIds = <String>[];
        final serials = <int>[];

        for (final msg in body) {
          final parts = (msg['id'] as String).split(':');
          baseIds.add(parts[0]);
          serials.add(int.parse(parts[1]));
        }

        // Same base for all messages in batch
        expect(baseIds.every((base) => base == baseIds[0]), isTrue);

        // Sequential serials starting from 0
        expect(serials, equals([0, 1, 2]));
      });
    });

    group('RSL1k3 - Separate publishes get unique base IDs', () {
      // UTS: rest/unit/RSL1k3/unique-base-ids-0
      test('generates different base IDs for separate calls', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k3-unique');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event1', data: 'data1');
        await channel.publish(name: 'event2', data: 'data2');

        final body1 = json.decode(capturedRequests[0].body!) as List;
        final body2 = json.decode(capturedRequests[1].body!) as List;

        final base1 = (body1[0]['id'] as String).split(':')[0];
        final base2 = (body2[0]['id'] as String).split(':')[0];

        // Different publish calls should have different base IDs
        expect(base1, isNot(equals(base2)));
      });
    });

    group('RSL1k3 - No ID generated when idempotent publishing disabled', () {
      // UTS: rest/unit/RSL1k3/no-id-when-disabled-1
      test('does not add ID when disabled', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k3-disabled');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
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
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 'data');

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        // No automatic ID should be added
        expect(body[0].containsKey('id'), isFalse);
      });
    });

    group('RSL1k - Client-supplied ID preserved', () {
      // UTS: rest/unit/RSL1k/client-id-preserved-0
      test('does not overwrite client-supplied IDs', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k-preserved');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(
          message:
              const Message(id: 'my-custom-id', name: 'event', data: 'data'),
        );

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        // Client-supplied ID should be preserved exactly
        expect(body[0]['id'], equals('my-custom-id'));
      });
    });

    group('RSL1k2 - Same ID used on retry', () {
      // UTS: rest/unit/RSL1k2/same-id-on-retry-2
      test('uses same message ID when retrying after failure', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('RSL1k2-retry');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              // First request fails with retryable error
              req.respondWith(500, {
                'error': {'code': 50000},
              });
            } else {
              // Retry succeeds
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.publish(name: 'event', data: 'data');

        expect(capturedRequests.length, equals(2));

        final body1 = json.decode(capturedRequests[0].body!) as List;
        final body2 = json.decode(capturedRequests[1].body!) as List;

        // Same ID should be used for retry
        expect(body1[0]['id'], equals(body2[0]['id']));
      });
    });

    group('RSL1k - Mixed client and library IDs in batch', () {
      // UTS: rest/unit/RSL1k/mixed-ids-in-batch-1
      test('preserves client IDs and generates IDs for others', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSL1k-mixed');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(201, {
              'serials': ['s1', 's2', 's3'],
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final messages = [
          const Message(id: 'client-id-1', name: 'event1', data: 'data1'),
          const Message(
            name: 'event2',
            data: 'data2',
          ), // No ID - should be generated
          const Message(id: 'client-id-2', name: 'event3', data: 'data3'),
        ];
        await channel.publish(messages: messages);

        final request = capturedRequests[0];
        final body = json.decode(request.body!) as List;

        // Client IDs preserved
        expect(body[0]['id'], equals('client-id-1'));
        expect(body[2]['id'], equals('client-id-2'));

        // Library-generated ID for middle message (base64:index)
        expect(body[1]['id'], matches(RegExp(r'^[A-Za-z0-9+/=]+:[0-9]+$')));
      });
    });
  });
}

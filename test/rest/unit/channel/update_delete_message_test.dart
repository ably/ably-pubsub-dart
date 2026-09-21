import 'dart:convert';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel updateMessage/deleteMessage/appendMessage
/// (RSL15a, RSL15b, RSL15b1, RSL15b7, RSL15c, RSL15d, RSL15e, RSL15f).
///
/// These tests use a mocked HTTP client to verify request formation
/// and response parsing for mutable message operations.
///
/// Spec: uts/test/rest/unit/channel/update_delete_message.md
void main() {
  group('RSL15b, RSL15b1 - updateMessage sends PATCH with MESSAGE_UPDATE', () {
    // UTS: rest/unit/RSL15b/update-sends-patch-update-0
    test('sends PATCH with action 1 to correct endpoint', () async {
      const channelName = 'test-RSL15-update';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
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
      await channel.updateMessage(
        const Message(
          serial: 'msg-serial-1',
          name: 'updated',
          data: 'new-data',
        ),
      );

      expect(mockHttp.capturedRequests.length, equals(1));
      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1',
        ),
      );

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['action'], equals(1));
      expect(body['name'], equals('updated'));
      expect(body['data'], equals('new-data'));

      mockHttp.dispose();
    });
  });

  group('RSL15b, RSL15b1 - deleteMessage sends PATCH with MESSAGE_DELETE', () {
    // UTS: rest/unit/RSL15b/delete-sends-patch-delete-1
    test('sends PATCH with action 2 to correct endpoint', () async {
      const channelName = 'test-RSL15-delete';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
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
      await channel.deleteMessage(
        const Message(serial: 'msg-serial-1'),
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1',
        ),
      );

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['action'], equals(2));

      mockHttp.dispose();
    });
  });

  group('RSL15b, RSL15b1 - appendMessage sends PATCH with MESSAGE_APPEND', () {
    // UTS: rest/unit/RSL15b/append-sends-patch-append-2
    test('sends PATCH with action 5 to correct endpoint', () async {
      const channelName = 'test-RSL15-append';
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
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
      await channel.appendMessage(
        const Message(serial: 'msg-serial-1', data: 'appended-data'),
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.method, equals('PATCH'));
      expect(
        request.url.path,
        equals(
          '/channels/${Uri.encodeComponent(channelName)}/messages/msg-serial-1',
        ),
      );

      final body = request.jsonBody as Map<String, dynamic>;
      expect(body['action'], equals(5));
      expect(body['data'], equals('appended-data'));

      mockHttp.dispose();
    });
  });

  group('RSL15b7 - version set to MessageOperation when provided', () {
    // UTS: rest/unit/RSL15b7/version-set-with-operation-0
    test('includes version field with operation data', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15b7');
      await channel.updateMessage(
        const Message(serial: 's1', data: 'updated'),
        operation: const MessageOperation(
          clientId: 'user1',
          description: 'fixed typo',
          metadata: {'reason': 'typo'},
        ),
      );

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body.containsKey('version'), isTrue);
      final version = body['version'] as Map<String, dynamic>;
      expect(version['clientId'], equals('user1'));
      expect(version['description'], equals('fixed typo'));
      expect((version['metadata'] as Map)['reason'], equals('typo'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSL15b7/version-absent-no-operation-1
    test('omits version field when no operation provided', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15b7-absent');
      await channel.updateMessage(
        const Message(serial: 's1', data: 'updated'),
      );

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body.containsKey('version'), isFalse);

      mockHttp.dispose();
    });
  });

  group('RSL15c - does not mutate user-supplied Message', () {
    // UTS: rest/unit/RSL15c/no-mutate-user-message-0
    test('original message is unchanged after updateMessage', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15c');
      const originalMsg =
          Message(serial: 's1', name: 'orig', data: 'original-data');

      await channel.updateMessage(originalMsg);

      expect(originalMsg.action, isNull);
      expect(originalMsg.name, equals('orig'));
      expect(originalMsg.data, equals('original-data'));

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body['action'], equals(1));

      mockHttp.dispose();
    });
  });

  group('RSL15e - returns UpdateDeleteResult on success', () {
    // UTS: rest/unit/RSL15e/returns-update-delete-result-0
    test('parses versionSerial from response', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'version-serial-abc'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15e');
      final result = await channel.updateMessage(
        const Message(serial: 's1', data: 'updated'),
      );

      expect(result, isA<UpdateDeleteResult>());
      expect(result.versionSerial, equals('version-serial-abc'));

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSL15e/null-version-serial-1
    test('null versionSerial preserved', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': null});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15e-null');
      final result = await channel.updateMessage(
        const Message(serial: 's1', data: 'updated'),
      );

      expect(result, isA<UpdateDeleteResult>());
      expect(result.versionSerial, isNull);

      mockHttp.dispose();
    });
  });

  group('RSL15f - params sent as querystring', () {
    // UTS: rest/unit/RSL15f/params-sent-as-querystring-0
    test('optional params are sent as query parameters', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15f');
      await channel.updateMessage(
        const Message(serial: 's1', data: 'updated'),
        params: {'key': 'value', 'num': '42'},
      );

      final request = mockHttp.capturedRequests[0];
      expect(request.url.queryParameters['key'], equals('value'));
      expect(request.url.queryParameters['num'], equals('42'));

      mockHttp.dispose();
    });
  });

  group('RSL15a - serial required, throws error if missing', () {
    // UTS: rest/unit/RSL15a/serial-required-throws-error-0
    test('updateMessage without serial throws error code 40003', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15a');

      try {
        await channel.updateMessage(const Message(name: 'x', data: 'y'));
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      try {
        await channel.deleteMessage(const Message(name: 'x'));
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      try {
        await channel.appendMessage(const Message(data: 'y'));
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40003));
      }

      mockHttp.dispose();
    });
  });

  group('RSL15d - request body encoded per RSL4', () {
    // UTS: rest/unit/RSL15d/body-encoded-per-rsl4-0
    test('JSON data encoded as string with encoding field', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyId:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL15d');
      await channel.updateMessage(
        const Message(serial: 's1', data: {'key': 'value'}),
      );

      final body =
          mockHttp.capturedRequests[0].jsonBody as Map<String, dynamic>;
      expect(body['data'], isA<String>());
      expect(body['encoding'], equals('json'));
      expect(json.decode(body['data'] as String), equals({'key': 'value'}));

      mockHttp.dispose();
    });
  });

  group('RSL15b - serial URL-encoded in path', () {
    // UTS: rest/unit/RSL15b/serial-url-encoded-path-3
    test('special characters in serial are URL-encoded', () async {
      const channelName = 'test-RSL15b-encode';
      const serialWithSpecialChars = 'serial/special:chars';

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {'versionSerial': 'vs1'});
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
      await channel.updateMessage(
        const Message(serial: serialWithSpecialChars, data: 'updated'),
      );

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
}

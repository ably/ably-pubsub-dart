import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../helpers/mock_http_client.dart';

/// Unit tests for REST batchPresence (RSC24) and related types (BAR2, BGR2, BGF2).
///
/// These tests use a mocked HTTP client to verify request formation and
/// response parsing without hitting the real Ably server.
///
/// Spec: uts/test/rest/unit/batch_presence.md
void main() {
  group('RSC24 - batchPresence sends GET to /presence', () {
    // UTS: rest/unit/RSC24/get-presence-channels-param-0
    test('RSC24_1 - sends GET request to /presence with channels query param',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 2,
            'failureCount': 0,
            'results': [
              {'channel': 'channel-a', 'presence': []},
              {'channel': 'channel-b', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      await client.batchPresence(['channel-a', 'channel-b']);

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(mockHttp.capturedRequests[0].method, equals('GET'));
      expect(mockHttp.capturedRequests[0].url.path, equals('/presence'));
      expect(
        mockHttp.capturedRequests[0].url.queryParameters['channels'],
        equals('channel-a,channel-b'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSC24/single-channel-param-0
    test('RSC24_2 - single channel sends GET with single channel name',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {'channel': 'my-channel', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      await client.batchPresence(['my-channel']);

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['channels'],
        equals('my-channel'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSC24/special-chars-comma-joined-0
    test('RSC24_3 - channel names with special characters are comma-joined',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 2,
            'failureCount': 0,
            'results': [
              {'channel': 'foo:bar', 'presence': []},
              {'channel': 'baz/qux', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      await client.batchPresence(['foo:bar', 'baz/qux']);

      expect(
        mockHttp.capturedRequests[0].url.queryParameters['channels'],
        equals('foo:bar,baz/qux'),
      );

      mockHttp.dispose();
    });
  });

  group('BAR2 - BatchPresenceResponse structure', () {
    // UTS: rest/unit/BAR2/mixed-success-failure-counts-0
    test('BAR2_1 - successCount and failureCount from mixed response',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 3,
            'failureCount': 1,
            'results': [
              {'channel': 'ch-1', 'presence': []},
              {'channel': 'ch-2', 'presence': []},
              {'channel': 'ch-3', 'presence': []},
              {
                'channel': 'ch-4',
                'error': {
                  'code': 40160,
                  'statusCode': 401,
                  'message': 'Not permitted',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result =
          await client.batchPresence(['ch-1', 'ch-2', 'ch-3', 'ch-4']);

      expect(result.successCount, equals(3));
      expect(result.failureCount, equals(1));
      expect(result.results.length, equals(4));

      mockHttp.dispose();
    });

    // UTS: rest/unit/BAR2/all-success-counts-0
    test('BAR2_2 - all success', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 2,
            'failureCount': 0,
            'results': [
              {'channel': 'ch-a', 'presence': []},
              {'channel': 'ch-b', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result = await client.batchPresence(['ch-a', 'ch-b']);

      expect(result.successCount, equals(2));
      expect(result.failureCount, equals(0));
      expect(result.results.length, equals(2));

      mockHttp.dispose();
    });

    // UTS: rest/unit/BAR2/all-failure-counts-0
    test('BAR2_3 - all failure', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 0,
            'failureCount': 2,
            'results': [
              {
                'channel': 'ch-a',
                'error': {
                  'code': 40160,
                  'statusCode': 401,
                  'message': 'Not permitted',
                },
              },
              {
                'channel': 'ch-b',
                'error': {
                  'code': 40160,
                  'statusCode': 401,
                  'message': 'Not permitted',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result = await client.batchPresence(['ch-a', 'ch-b']);

      expect(result.successCount, equals(0));
      expect(result.failureCount, equals(2));
      expect(result.results.length, equals(2));

      mockHttp.dispose();
    });
  });

  group('BGR2 - BatchPresenceSuccessResult structure', () {
    // UTS: rest/unit/BGR2/success-with-members-0
    test('BGR2_1 - success result with members present', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'channel': 'my-channel',
                'presence': [
                  {
                    'clientId': 'client-1',
                    'action': 1,
                    'connectionId': 'conn-abc',
                    'id': 'conn-abc:0:0',
                    'timestamp': 1700000000000,
                    'data': 'hello',
                  },
                  {
                    'clientId': 'client-2',
                    'action': 1,
                    'connectionId': 'conn-def',
                    'id': 'conn-def:0:0',
                    'timestamp': 1700000000000,
                    'data': {'key': 'value'},
                  },
                ],
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result = await client.batchPresence(['my-channel']);

      expect(result.results.length, equals(1));

      final success = result.results[0];
      expect(success, isA<BatchPresenceSuccessResult>());
      expect(success.channel, equals('my-channel'));

      final successResult = success as BatchPresenceSuccessResult;
      expect(successResult.presence.length, equals(2));

      expect(successResult.presence[0].clientId, equals('client-1'));
      expect(successResult.presence[0].action, equals(PresenceAction.present));
      expect(successResult.presence[0].connectionId, equals('conn-abc'));
      expect(successResult.presence[0].data, equals('hello'));

      expect(successResult.presence[1].clientId, equals('client-2'));
      expect(successResult.presence[1].data, isA<Map>());
      expect(
        (successResult.presence[1].data as Map)['key'],
        equals('value'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/BGR2/success-empty-presence-0
    test('BGR2_2 - success result with empty presence (no members)', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {'channel': 'empty-channel', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result = await client.batchPresence(['empty-channel']);

      final success = result.results[0];
      expect(success, isA<BatchPresenceSuccessResult>());
      expect(success.channel, equals('empty-channel'));
      expect(
        (success as BatchPresenceSuccessResult).presence.length,
        equals(0),
      );

      mockHttp.dispose();
    });
  });

  group('BGF2 - BatchPresenceFailureResult structure', () {
    // UTS: rest/unit/BGF2/failure-error-details-0
    test('BGF2_1 - failure result with error details', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 0,
            'failureCount': 1,
            'results': [
              {
                'channel': 'restricted-channel',
                'error': {
                  'code': 40160,
                  'statusCode': 401,
                  'message': 'Channel operation not permitted',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result = await client.batchPresence(['restricted-channel']);

      expect(result.results.length, equals(1));

      final failure = result.results[0];
      expect(failure, isA<BatchPresenceFailureResult>());
      expect(failure.channel, equals('restricted-channel'));

      final failureResult = failure as BatchPresenceFailureResult;
      expect(failureResult.error, isA<ErrorInfo>());
      expect(failureResult.error.code, equals(40160));
      expect(failureResult.error.statusCode, equals(401));
      expect(failureResult.error.message, contains('not permitted'));

      mockHttp.dispose();
    });
  });

  group('RSC24 - Mixed results', () {
    // UTS: rest/unit/RSC24/mixed-success-failure-results-0
    test('RSC24_Mixed_1 - mixed success and failure results', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 1,
            'failureCount': 1,
            'results': [
              {
                'channel': 'allowed-channel',
                'presence': [
                  {
                    'clientId': 'user-1',
                    'action': 1,
                    'connectionId': 'conn-1',
                    'id': 'conn-1:0:0',
                    'timestamp': 1700000000000,
                  },
                ],
              },
              {
                'channel': 'restricted-channel',
                'error': {
                  'code': 40160,
                  'statusCode': 401,
                  'message': 'Not permitted',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final result =
          await client.batchPresence(['allowed-channel', 'restricted-channel']);

      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(1));
      expect(result.results.length, equals(2));

      expect(result.results[0], isA<BatchPresenceSuccessResult>());
      expect(result.results[0].channel, equals('allowed-channel'));
      expect(
        (result.results[0] as BatchPresenceSuccessResult).presence.length,
        equals(1),
      );
      expect(
        (result.results[0] as BatchPresenceSuccessResult).presence[0].clientId,
        equals('user-1'),
      );

      expect(result.results[1], isA<BatchPresenceFailureResult>());
      expect(result.results[1].channel, equals('restricted-channel'));
      expect(
        (result.results[1] as BatchPresenceFailureResult).error.code,
        equals(40160),
      );

      mockHttp.dispose();
    });
  });

  group('RSC24 - Error handling', () {
    // UTS: rest/unit/RSC24/server-error-propagated-0
    test('RSC24_Error_1 - server error is propagated as an exception',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(500, {
            'error': {
              'code': 50000,
              'statusCode': 500,
              'message': 'Internal error',
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      try {
        await client.batchPresence(['any-channel']);
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final error = e as AblyException;
        expect(error.errorInfo?.code, equals(50000));
        expect(error.errorInfo?.statusCode, equals(500));
      }

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSC24/auth-error-propagated-0
    test('RSC24_Error_2 - authentication error is propagated as an exception',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(401, {
            'error': {
              'code': 40101,
              'statusCode': 401,
              'message': 'Invalid credentials',
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      try {
        await client.batchPresence(['any-channel']);
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final error = e as AblyException;
        expect(error.errorInfo?.code, equals(40101));
        expect(error.errorInfo?.statusCode, equals(401));
      }

      mockHttp.dispose();
    });
  });

  group('RSC24 - Request authentication', () {
    // UTS: rest/unit/RSC24/uses-configured-auth-0
    test('RSC24_Auth_1 - request uses configured authentication', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {'channel': 'ch', 'presence': []},
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      await client.batchPresence(['ch']);

      // http.Request headers are case-insensitive; Map.from preserves
      // the original key casing from AblyHttpClient ('Authorization').
      final authHeader =
          mockHttp.capturedRequests[0].headers['Authorization'] ??
              mockHttp.capturedRequests[0].headers['authorization'];
      expect(authHeader, startsWith('Basic '));

      mockHttp.dispose();
    });
  });
}

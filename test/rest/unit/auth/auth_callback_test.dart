import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Auth Callback Tests
///
/// Spec points: RSA8c, RSA8c1a, RSA8c1b, RSA8c1c, RSA8c2, RSA8c3, RSA8d
void main() {
  group('Auth Callback', () {
    group('RSA8d - authCallback invocation', () {
      // UTS: rest/unit/RSA8d/callback-receives-token-params-3
      test('invokes callback with TokenParams and returns token', () async {
        final callbackInvocations = <TokenParams>[];
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8d');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
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
            authCallback: (tokenParams) async {
              callbackInvocations.add(tokenParams);
              return TokenDetails(
                token: 'mock-token-string',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
                clientId: 'callback-client',
              );
            },
            clientId: 'test-client',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        // Trigger auth by making a request
        final channel = client.channels.get(channelName);
        await channel.publish(name: 'event', data: 'data');

        // Callback was invoked
        expect(callbackInvocations.length, greaterThanOrEqualTo(1));

        // TokenParams were passed
        expect(callbackInvocations[0], isA<TokenParams>());

        // Token was used in request
        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer mock-token-string'),
        );
      });
    });

    group('RSA8d - authCallback returns different token types', () {
      // UTS: rest/unit/RSA8d/callback-invoked-for-auth-0
      test('accepts TokenDetails return type', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8d-details');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
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
            authCallback: (params) async => TokenDetails(
              token: 'callback-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            ),
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer callback-token'),
        );
      });

      // UTS: rest/unit/RSA8d/callback-returns-jwt-1
      test('accepts String (token) return type', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8d-string');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
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
            authCallback: (params) async => 'raw-string-token',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer raw-string-token'),
        );
      });

      // UTS: rest/unit/RSA8d/callback-returns-token-request-2
      test('accepts TokenRequest return type', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8d-request');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.path.contains('requestToken')) {
              // First request: exchange TokenRequest for TokenDetails
              req.respondWith(200, {
                'token': 'exchanged-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                'keyName': 'appId.keyId',
              });
            } else {
              // Second request: actual publish
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async => TokenRequest(
              keyName: 'appId.keyId',
              ttl: 3600000,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              nonce: 'unique-nonce',
              mac: 'valid-mac-signature',
            ),
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        // First request should be token exchange
        expect(
          capturedRequests[0].url.path,
          equals('/keys/appId.keyId/requestToken'),
        );

        // Second request should use exchanged token
        expect(
          capturedRequests[1].headers['Authorization'],
          equals('Bearer exchanged-token'),
        );
      });
    });

    group('RSA8c - authUrl queries URL for token', () {
      // UTS: rest/unit/RSA8c/authurl-invoked-for-auth-0
      test('queries authUrl to obtain a token', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              // Response from authUrl
              req.respondWith(
                200,
                {'token': 'authurl-token', 'expires': 9999999999999},
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              // Response from Ably for publish
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/get-token',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        // First request goes to authUrl
        final authRequest = capturedRequests[0];
        expect(authRequest.url.host, equals('auth.example.com'));
        expect(authRequest.url.path, equals('/get-token'));

        // Subsequent request uses obtained token
        final publishRequest = capturedRequests[1];
        expect(
          publishRequest.headers['Authorization'],
          equals('Bearer authurl-token'),
        );
      });
    });

    group('RSA8c1a - authUrl with GET method', () {
      // UTS: rest/unit/RSA8c/authurl-returns-jwt-4
      test('sends TokenParams and authParams as query string', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c1a');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                'plain-token-string',
                headers: {'Content-Type': 'text/plain'},
              );
            } else {
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/token',
            authMethod: 'GET',
            authParams: {'custom': 'param1'},
            authHeaders: {'X-Custom-Header': 'value1'},
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final authRequest = capturedRequests[0];

        expect(authRequest.method, equals('GET'));
        expect(authRequest.url.queryParameters['custom'], equals('param1'));
        expect(authRequest.headers['X-Custom-Header'], equals('value1'));
        expect(authRequest.body, isEmpty);
      });
    });

    group('RSA8c1b - authUrl with POST method', () {
      // UTS: rest/unit/RSA8c/authurl-post-method-1
      test('sends TokenParams and authParams as form-encoded body', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c1b');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                {'token': 'post-token'},
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/token',
            authMethod: 'POST',
            authParams: {'custom': 'param1'},
            authHeaders: {'X-Custom-Header': 'value1'},
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final authRequest = capturedRequests[0];

        expect(authRequest.method, equals('POST'));
        expect(
          authRequest.headers['Content-Type'],
          equals('application/x-www-form-urlencoded'),
        );
        expect(authRequest.headers['X-Custom-Header'], equals('value1'));

        // Body should contain form params
        expect(authRequest.body, contains('custom=param1'));
      });
    });

    group('RSA8c1c - authUrl preserves existing query params', () {
      // UTS: rest/unit/RSA8c/authurl-query-params-3
      test('merges existing and new query params', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c1c');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                {'token': 'merged-token'},
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl:
                'https://auth.example.com/token?existing=value&another=123',
            authMethod: 'GET',
            authParams: {'added': 'new'},
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final authRequest = capturedRequests[0];

        // All params should be present
        expect(authRequest.url.queryParameters['existing'], equals('value'));
        expect(authRequest.url.queryParameters['another'], equals('123'));
        expect(authRequest.url.queryParameters['added'], equals('new'));
      });
    });

    group('RSA8c - authUrl custom headers', () {
      // UTS: rest/unit/RSA8c/authurl-custom-headers-2
      test('authUrl request includes custom headers from authHeaders',
          () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c-headers');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                {'token': 'custom-header-token', 'expires': 9999999999999},
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/get-token',
            authHeaders: {
              'X-Custom-Auth': 'my-secret',
              'X-Another-Header': 'another-value',
            },
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        // First request goes to authUrl
        final authRequest = capturedRequests[0];
        expect(authRequest.url.host, equals('auth.example.com'));
        expect(authRequest.headers['X-Custom-Auth'], equals('my-secret'));
        expect(
          authRequest.headers['X-Another-Header'],
          equals('another-value'),
        );
      });
    });

    group('RSA8c - authUrl error propagation', () {
      // UTS: rest/unit/RSA8c/authurl-error-propagated-5
      test('error from authUrl is propagated to the caller', () async {
        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            if (req.url.host == 'auth.example.com') {
              // authUrl returns an error
              req.respondWith(500, {
                'error': {
                  'code': 50000,
                  'statusCode': 500,
                  'message': 'Internal auth server error',
                },
              });
            } else {
              req.respondWith(200, {});
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/get-token',
          ),
          httpClient: mockHttp,
        );

        expect(
          () => client.channels
              .get(testChannelName('RSA8c-error'))
              .publish(name: 'e', data: 'd'),
          throwsA(isA<AblyException>()),
        );
      });
    });

    group('RSA8c2 - TokenParams take precedence over authParams', () {
      // UTS: rest/unit/RSA8d/callback-error-propagated-4
      test('uses TokenParams values when names conflict', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA8c2');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                {'token': 'precedence-token'},
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              req.respondWith(201, {
                'serials': ['s1'],
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/token',
            authMethod: 'GET',
            authParams: {
              'clientId': 'from-authParams',
              'custom': 'authParams-value',
            },
            clientId: 'from-tokenParams', // This becomes part of TokenParams
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).publish(name: 'e', data: 'd');

        final authRequest = capturedRequests[0];

        // TokenParams.clientId should override authParams.clientId
        expect(
          authRequest.url.queryParameters['clientId'],
          equals('from-tokenParams'),
        );
        // Non-conflicting authParams preserved
        expect(
          authRequest.url.queryParameters['custom'],
          equals('authParams-value'),
        );
      });
    });
  });
}

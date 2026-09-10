import 'dart:convert';

import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Auth Scheme Selection Tests
///
/// Spec points: RSA1, RSA2, RSA3, RSA4, RSA4a, RSA4b, RSA4c, RSA11
void main() {
  group('Auth Scheme Selection', () {
    group('RSA1 - API key format validation', () {
      final testCases = [
        (input: 'appId.keyId:keySecret', expected: 'Valid'),
        (input: 'appId.keyId', expected: 'Invalid'),
        (input: 'invalid-format', expected: 'Invalid'),
        (input: '', expected: 'Invalid'),
        (input: 'a.b:c', expected: 'Valid'),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/RSA1/token-auth-takes-precedence-0
        test('${testCase.input} is ${testCase.expected}', () {
          if (testCase.expected == 'Valid') {
            expect(
              () => ClientOptions.fromKey(testCase.input),
              returnsNormally,
            );
          } else {
            expect(
              () => ClientOptions.fromKey(testCase.input),
              throwsA(isA<ArgumentError>()),
            );
          }
        });
      }
    });

    group('RSA2, RSA11 - Basic auth when using API key', () {
      // UTS: rest/unit/RSA2/basic-auth-header-format-0
      test('uses Basic authentication header', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA2');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        final authHeader = request.headers['Authorization'];

        expect(authHeader, startsWith('Basic '));

        // Decode and verify
        final credentials = utf8.decode(
          base64.decode(authHeader!.substring(6)),
        );
        expect(credentials, equals('appId.keyId:keySecret'));
      });
    });

    group('RSA3 - Token auth when token provided', () {
      // UTS: rest/unit/RSA3/token-auth-explicit-token-0
      test('uses Bearer token authentication header', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA3');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options:
              ClientOptions(token: 'my-token-string', useBinaryProtocol: false),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer my-token-string'),
        );
      });

      // UTS: rest/unit/RSA3/token-auth-token-details-1
      test('extracts token from TokenDetails', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA3-details');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            tokenDetails: TokenDetails(
              token: 'token-from-details',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            ),
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer token-from-details'),
        );
      });
    });

    group('RSA4 - Auth method selection priority', () {
      // UTS: rest/unit/RSA4/authurl-triggers-token-3
      test('RSA4a - authCallback takes precedence', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4a');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
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

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer callback-token'),
        );
      });

      // No UTS spec: key + clientId retains basic auth; the clientId is
      // conveyed via the X-Ably-ClientId header per RSA7e2. (This test
      // previously asserted that key + clientId triggers token auth, which
      // contradicts features spec RSA7e2 and the push activation UTS specs,
      // e.g. uts/rest/unit/push/push_activation_state_machine.md
      // RSH3a2a1, whose identified clients must issue no token requests.)
      test('RSA7e2 - key + clientId uses Basic auth with X-Ably-ClientId',
          () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4b');

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
              // Token request
              req.respondWith(200, {
                'token': 'auto-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                'keyName': 'appId.keyId',
              });
            } else {
              // Actual request
              req.respondWith(200, {
                'channelId': channelName,
                'status': {'isActive': true},
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            clientId: 'my-client',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        // The single request uses Basic auth — no token request is made
        expect(capturedRequests.length, equals(1));
        expect(
          capturedRequests[0].headers['Authorization'],
          startsWith('Basic '),
        );

        // RSA7e2 — the clientId travels in the X-Ably-ClientId header,
        // Base64 encoded
        expect(
          capturedRequests[0].headers['X-Ably-ClientId'],
          equals(base64.encode(utf8.encode('my-client'))),
        );
      });

      // UTS: rest/unit/RSC18/token-auth-over-non-tls-0
      test('RSA4c - key only uses Basic auth', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4c');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(request.headers['Authorization'], startsWith('Basic '));
      });

      // UTS: rest/unit/RSA4/basic-auth-key-only-0
      test('authCallback takes precedence over key', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4-callback');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            authCallback: (params) async => 'callback-wins',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer callback-wins'),
        );
      });

      // UTS: rest/unit/RSA4/use-token-auth-forced-1
      test('explicit token takes precedence over key', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4-token');

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

            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            token: 'explicit-token',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final request = capturedRequests[0];
        expect(
          request.headers['Authorization'],
          equals('Bearer explicit-token'),
        );
      });
    });

    group('RSA4 - No auth credentials error', () {
      // UTS: rest/unit/RSC1b/no-auth-method-error-0
      test('throws error when no authentication method is configured', () {
        expect(
          () => RestClient(options: ClientOptions()),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40106),
            ),
          ),
        );
      });
    });
  });
}

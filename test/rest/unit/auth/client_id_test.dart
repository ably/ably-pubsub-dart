import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Client ID Tests
///
/// Spec points: RSA7, RSA7a, RSA7b, RSA7c, RSA12, RSA12a, RSA12b,
///              RSA15, RSA15a, RSA15b, RSA15c
void main() {
  group('Client ID', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSA7a - clientId from ClientOptions', () {
      /// Tests that clientId from ClientOptions is accessible via auth.clientId.
      // UTS: rest/unit/RSA7a/clientid-from-options-0
      test('accessible via auth.clientId', () {
        final client = RestClient(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            clientId: 'my-client-id',
          ),
        );

        expect(client.auth.clientId, equals('my-client-id'));
      });
    });

    group('RSA7b - clientId from TokenDetails', () {
      /// Tests that clientId is derived from TokenDetails when token auth
      /// is used.
      // UTS: rest/unit/RSA7b/clientid-from-token-details-0
      test('derived from TokenDetails when token auth is used', () async {
        final channelName = testChannelName('RSA7b-token');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            tokenDetails: TokenDetails(
              token: 'token-with-clientId',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'token-client-id',
            ),
          ),
          httpClient: mockHttp,
        );

        expect(client.auth.clientId, equals('token-client-id'));
      });

      /// Tests that clientId is extracted from TokenDetails returned by
      /// authCallback.
      // UTS: rest/unit/RSA7b/clientid-from-callback-token-1
      test('extracted from authCallback TokenDetails', () async {
        final channelName = testChannelName('RSA7b-callback');
        mockHttp = MockHttpClient(
          onRequest: (req) {
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
              clientId: 'callback-client-id',
            ),
          ),
          httpClient: mockHttp,
        );

        // Trigger auth by making a request
        await client.channels.get(channelName).status();

        expect(client.auth.clientId, equals('callback-client-id'));
      });
    });

    group('RSA7c - clientId null when unidentified', () {
      /// Tests that auth.clientId is null when no client identity is
      /// established.
      // UTS: rest/unit/RSA7c/clientid-null-unidentified-0
      test('null when no client identity is established', () {
        final client = RestClient(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
        );

        expect(client.auth.clientId, isNull);
      });

      /// Tests that auth.clientId is null when token has no clientId.
      // UTS: rest/unit/RSA7c/clientid-null-unidentified-token-1
      test('null when token has no clientId', () async {
        final channelName = testChannelName('RSA7c-null');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            tokenDetails: TokenDetails(
              token: 'token-without-clientId',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              // No clientId in token
            ),
          ),
          httpClient: mockHttp,
        );

        expect(client.auth.clientId, isNull);
      });
    });

    group('RSA12a - clientId passed to authCallback in TokenParams', () {
      /// Tests that clientId is passed to authCallback via TokenParams.
      // UTS: rest/unit/RSA12a/clientid-passed-to-callback-0
      test('passed to authCallback via TokenParams', () async {
        final receivedParams = <TokenParams>[];
        final channelName = testChannelName('RSA12a');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              receivedParams.add(params);
              return TokenDetails(
                token: 'tok',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            },
            clientId: 'library-client-id',
          ),
          httpClient: mockHttp,
        );

        // Trigger auth
        await client.channels.get(channelName).status();

        expect(receivedParams.length, greaterThanOrEqualTo(1));
        expect(receivedParams[0].clientId, equals('library-client-id'));
      });
    });

    group('RSA12b - clientId sent to authUrl', () {
      /// Tests that clientId is sent as a parameter when using authUrl.
      // UTS: rest/unit/RSA12b/clientid-sent-to-authurl-0
      test('sent as parameter when using authUrl', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA12b');

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

            if (req.url.host == 'auth.example.com') {
              req.respondWith(
                200,
                {
                  'token': 'url-token',
                  'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                },
                headers: {'Content-Type': 'application/json'},
              );
            } else {
              req.respondWith(200, {
                'channelId': channelName,
                'status': {'isActive': true},
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://auth.example.com/token',
            clientId: 'url-client-id',
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).status();

        final authRequest = capturedRequests[0];
        expect(authRequest.url.host, equals('auth.example.com'));

        // clientId should be in query params (GET) or body (POST)
        if (authRequest.method == 'GET') {
          expect(
            authRequest.url.queryParameters['clientId'],
            equals('url-client-id'),
          );
        } else {
          // For POST, check body params
          expect(authRequest.body, contains('url-client-id'));
        }
      });
    });

    group('RSA7 - clientId updated after authorize()', () {
      /// Tests that auth.clientId is updated when authorize() returns a new
      /// token with different clientId.
      // UTS: rest/unit/RSA7/clientid-updated-after-authorize-0
      test('updated when authorize() returns new token', () async {
        var tokenCount = 0;
        final channelName = testChannelName('RSA7-update');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              tokenCount++;
              return TokenDetails(
                token: 'token-$tokenCount',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
                clientId: 'client-$tokenCount',
              );
            },
          ),
          httpClient: mockHttp,
        );

        // First auth
        await client.channels.get(channelName).status();

        expect(client.auth.clientId, equals('client-1'));

        // Second auth with explicit authorize
        await client.auth.authorize();

        expect(client.auth.clientId, equals('client-2'));
      });
    });

    group('RSA12 - Wildcard clientId', () {
      /// Tests handling of wildcard * clientId.
      // UTS: rest/unit/RSA12/wildcard-clientid-0
      test('wildcard * clientId is preserved', () async {
        final channelName = testChannelName('RSA12-wildcard');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            tokenDetails: TokenDetails(
              token: 'wildcard-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: '*', // Wildcard
            ),
          ),
          httpClient: mockHttp,
        );

        // Wildcard clientId should be preserved
        expect(client.auth.clientId, equals('*'));
      });
    });

    group('RSA7, RSA15 - clientId consistency between ClientOptions and token',
        () {
      /// Tests that clientId in ClientOptions matches token clientId.
      // UTS: rest/unit/RSA15a/token-clientid-must-match-0
      test('matching clientId in ClientOptions and token - success', () async {
        final channelName = testChannelName('RSA7-match');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            clientId: 'client-a',
            tokenDetails: TokenDetails(
              token: 'matched-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'client-a', // Same as ClientOptions
            ),
          ),
          httpClient: mockHttp,
        );

        // Should not throw
        await client.channels.get(channelName).status();
        expect(client.auth.clientId, equals('client-a'));
      });

      /// Tests that mismatch between ClientOptions and token clientId causes
      /// an error.
      // UTS: rest/unit/RSA7/clientid-mismatch-error-1
      test('mismatched clientId in ClientOptions and token - error', () async {
        final channelName = testChannelName('RSA7-mismatch');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        // RSA7: Mismatch is detected during client construction
        expect(
          () => RestClient.forTesting(
            options: ClientOptions(
              clientId: 'client-a',
              tokenDetails: TokenDetails(
                token: 'mismatched-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
                clientId: 'client-b', // Different from ClientOptions
              ),
            ),
            httpClient: mockHttp,
          ),
          throwsA(
            isA<AblyException>().having(
              (e) => e.message?.toLowerCase(),
              'message',
              allOf(contains('clientid'), contains('mismatch')),
            ),
          ),
        );
      });

      /// Tests that ClientOptions clientId with null token clientId succeeds.
      // UTS: rest/unit/RSA15c/incompatible-clientid-error-0
      test('ClientOptions clientId with null token clientId - success',
          () async {
        final channelName = testChannelName('RSA7-null-token');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            clientId: 'client-a',
            tokenDetails: TokenDetails(
              token: 'token-without-clientId',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              // No clientId in token
            ),
          ),
          httpClient: mockHttp,
        );

        // Should not throw - client keeps explicit clientId
        await client.channels.get(channelName).status();
        expect(client.auth.clientId, equals('client-a'));
      });

      /// Tests that wildcard token clientId allows any ClientOptions clientId.
      // UTS: rest/unit/RSA15b/wildcard-token-permits-any-0
      test('ClientOptions clientId with wildcard token - success', () async {
        final channelName = testChannelName('RSA7-wildcard');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            clientId: 'client-a',
            tokenDetails: TokenDetails(
              token: 'wildcard-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: '*', // Wildcard allows any
            ),
          ),
          httpClient: mockHttp,
        );

        // Should not throw - wildcard allows any clientId
        await client.channels.get(channelName).status();
        // RSA7: When token has wildcard, return the options clientId
        expect(client.auth.clientId, equals('client-a'));
      });

      /// Tests that null ClientOptions clientId inherits from token.
      // UTS: rest/unit/RSA7c/clientid-null-unidentified-token-1.1
      test('null ClientOptions clientId inherits from token - success',
          () async {
        final channelName = testChannelName('RSA7-inherit');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            // No clientId in ClientOptions
            tokenDetails: TokenDetails(
              token: 'token-with-clientId',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'client-b',
            ),
          ),
          httpClient: mockHttp,
        );

        // Should inherit from token
        await client.channels.get(channelName).status();
        expect(client.auth.clientId, equals('client-b'));
      });
    });
  });
}

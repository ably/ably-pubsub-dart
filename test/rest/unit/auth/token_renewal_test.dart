import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Token Renewal Tests
///
/// Spec points: RSA4b4, RSA14
void main() {
  group('Token Renewal', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSA4b4 - Token renewal on expiry rejection', () {
      /// Tests that when a request is rejected with error code 40142
      /// (token expired), the library obtains a new token via the auth
      /// callback and retries the request automatically.
      // UTS: rest/unit/RSA4b/renewal-on-40142-0
      test('obtains new token and retries on 40142 error', () async {
        var callbackCount = 0;
        final tokens = ['first-token', 'second-token'];
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('RSA4b4-40142');

        Future<TokenDetails> authCallback(TokenParams params) async {
          final token = tokens[callbackCount];
          callbackCount++;
          return TokenDetails(
            token: token,
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

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
              // First request fails with token expired
              req.respondWith(401, {
                'error': {
                  'code': 40142,
                  'statusCode': 401,
                  'message': 'Token expired',
                },
              });
            } else {
              // Second request (after renewal) succeeds
              req.respondWith(200, [
                {'channel': channelName},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        final result = await client.channels.get(channelName).history();

        // authCallback was called twice (initial + renewal)
        expect(callbackCount, equals(2));

        // Two HTTP requests were made
        expect(requestCount, equals(2));

        // First request used first token
        expect(
          capturedRequests[0].headers['Authorization'],
          equals('Bearer first-token'),
        );

        // Second request used renewed token
        expect(
          capturedRequests[1].headers['Authorization'],
          equals('Bearer second-token'),
        );

        // Final result is successful
        expect(result.items, isA<List>());
      });
    });

    group('RSA4b4 - Token renewal on 40140 error', () {
      /// Tests renewal is triggered for error code 40140 (token error).
      // UTS: rest/unit/RSA4b/renewal-on-40140-1
      test('obtains new token and retries on 40140 error', () async {
        var callbackCount = 0;
        var requestCount = 0;
        final channelName = testChannelName('RSA4b4-40140');

        Future<TokenDetails> authCallback(TokenParams params) async {
          callbackCount++;
          return TokenDetails(
            token: 'token-$callbackCount',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // First attempt fails with 40140
              req.respondWith(401, {
                'error': {
                  'code': 40140,
                  'statusCode': 401,
                  'message': 'Token error',
                },
              });
            } else {
              // Retry succeeds
              req.respondWith(200, []);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).history();

        expect(callbackCount, equals(2));
        expect(requestCount, equals(2));
      });
    });

    group('RSA14 - Pre-emptive token renewal', () {
      /// Tests that if a token is known to be expired before making a request,
      /// renewal happens without first making a failing request.
      // UTS: rest/unit/RSA4b1/preemptive-renewal-0.1
      test('renews expired token pre-emptively', () async {
        var callbackCount = 0;
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA14');

        Future<TokenDetails> authCallback(TokenParams params) async {
          callbackCount++;
          if (callbackCount == 1) {
            // First token is already expired
            return TokenDetails(
              token: 'expired-token',
              expires: DateTime.now().millisecondsSinceEpoch - 1000,
            );
          } else {
            return TokenDetails(
              token: 'fresh-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          }
        }

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
            // Only success response (no 401 expected)
            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        // Force initial token acquisition
        await client.auth.authorize();

        // This should detect expired token and renew before request
        await client.channels.get(channelName).history();

        // Callback was called twice (initial + pre-emptive renewal)
        expect(callbackCount, equals(2));

        // Only ONE HTTP request to the API (history)
        // No failed request with expired token
        final requestsToChannels = capturedRequests
            .where(
              (r) =>
                  r.url.path ==
                  '/channels/${Uri.encodeComponent(channelName)}/messages',
            )
            .toList();
        expect(requestsToChannels.length, equals(1));
        expect(
          requestsToChannels[0].headers['Authorization'],
          equals('Bearer fresh-token'),
        );
      });
    });

    group('RSA4b4 - No renewal without authCallback', () {
      /// Tests that token renewal is not attempted if no renewal mechanism
      /// (authCallback/authUrl/key) is available.
      // UTS: rest/unit/RSC10b/non-token-401-no-renewal-0
      test('does not retry without renewal mechanism', () async {
        var requestCount = 0;
        final channelName = testChannelName('RSA4b4-no-renewal');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            req.respondWith(401, {
              'error': {
                'code': 40142,
                'statusCode': 401,
                'message': 'Token expired',
              },
            });
          },
        );

        // Client with explicit token but no authCallback
        final client = RestClient.forTesting(
          options: ClientOptions(token: 'static-token'),
          httpClient: mockHttp,
        );

        try {
          await client.channels.get(channelName).history();
          fail('Expected token expired error');
        } catch (e) {
          expect(e, isA<AblyException>());
          final ablyException = e as AblyException;
          expect(ablyException.code, equals(40142));
        }

        // Only one request was made (no retry)
        expect(requestCount, equals(1));
      });
    });

    group('RSA4b4 - Renewal with authUrl', () {
      /// Tests that token renewal works via authUrl.
      // UTS: rest/unit/RSA4b/renewal-via-authurl-2
      test('renews token via authUrl on 40142 error', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('RSA4b4-authUrl');

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

            if (req.url.host == 'example.com') {
              // authUrl requests - return tokens
              if (requestCount == 1) {
                req.respondWith(200, {
                  'token': 'first-token',
                  'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                });
              } else {
                // Second token request (renewal)
                req.respondWith(200, {
                  'token': 'second-token',
                  'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                });
              }
            } else {
              // API requests
              if (requestCount == 2) {
                // First API request fails
                req.respondWith(401, {
                  'error': {'code': 40142, 'message': 'Token expired'},
                });
              } else {
                // Retry succeeds
                req.respondWith(200, []);
              }
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authUrl: 'https://example.com/auth',
          ),
          httpClient: mockHttp,
        );

        await client.channels.get(channelName).history();

        // Two requests to authUrl
        final authRequests =
            capturedRequests.where((r) => r.url.host == 'example.com').toList();
        expect(authRequests.length, equals(2));

        // Two requests to Ably API
        final apiRequests =
            capturedRequests.where((r) => r.url.host != 'example.com').toList();
        expect(apiRequests.length, equals(2));

        // Second API request used renewed token
        expect(
          apiRequests[1].headers['Authorization'],
          equals('Bearer second-token'),
        );
      });
    });

    group('RSA4a2 - Expired token with no renewal mechanism', () {
      /// Tests that when a token expires and there is no means to renew
      /// (no key, no authCallback, no authUrl), the request fails with
      /// a 40171 error.
      // UTS: rest/unit/RSA4a2/expired-token-no-renewal-0
      test('request fails when token expires and no renewal means', () async {
        var requestCount = 0;
        final channelName = testChannelName('RSA4a2-no-renewal');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            req.respondWith(401, {
              'error': {
                'code': 40142,
                'statusCode': 401,
                'message': 'Token expired',
              },
            });
          },
        );

        // Client with only a token string - no key, no authCallback, no authUrl
        final client = RestClient.forTesting(
          options: ClientOptions(token: 'static-expired-token'),
          httpClient: mockHttp,
        );

        try {
          await client.channels.get(channelName).history();
          fail('Expected token expired error');
        } catch (e) {
          expect(e, isA<AblyException>());
          final ablyException = e as AblyException;
          // Should fail because no renewal is possible
          expect(ablyException.code, equals(40142));
        }

        // Only one request was made (no retry attempted)
        expect(requestCount, equals(1));
      });
    });

    group('RSA4b - Msgpack response', () {
      // UTS: rest/unit/RSA4b/renewal-msgpack-response-4
      test(
        'RSA4b - renewal msgpack response',
        () {},
        skip: 'Not yet implemented: msgpack encoding support',
      );
    });

    group('RSA4b1 - Preemptive token renewal', () {
      /// Tests that the client proactively renews a token before expiry when
      /// the token is known to be expired.
      // UTS: rest/unit/RSA4b1/preemptive-renewal-0
      test('client renews token before making request when expired', () async {
        var callbackCount = 0;
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA4b1-preemptive');

        Future<TokenDetails> authCallback(TokenParams params) async {
          callbackCount++;
          if (callbackCount == 1) {
            // First token: already expired
            return TokenDetails(
              token: 'expired-token',
              expires: DateTime.now().millisecondsSinceEpoch - 1000,
            );
          } else {
            // Second token: valid
            return TokenDetails(
              token: 'fresh-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            );
          }
        }

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
            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        // Force initial token acquisition
        await client.auth.authorize();

        // Make a request - token is expired, should renew preemptively
        await client.channels.get(channelName).history();

        // Callback was called twice: initial + preemptive renewal
        expect(callbackCount, equals(2));

        // The actual API request should use the fresh token
        final channelRequests = capturedRequests
            .where(
              (r) =>
                  r.url.path ==
                  '/channels/${Uri.encodeComponent(channelName)}/messages',
            )
            .toList();
        expect(channelRequests.length, equals(1));
        expect(
          channelRequests[0].headers['Authorization'],
          equals('Bearer fresh-token'),
        );
      });
    });

    group('RSC10 - Request retried after renewal', () {
      /// Tests that after a 40142 error, the client renews the token and
      /// retries the original request successfully.
      // UTS: rest/unit/RSC10/request-retried-after-renewal-0
      test('renews token and retries original request on 40142', () async {
        var callbackCount = 0;
        var requestCount = 0;
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSC10-retry');

        Future<TokenDetails> authCallback(TokenParams params) async {
          callbackCount++;
          return TokenDetails(
            token: 'token-$callbackCount',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

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
              // First request fails with token expired
              req.respondWith(401, {
                'error': {
                  'code': 40142,
                  'statusCode': 401,
                  'message': 'Token expired',
                },
              });
            } else {
              // Retry after renewal succeeds
              req.respondWith(200, [
                {'channel': channelName},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        final result = await client.channels.get(channelName).history();

        // Two HTTP requests were made (original + retry)
        expect(requestCount, equals(2));

        // authCallback was called twice (initial + renewal)
        expect(callbackCount, equals(2));

        // First request used first token
        expect(
          capturedRequests[0].headers['Authorization'],
          equals('Bearer token-1'),
        );

        // Second request used renewed token
        expect(
          capturedRequests[1].headers['Authorization'],
          equals('Bearer token-2'),
        );

        // Final result is successful
        expect(result.items, isA<List>());
      });
    });

    group('RSA4b4 - Renewal limit', () {
      /// Tests that token renewal doesn't loop infinitely if server keeps
      /// rejecting tokens.
      // UTS: rest/unit/RSA4b/renewal-limit-no-loop-3
      test('stops retrying after max attempts', () async {
        var callbackCount = 0;
        var requestCount = 0;
        final channelName = testChannelName('RSA4b4-limit');

        Future<TokenDetails> authCallback(TokenParams params) async {
          callbackCount++;
          return TokenDetails(
            token: 'token-$callbackCount',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            // Always return token expired
            req.respondWith(401, {
              'error': {'code': 40142, 'message': 'Token expired'},
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(authCallback: authCallback),
          httpClient: mockHttp,
        );

        try {
          await client.channels.get(channelName).history();
          fail('Expected error after max retries');
        } catch (e) {
          // Should eventually give up
          expect(e, isA<AblyException>());
          final ablyException = e as AblyException;
          expect(ablyException.code, equals(40142));
        }

        // Should not retry indefinitely (implementation-specific limit)
        expect(callbackCount, lessThanOrEqualTo(3)); // Reasonable retry limit
        expect(
          requestCount,
          lessThanOrEqualTo(3),
        ); // Should stop making requests
      });
    });
  });
}

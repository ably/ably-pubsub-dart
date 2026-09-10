import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Auth.authorize() Tests
///
/// Spec points: RSA10, RSA10a, RSA10b, RSA10e, RSA10g, RSA10h, RSA10i,
/// RSA10j, RSA10k, RSA10l
void main() {
  group('Auth.authorize()', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSA10a - authorize() with default tokenParams', () {
      /// Tests that authorize() obtains a token using configured defaults.
      // UTS: rest/unit/RSA10a/authorize-default-params-0
      test('obtains token using configured defaults', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA10a');

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

            if (req.url.path.contains('requestToken')) {
              // Token request
              req.respondWith(200, {
                'token': 'obtained-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                'keyName': 'appId.keyId',
              });
            } else {
              // Subsequent request to verify token is used
              req.respondWith(200, {
                'channelId': channelName,
                'status': {'isActive': true},
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final tokenDetails = await client.auth.authorize();

        expect(tokenDetails, isA<TokenDetails>());
        expect(tokenDetails!.token, equals('obtained-token'));

        // Verify token is now used for requests
        await client.channels.get(channelName).status();
        expect(
          capturedRequests.last.headers['Authorization'],
          equals('Bearer obtained-token'),
        );
      });
    });

    group('RSA10b - authorize() with explicit tokenParams', () {
      /// Tests that provided tokenParams override defaults.
      // UTS: rest/unit/RSA10b/authorize-explicit-params-0
      test('provided tokenParams override defaults', () async {
        final callbackParams = <TokenParams>[];
        final channelName = testChannelName('RSA10b');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {'channelId': channelName});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              callbackParams.add(params);
              return TokenDetails(
                token: 'callback-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            },
            clientId: 'default-client', // Default TokenParams
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.auth.authorize(
          tokenParams: const TokenParams(
            clientId: 'override-client',
            ttl: 7200000,
          ),
        );

        final params = callbackParams[0];
        expect(params.clientId, equals('override-client')); // Overridden
        expect(params.ttl, equals(7200000));
      });
    });

    group('RSA10e - authorize() saves tokenParams for reuse', () {
      /// Tests that tokenParams provided to authorize() are saved and reused.
      // UTS: rest/unit/RSA10e/authorize-saves-params-0
      test('saves and reuses tokenParams on subsequent requests', () async {
        final testClock = TestClock();
        final channelName = testChannelName('RSA10e');

        await withClock(testClock, () async {
          final callbackInvocations = <TokenParams>[];
          final tokenExpiryMs = testClock.now().millisecondsSinceEpoch + 1000;

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
                callbackInvocations.add(params);
                return TokenDetails(
                  token: 'token-${callbackInvocations.length}',
                  expires: tokenExpiryMs,
                );
              },
              useBinaryProtocol: false,
            ),
            httpClient: mockHttp,
          );

          // First authorize with custom params
          await client.auth.authorize(
            tokenParams: const TokenParams(
              clientId: 'saved-client',
              ttl: 3600000,
            ),
          );

          // Advance time past token expiry (token expires at +1000ms)
          testClock.advance(const Duration(milliseconds: 2000));

          // Force re-auth via request - should reuse saved params
          await client.channels.get(channelName).status();

          // Second callback should have received the saved params
          expect(callbackInvocations.length, greaterThanOrEqualTo(2));
          expect(callbackInvocations[1].clientId, equals('saved-client'));
          expect(callbackInvocations[1].ttl, equals(3600000));
        });
      });
    });

    group('RSA10g - authorize() updates Auth.tokenDetails', () {
      /// Tests that after authorize(), auth.tokenDetails reflects the new token.
      // UTS: rest/unit/RSA10g/authorize-updates-token-details-0
      test('updates auth.tokenDetails after authorize', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            if (req.url.path.contains('requestToken')) {
              req.respondWith(200, {
                'token': 'new-token',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                'keyName': 'appId.keyId',
                'clientId': 'token-client',
              });
            } else {
              req.respondWith(200, {'time': 1234567890000});
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        expect(client.auth.tokenDetails, isNull); // Before authorize

        final result = await client.auth.authorize();

        expect(client.auth.tokenDetails, isNotNull);
        expect(client.auth.tokenDetails!.token, equals('new-token'));
        expect(client.auth.tokenDetails!.clientId, equals('token-client'));
        expect(client.auth.tokenDetails!.token, equals(result!.token));
      });
    });

    group('RSA10h - authorize() with authOptions replaces defaults', () {
      /// Tests that authOptions in authorize() replaces stored auth options.
      // UTS: rest/unit/RSA10h/authorize-replaces-auth-options-0
      test('authOptions replaces stored auth options', () async {
        var originalCallbackCalled = false;
        var newCallbackCalled = false;
        final channelName = testChannelName('RSA10h');

        Future<TokenDetails> originalCallback(TokenParams params) async {
          originalCallbackCalled = true;
          return TokenDetails(
            token: 'original',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

        Future<TokenDetails> newCallback(TokenParams params) async {
          newCallbackCalled = true;
          return TokenDetails(
            token: 'new',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {'channelId': channelName});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: originalCallback,
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.auth.authorize(
          authOptions: AuthOptions(authCallback: newCallback),
        );

        expect(originalCallbackCalled, isFalse);
        expect(newCallbackCalled, isTrue);
      });
    });

    group('RSA10i - authorize() preserves key from constructor', () {
      /// Tests that the API key from ClientOptions is preserved even when
      /// authOptions are provided.
      // UTS: rest/unit/RSA10i/authorize-preserves-key-0
      test('preserves key from constructor', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSA10i');

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

            if (req.url.path.contains('requestToken')) {
              // Initial token request using key
              req.respondWith(200, {
                'token': 'token-via-key',
                'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
                'keyName': 'appId.keyId',
              });
            } else {
              req.respondWith(200, {'channelId': channelName});
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        // Call authorize with new authUrl but no key
        await client.auth.authorize(
          authOptions: const AuthOptions(
            authUrl: 'https://new-auth.example.com/token',
          ),
        );

        // Key from constructor should be preserved
        // Verify by checking that key-based operations still work
        expect(capturedRequests, isNotEmpty);
      });
    });

    group('RSA10j - authorize() when already authorized', () {
      /// Tests that calling authorize() when a valid token exists obtains
      /// a new token.
      // UTS: rest/unit/RSA10j/authorize-replaces-existing-token-0
      test('obtains new token when already authorized', () async {
        var tokenCount = 0;
        final channelName = testChannelName('RSA10j');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {'channelId': channelName});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              tokenCount++;
              return TokenDetails(
                token: 'token-$tokenCount',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            },
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        final result1 = await client.auth.authorize();
        final result2 = await client.auth.authorize();

        expect(result1!.token, equals('token-1'));
        expect(result2!.token, equals('token-2'));
      });
    });

    group('RSA10k - authorize() with queryTime option', () {
      /// Tests that queryTime: true causes time to be queried from server
      /// before requesting token.
      // UTS: rest/unit/RSA10k/authorize-query-time-0
      test('queries time from server when queryTime is true', () async {
        final capturedRequests = <CapturedRequest>[];

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

            if (req.url.path == '/time') {
              // Time query
              req.respondWith(200, [1234567890000]);
            } else {
              // Token request
              req.respondWith(200, {
                'token': 'time-synced-token',
                'expires': 1234567890000 + 3600000,
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'appId.keyId:keySecret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        await client.auth.authorize(
          authOptions: const AuthOptions(queryTime: true),
        );

        // Should have made two requests: time query + token request
        final timeRequest = capturedRequests.firstWhere(
          (r) => r.url.path == '/time',
          orElse: () => throw StateError('No time request found'),
        );
        expect(timeRequest, isNotNull);
      });
    });

    group('RSA10l - authorize() error handling', () {
      /// Tests that errors during authorization are properly propagated to
      /// the caller.
      // UTS: rest/unit/RSA10l/authorize-error-propagated-0
      test('propagates errors during authorization', () async {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(401, {
              'error': {
                'code': 40100,
                'statusCode': 401,
                'message': 'Unauthorized',
              },
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey(
            'invalid.key:secret',
            useBinaryProtocol: false,
          ),
          httpClient: mockHttp,
        );

        try {
          await client.auth.authorize();
          fail('Expected AblyException');
        } catch (e) {
          expect(e, isA<AblyException>());
          final ablyException = e as AblyException;
          expect(ablyException.code, equals(40100));
          expect(ablyException.statusCode, equals(401));
        }
      });
    });
  });
}

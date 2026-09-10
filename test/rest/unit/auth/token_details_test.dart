import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// Auth.tokenDetails Tests (RSA16)
///
/// Spec points: RSA16, RSA16a, RSA16b, RSA16c, RSA16d
void main() {
  late MockHttpClient mockHttp;

  late String defaultChannelName;

  setUp(() {
    defaultChannelName = testChannelName('RSA16-default');
    mockHttp = MockHttpClient(
      onRequest: (req) {
        req.respondWith(200, {
          'channelId': defaultChannelName,
          'status': {'isActive': true},
        });
      },
    );
  });

  group('RSA16a - tokenDetails holds current token', () {
    // UTS: rest/unit/RSA16a/token-from-callback-0
    test('tokenDetails reflects token from authCallback', () async {
      final channelName = testChannelName('RSA16a-callback');
      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async => TokenDetails(
            token: 'callback-token-abc',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            issued: DateTime.now().millisecondsSinceEpoch,
            clientId: 'my-client',
          ),
        ),
        httpClient: mockHttp,
      );

      // Force token acquisition by making a request
      await client.channels.get(channelName).status();

      expect(client.auth.tokenDetails, isNotNull);
      expect(client.auth.tokenDetails!.token, equals('callback-token-abc'));
      expect(client.auth.tokenDetails!.clientId, equals('my-client'));
      expect(client.auth.tokenDetails!.expires, isNotNull);
      expect(client.auth.tokenDetails!.issued, isNotNull);
    });

    // UTS: rest/unit/RSA16a/token-from-request-token-1
    test('tokenDetails reflects token from requestToken', () async {
      final channelName = testChannelName('RSA16a-request');
      mockHttp = MockHttpClient(
        onRequest: (req) {
          if (req.url.path.contains('requestToken')) {
            req.respondWith(200, {
              'token': 'requested-token-xyz',
              'expires': DateTime.now().millisecondsSinceEpoch + 3600000,
              'issued': DateTime.now().millisecondsSinceEpoch,
              'keyName': 'appId.keyId',
              'clientId': 'token-client',
            });
          } else {
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          }
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      // Explicitly authorize to get a token
      await client.auth.authorize();

      expect(client.auth.tokenDetails, isNotNull);
      expect(client.auth.tokenDetails!.token, equals('requested-token-xyz'));
      expect(client.auth.tokenDetails!.clientId, equals('token-client'));
    });
  });

  group('RSA16b - tokenDetails with token string only', () {
    // UTS: rest/unit/RSA16b/token-string-in-options-0
    test('tokenDetails created from token string in ClientOptions', () {
      // Provide only a token string, not full TokenDetails
      final client = RestClient.forTesting(
        options: ClientOptions(token: 'standalone-token-string'),
        httpClient: mockHttp,
      );

      // Access tokenDetails immediately after construction
      final tokenDetails = client.auth.tokenDetails;

      expect(tokenDetails, isNotNull);
      expect(tokenDetails!.token, equals('standalone-token-string'));
      // Other fields should be null since we only had the token string
      expect(tokenDetails.expires, isNull);
      expect(tokenDetails.issued, isNull);
      expect(tokenDetails.clientId, isNull);
      expect(tokenDetails.capability, isNull);
    });

    // UTS: rest/unit/RSA16b/token-string-from-callback-1
    test('tokenDetails created from token string returned by authCallback',
        () async {
      final channelName = testChannelName('RSA16b-string');
      // authCallback returns just a token string, not TokenDetails
      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async => 'just-a-token-string',
        ),
        httpClient: mockHttp,
      );

      // Force token acquisition
      await client.channels.get(channelName).status();

      expect(client.auth.tokenDetails, isNotNull);
      expect(client.auth.tokenDetails!.token, equals('just-a-token-string'));
      // Other fields should be null
      expect(client.auth.tokenDetails!.expires, isNull);
      expect(client.auth.tokenDetails!.issued, isNull);
    });
  });

  group('RSA16c - tokenDetails updated on token changes', () {
    // UTS: rest/unit/RSA16c/set-on-instantiation-0
    test('tokenDetails set on instantiation with tokenDetails option', () {
      final initialToken = TokenDetails(
        token: 'initial-token',
        expires: DateTime.now().millisecondsSinceEpoch + 3600000,
        issued: DateTime.now().millisecondsSinceEpoch,
        clientId: 'initial-client',
      );

      final client = RestClient.forTesting(
        options: ClientOptions(tokenDetails: initialToken),
        httpClient: mockHttp,
      );

      // Access tokenDetails immediately after construction
      final tokenDetails = client.auth.tokenDetails;

      expect(tokenDetails, isNotNull);
      expect(tokenDetails!.token, equals('initial-token'));
      expect(tokenDetails.clientId, equals('initial-client'));
    });

    // UTS: rest/unit/RSA16c/updated-after-authorize-1
    test('tokenDetails updated after explicit authorize()', () async {
      var tokenCount = 0;

      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            tokenCount++;
            return TokenDetails(
              token: 'token-v$tokenCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'client-v$tokenCount',
            );
          },
        ),
        httpClient: mockHttp,
      );

      // First authorize
      await client.auth.authorize();
      final firstToken = client.auth.tokenDetails;

      // Second authorize
      await client.auth.authorize();
      final secondToken = client.auth.tokenDetails;

      expect(firstToken!.token, equals('token-v1'));
      expect(firstToken.clientId, equals('client-v1'));

      expect(secondToken!.token, equals('token-v2'));
      expect(secondToken.clientId, equals('client-v2'));

      // Verify it's actually updated, not the same object
      expect(firstToken.token, isNot(equals(secondToken.token)));
    });

    // UTS: rest/unit/RSA16c/updated-after-expiry-renewal-2
    test('tokenDetails updated after library-initiated renewal on expiry',
        () async {
      final testClock = TestClock();
      final channelName = testChannelName('RSA16c-expiry');

      await withClock(testClock, () async {
        var tokenCount = 0;
        final tokenExpiryMs = testClock.now().millisecondsSinceEpoch + 1000;

        final client = RestClient.forTesting(
          options: ClientOptions(
            authCallback: (params) async {
              tokenCount++;
              return TokenDetails(
                token: 'token-v$tokenCount',
                expires: tokenExpiryMs,
                clientId: 'client-v$tokenCount',
              );
            },
          ),
          httpClient: mockHttp,
        );

        // First request - gets initial token
        await client.channels.get(channelName).status();
        final firstToken = client.auth.tokenDetails;

        // Advance time past token expiry
        testClock.advance(const Duration(milliseconds: 2000));

        // Second request - should trigger renewal
        await client.channels.get(channelName).status();
        final secondToken = client.auth.tokenDetails;

        expect(firstToken!.token, equals('token-v1'));
        expect(secondToken!.token, equals('token-v2'));
      });
    });

    // UTS: rest/unit/RSA16c/updated-after-40142-renewal-3
    test('tokenDetails updated after library-initiated renewal on 40142 error',
        () async {
      var requestCount = 0;
      var tokenCount = 0;
      final channelName = testChannelName('RSA16c-40142');

      mockHttp = MockHttpClient(
        onRequest: (req) {
          requestCount++;
          if (requestCount == 1) {
            // First request fails with token expired error
            req.respondWith(401, {
              'error': {
                'code': 40142,
                'statusCode': 401,
                'message': 'Token expired',
              },
            });
          } else {
            // Subsequent requests succeed
            req.respondWith(200, {
              'channelId': channelName,
              'status': {'isActive': true},
            });
          }
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            tokenCount++;
            return TokenDetails(
              token: 'token-v$tokenCount',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'client-v$tokenCount',
            );
          },
        ),
        httpClient: mockHttp,
      );

      // First get a token
      await client.auth.authorize();
      final firstToken = client.auth.tokenDetails;

      // Make a request that will fail with 40142, triggering renewal
      await client.channels.get(channelName).status();
      final secondToken = client.auth.tokenDetails;

      expect(firstToken!.token, equals('token-v1'));
      expect(secondToken!.token, equals('token-v2'));
    });
  });

  group('RSA16d - tokenDetails is null when appropriate', () {
    // UTS: rest/unit/RSA16d/null-with-basic-auth-0
    test('tokenDetails is null when using basic auth', () async {
      final channelName = testChannelName('RSA16d-basic');
      // Client with only API key - uses basic auth
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      // Make a request using basic auth (no token)
      await client.channels.get(channelName).status();

      // Should be null because we're using basic auth, not token auth
      expect(client.auth.tokenDetails, isNull);
    });

    // UTS: rest/unit/RSA16d/null-before-token-obtained-1
    test('tokenDetails is null before any token is obtained', () {
      // Client configured for token auth but no request made yet
      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async => TokenDetails(
            token: 'my-token',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          ),
        ),
        httpClient: mockHttp,
      );

      // Don't make any requests - just check tokenDetails
      final tokenDetails = client.auth.tokenDetails;

      // Should be null because no token has been obtained yet
      expect(tokenDetails, isNull);
    });

    // UTS: rest/unit/RSA16d/null-after-invalidation-2
    test('tokenDetails is null after token invalidation', () async {
      var callbackCount = 0;
      final channelName = testChannelName('RSA16d-invalid');

      mockHttp = MockHttpClient(
        onRequest: (req) {
          // Always fail with token error
          req.respondWith(401, {
            'error': {
              'code': 40142,
              'statusCode': 401,
              'message': 'Token expired',
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            callbackCount++;
            if (callbackCount == 1) {
              return TokenDetails(
                token: 'first-token',
                expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              );
            } else {
              // Second callback fails - cannot renew
              throw const AblyException(
                message: 'Cannot obtain new token',
                errorInfo: ErrorInfo(
                  message: 'Cannot obtain new token',
                  code: 40171,
                  statusCode: 401,
                ),
              );
            }
          },
        ),
        httpClient: mockHttp,
      );

      // First authorize succeeds
      await client.auth.authorize();
      expect(client.auth.tokenDetails, isNotNull);
      expect(client.auth.tokenDetails!.token, equals('first-token'));

      // Make a request that fails with 40142
      // Renewal will be attempted but will fail
      try {
        await client.channels.get(channelName).status();
      } catch (_) {
        // Expected to fail
      }

      // After failed renewal, tokenDetails should be null
      // (the old token is invalid and we couldn't get a new one)
      expect(client.auth.tokenDetails, isNull);
    });
  });

  group('RSA16d - tokenDetails null after switch to basic auth', () {
    // UTS: rest/unit/RSA16d/null-after-switch-to-basic-3
    test('RSA16d - tokenDetails null after switch to basic auth', () async {
      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            return TokenDetails(
              token: 'test-token-rsa16d',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'test-client',
            );
          },
        ),
        httpClient: mockHttp,
      );

      // First authorize to get a token
      final token = await client.auth.authorize();
      expect(token, isNotNull);
      expect(client.auth.tokenDetails, isNotNull);
      expect(client.auth.method, equals(AuthMethod.token));

      // Now switch to basic auth
      final result = await client.auth.authorize(
        authOptions: const AuthOptions(
          key: 'appId.keyId:keySecret',
          useTokenAuth: false,
        ),
      );

      expect(result, isNull);
      expect(client.auth.tokenDetails, isNull);
      expect(client.auth.method, equals(AuthMethod.basic));
    });
  });

  group('RSA16 - Edge cases', () {
    // UTS: rest/unit/RSA16a/preserved-across-requests-0
    test('tokenDetails preserved across multiple successful requests',
        () async {
      var callbackCount = 0;
      final channelName = testChannelName('RSA16-stable');

      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async {
            callbackCount++;
            return TokenDetails(
              token: 'stable-token',
              expires: DateTime.now().millisecondsSinceEpoch + 3600000,
              clientId: 'stable-client',
            );
          },
        ),
        httpClient: mockHttp,
      );

      // Make multiple requests
      await client.channels.get(channelName).status();
      final firstCheck = client.auth.tokenDetails;

      await client.channels.get(channelName).status();
      final secondCheck = client.auth.tokenDetails;

      await client.channels.get(channelName).status();
      final thirdCheck = client.auth.tokenDetails;

      // Token should remain the same across requests (not re-fetched)
      expect(firstCheck!.token, equals('stable-token'));
      expect(secondCheck!.token, equals('stable-token'));
      expect(thirdCheck!.token, equals('stable-token'));

      // Callback should only be called once
      expect(callbackCount, equals(1));
    });

    // UTS: rest/unit/RSA16a/reflects-capability-1
    test('tokenDetails reflects capability from token', () async {
      final channelName = testChannelName('RSA16-capability');
      final client = RestClient.forTesting(
        options: ClientOptions(
          authCallback: (params) async => TokenDetails(
            token: 'capable-token',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
            capability: '{"channel1":["publish","subscribe"],'
                '"channel2":["subscribe"]}',
          ),
        ),
        httpClient: mockHttp,
      );

      await client.channels.get(channelName).status();

      expect(client.auth.tokenDetails, isNotNull);
      expect(
        client.auth.tokenDetails!.capability,
        equals('{"channel1":["publish","subscribe"],"channel2":["subscribe"]}'),
      );
    });
  });
}

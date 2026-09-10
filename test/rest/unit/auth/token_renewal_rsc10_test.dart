import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// RSC10 Token Error Retry Tests
///
/// Spec points: RSC10
///
/// Tests that the HTTP client transparently retries REST requests after
/// token renewal when a token error (40140–40149) is received.
///
/// Note: The RSA4b4 tests in token_renewal_test.dart verify the auth renewal
/// mechanism. These RSC10 tests verify the HTTP client's retry behaviour
/// wrapping that mechanism.
///
/// Spec: uts/test/rest/unit/auth/token_renewal.md (RSC10 section)
void main() {
  group('RSC10 - REST request retried after token renewal', () {
    // UTS: rest/unit/RSC10/request-retried-after-renewal-0.1
    test('channel.status() transparently retried after token renewal',
        () async {
      var callbackCount = 0;
      final capturedRequests = <CapturedRequest>[];
      final channelName = testChannelName('RSC10');

      Future<TokenDetails> authCallback(TokenParams params) async {
        callbackCount++;
        return TokenDetails(
          token: 'token-$callbackCount',
          expires: DateTime.now().millisecondsSinceEpoch + 3600000,
        );
      }

      final mockHttp = MockHttpClient(
        onRequest: (req) {
          capturedRequests.add(
            CapturedRequest(
              method: req.method,
              url: req.url,
              headers: req.headers,
              body: req.bodyAsString,
            ),
          );

          if (req.headers['Authorization'] == 'Bearer token-1') {
            // First token is rejected
            req.respondWith(401, {
              'error': {
                'code': 40142,
                'statusCode': 401,
                'message': 'Token expired',
              },
            });
          } else {
            // Renewed token succeeds — return channel status
            req.respondWith(200, {
              'channelId': channelName,
              'status': {
                'isActive': true,
                'occupancy': {
                  'metrics': {'connections': 0},
                },
              },
            });
          }
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(authCallback: authCallback),
        httpClient: mockHttp,
      );

      // Call channel.status() — the caller should not see the 401/renewal
      final result = await client.channels.get(channelName).status();

      // The call succeeded transparently
      expect(result, isA<ChannelDetails>());

      // Two HTTP requests were made (original + retry)
      final channelRequests = capturedRequests
          .where(
            (r) =>
                r.url.path == '/channels/${Uri.encodeComponent(channelName)}',
          )
          .toList();
      expect(channelRequests.length, equals(2));

      // Auth callback was called twice (initial token + renewal)
      expect(callbackCount, equals(2));

      // First request used first token, second used renewed token
      expect(
        channelRequests[0].headers['Authorization'],
        equals('Bearer token-1'),
      );
      expect(
        channelRequests[1].headers['Authorization'],
        equals('Bearer token-2'),
      );
    });
  });

  group('RSC10b - Non-token 401 errors are not retried', () {
    // UTS: rest/unit/RSC10b/non-token-401-no-renewal-0.1
    test('40100 error is not retried', () async {
      var callbackCount = 0;
      var requestCount = 0;
      final channelName = testChannelName('RSC10b');

      Future<TokenDetails> authCallback(TokenParams params) async {
        callbackCount++;
        return TokenDetails(
          token: 'token-$callbackCount',
          expires: DateTime.now().millisecondsSinceEpoch + 3600000,
        );
      }

      final mockHttp = MockHttpClient(
        onRequest: (req) {
          requestCount++;
          // Return a 401 with a non-token error code
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
        options: ClientOptions(authCallback: authCallback),
        httpClient: mockHttp,
      );

      try {
        await client.channels.get(channelName).status();
        fail('Expected error');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).code, equals(40100));
      }

      // Only one HTTP request — no retry
      expect(requestCount, equals(1));

      // Auth callback was called once (initial token only, no renewal)
      expect(callbackCount, equals(1));
    });
  });
}

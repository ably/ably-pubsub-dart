import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Unit tests for Auth#revokeTokens (RSA17).
///
/// These tests use mocked HTTP to verify request formation,
/// response parsing, and client-side validation.
///
/// Spec: uts/test/rest/unit/auth/revoke_tokens.md
void main() {
  group('RSA17g - revokeTokens sends POST to /keys/{keyName}/revokeTokens', () {
    // UTS: rest/unit/RSA17g/sends-post-correct-path-0
    test('sends POST request to correct path', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      expect(capturedRequests.length, equals(1));
      expect(capturedRequests[0].method, equals('POST'));
      expect(
        capturedRequests[0].url.path,
        equals('/keys/appId.keyName/revokeTokens'),
      );
    });
  });

  group('RSA17b - Target specifiers mapped to type:value strings', () {
    // UTS: rest/unit/RSA17b/single-specifier-targets-0
    test('single specifier sent as targets array', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody['targets'], equals(['clientId:alice']));
    });

    // UTS: rest/unit/RSA17b/multiple-specifier-types-1
    test('multiple specifiers with different types', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 3,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              },
              {
                'target': 'revocationKey:group-1',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              },
              {
                'target': 'channel:secret',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
        const TokenRevocationTargetSpecifier(
          type: 'revocationKey',
          value: 'group-1',
        ),
        const TokenRevocationTargetSpecifier(
          type: 'channel',
          value: 'secret',
        ),
      ]);

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(
        requestBody['targets'],
        equals([
          'clientId:alice',
          'revocationKey:group-1',
          'channel:secret',
        ]),
      );
    });
  });

  group('RSA17c, BAR2 - Returns BatchResult', () {
    // UTS: rest/unit/RSA17c/all-success-result-0
    test('all success result', () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(200, {
            'successCount': 2,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              },
              {
                'target': 'clientId:bob',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000002000,
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'bob',
        ),
      ]);

      expect(result.successCount, equals(2));
      expect(result.failureCount, equals(0));
      expect(result.results.length, equals(2));
    });

    // UTS: rest/unit/RSA17c/mixed-success-failure-1
    test('mixed success and failure result', () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(200, {
            'successCount': 1,
            'failureCount': 1,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              },
              {
                'target': 'invalidType:abc',
                'error': {
                  'code': 40000,
                  'statusCode': 400,
                  'message': 'Invalid target type',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
        const TokenRevocationTargetSpecifier(
          type: 'invalidType',
          value: 'abc',
        ),
      ]);

      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(1));
      expect(result.results.length, equals(2));
    });

    // UTS: rest/unit/RSA17c/all-failure-result-2
    test('all failure result', () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(200, {
            'successCount': 0,
            'failureCount': 2,
            'results': [
              {
                'target': 'invalidType:foo',
                'error': {
                  'code': 40000,
                  'statusCode': 400,
                  'message': 'Invalid target type',
                },
              },
              {
                'target': 'invalidType:bar',
                'error': {
                  'code': 40000,
                  'statusCode': 400,
                  'message': 'Invalid target type',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'invalidType',
          value: 'foo',
        ),
        const TokenRevocationTargetSpecifier(
          type: 'invalidType',
          value: 'bar',
        ),
      ]);

      expect(result.successCount, equals(0));
      expect(result.failureCount, equals(2));
      expect(result.results.length, equals(2));
    });
  });

  group('TRS2 - TokenRevocationSuccessResult attributes', () {
    // UTS: rest/unit/TRS2/success-result-attributes-0
    test('success result contains target, appliesAt, and issuedBefore',
        () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(200, {
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      final success = result.results[0];
      expect(success, isA<TokenRevocationSuccessResult>());
      final successResult = success as TokenRevocationSuccessResult;
      expect(successResult.target, equals('clientId:alice'));
      expect(successResult.issuedBefore, equals(1700000000000));
      expect(successResult.appliesAt, equals(1700000001000));
    });
  });

  group('TRF2 - TokenRevocationFailureResult attributes', () {
    // UTS: rest/unit/TRF2/failure-result-attributes-0
    test('failure result contains target and error', () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(200, {
            'successCount': 0,
            'failureCount': 1,
            'results': [
              {
                'target': 'invalidType:abc',
                'error': {
                  'code': 40000,
                  'statusCode': 400,
                  'message': 'Invalid target type',
                },
              },
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      final result = await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'invalidType',
          value: 'abc',
        ),
      ]);

      final failure = result.results[0];
      expect(failure, isA<TokenRevocationFailureResult>());
      final failureResult = failure as TokenRevocationFailureResult;
      expect(failureResult.target, equals('invalidType:abc'));
      expect(failureResult.error, isA<ErrorInfo>());
      expect(failureResult.error.code, equals(40000));
      expect(failureResult.error.statusCode, equals(400));
      expect(failureResult.error.message, contains('Invalid target type'));
    });
  });

  group('RSA17d - Token auth clients cannot revoke tokens', () {
    // UTS: rest/unit/RSA17d/token-auth-revoke-rejected-0
    test('token auth client fails with 40162', () async {
      final capturedRequests = <CapturedRequest>[];

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
          req.respondWith(200, <dynamic>[]);
        },
      );

      final client = RestClient.forTesting(
        options:
            ClientOptions(token: 'a.token.string', useBinaryProtocol: false),
        httpClient: mockHttp,
      );

      try {
        await client.auth.revokeTokens([
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ]);
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final error = (e as AblyException).errorInfo!;
        expect(error.code, equals(40162));
        expect(error.statusCode, equals(401));
      }

      // No HTTP request should have been made
      expect(capturedRequests.length, equals(0));
    });

    // UTS: rest/unit/RSA17d/use-token-auth-revoke-rejected-1
    test('token auth via useTokenAuth flag fails with 40162', () async {
      final capturedRequests = <CapturedRequest>[];

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
          req.respondWith(200, <dynamic>[]);
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyName:keySecret',
          useTokenAuth: true,
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      try {
        await client.auth.revokeTokens([
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ]);
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final error = (e as AblyException).errorInfo!;
        expect(error.code, equals(40162));
        expect(error.statusCode, equals(401));
      }

      expect(capturedRequests.length, equals(0));
    });
  });

  group('RSA17e - Optional issuedBefore parameter', () {
    // UTS: rest/unit/RSA17e/issued-before-included-0
    test('issuedBefore included in request body', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1699999000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens(
        [
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ],
        options: const RevokeTokensOptions(issuedBefore: 1699999000000),
      );

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody['issuedBefore'], equals(1699999000000));
    });

    // UTS: rest/unit/RSA17e/issued-before-omitted-1
    test('issuedBefore omitted when not provided', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody.containsKey('issuedBefore'), isFalse);
    });
  });

  group('RSA17f - Optional allowReauthMargin parameter', () {
    // UTS: rest/unit/RSA17f/reauth-margin-included-0
    test('allowReauthMargin included when true', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000030000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens(
        [
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ],
        options: const RevokeTokensOptions(allowReauthMargin: true),
      );

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody['allowReauthMargin'], isTrue);
    });

    // UTS: rest/unit/RSA17f/reauth-margin-omitted-1
    test('allowReauthMargin omitted when not provided', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody.containsKey('allowReauthMargin'), isFalse);
    });

    // UTS: rest/unit/RSA17f/both-options-together-2
    test('both issuedBefore and allowReauthMargin together', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1699999000000,
                'appliesAt': 1700000030000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens(
        [
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ],
        options: const RevokeTokensOptions(
          issuedBefore: 1699999000000,
          allowReauthMargin: true,
        ),
      );

      final requestBody =
          json.decode(capturedRequests[0].body!) as Map<String, dynamic>;
      expect(requestBody['targets'], equals(['clientId:alice']));
      expect(requestBody['issuedBefore'], equals(1699999000000));
      expect(requestBody['allowReauthMargin'], isTrue);
    });
  });

  group('Error handling', () {
    // UTS: rest/unit/RSA17/server-error-propagated-0
    test('server error is propagated as an exception', () async {
      final mockHttp = MockHttpClient(
        onConnectionAttempt: (conn) => conn.respondWithSuccess(),
        onRequest: (req) {
          req.respondWith(500, {
            'error': {
              'code': 50000,
              'statusCode': 500,
              'message': 'Internal error',
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      try {
        await client.auth.revokeTokens([
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'alice',
          ),
        ]);
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        final error = (e as AblyException).errorInfo!;
        expect(error.code, equals(50000));
        expect(error.statusCode, equals(500));
      }
    });
  });

  group('Request authentication', () {
    // UTS: rest/unit/RSA17/request-uses-basic-auth-0
    test('request uses Basic authentication', () async {
      final capturedRequests = <CapturedRequest>[];

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
            'successCount': 1,
            'failureCount': 0,
            'results': [
              {
                'target': 'clientId:alice',
                'issuedBefore': 1700000000000,
                'appliesAt': 1700000001000,
              }
            ],
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey(
          'appId.keyName:keySecret',
          useBinaryProtocol: false,
        ),
        httpClient: mockHttp,
      );

      await client.auth.revokeTokens([
        const TokenRevocationTargetSpecifier(
          type: 'clientId',
          value: 'alice',
        ),
      ]);

      expect(
        capturedRequests[0].headers['Authorization'],
        startsWith('Basic '),
      );
    });
  });
}

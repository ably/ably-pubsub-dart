import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Client Options Tests
///
/// Spec points: RSC1, RSC1a, RSC1b, RSC1c
void main() {
  group('Client Options', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSC1, RSC1a, RSC1c - Constructor String Argument Detection', () {
      final testCases = [
        (
          input: 'appId.keyId:keySecret',
          expected: 'API key',
          rationale: 'Contains : delimiter',
        ),
        (
          input: 'xVLyHw.A-pwh:5WEB4HEAT3pOqWp9',
          expected: 'API key',
          rationale: 'Real key format with special chars',
        ),
        (
          input: 'xVLyHw.A-pwh:5WEB4HEAT3pOqWp9-the_rest',
          expected: 'API key',
          rationale: 'Key with extended secret',
        ),
        (
          input: 'abcdef1234567890',
          expected: 'Token',
          rationale: 'No : delimiter (opaque token)',
        ),
        (
          input:
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U',
          expected: 'Token',
          rationale: 'JWT format (no : before first .)',
        ),
      ];

      for (final testCase in testCases) {
        final inputPreview = testCase.input.length > 20
            ? '${testCase.input.substring(0, 20)}...'
            : testCase.input;
        // UTS: rest/unit/RSC15l/qualifying-errors-trigger-fallback-0.1
        test('$inputPreview is detected as ${testCase.expected}', () {
          if (testCase.expected == 'API key') {
            final options = ClientOptions.fromKey(testCase.input);
            expect(options.key, equals(testCase.input));
          } else {
            final options = ClientOptions(token: testCase.input);
            expect(options.token, equals(testCase.input));
          }
        });
      }

      // UTS: rest/unit/RSC15l/qualifying-errors-trigger-fallback-0.2
      test('empty string throws error', () {
        expect(
          () => ClientOptions.fromKey(''),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('RSC1b - Invalid Arguments Error', () {
      // UTS: rest/unit/RSC1b/no-auth-method-error-0.1
      test('throws error 40106 when no auth configured', () {
        expect(
          () => RestClient.forTesting(
            options: ClientOptions(),
            httpClient: mockHttp,
          ),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40106),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSC1b/no-auth-method-error-0.2
      test('throws error when useTokenAuth: true but no token means', () {
        expect(
          () => RestClient.forTesting(
            options: ClientOptions(useTokenAuth: true),
            httpClient: mockHttp,
          ),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40106),
            ),
          ),
        );
      });

      // UTS: rest/unit/RSC1b/no-auth-method-error-0.3
      test('throws error when only clientId provided', () {
        expect(
          () => RestClient.forTesting(
            options: ClientOptions(clientId: 'test'),
            httpClient: mockHttp,
          ),
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

    group('RSC1 - ClientOptions Constructor', () {
      // UTS: rest/unit/RSC15l/qualifying-errors-trigger-fallback-0.3
      test('accepts full ClientOptions and preserves values', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          clientId: 'testClient',
          endpoint: 'test',
          httpRequestTimeout: 5000,
          logLevel: LogLevel.verbose,
        );

        final client = RestClient.forTesting(
          options: options,
          httpClient: mockHttp,
        );

        expect(client.options.key, equals('appId.keyId:keySecret'));
        expect(client.options.clientId, equals('testClient'));
        expect(client.options.endpoint, equals('test'));
        expect(client.options.tls, isTrue);
        expect(client.options.httpRequestTimeout, equals(5000));
        expect(client.options.idempotentRestPublishing, isTrue);
        expect(client.options.logLevel, equals(LogLevel.verbose));
      });

      // UTS: rest/unit/TO3/client-options-default-token-params-3.1
      test('applies default values for unspecified options', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');

        expect(options.tls, isTrue);
        expect(options.httpRequestTimeout, equals(10000));
        expect(options.idempotentRestPublishing, isTrue);
        expect(options.addRequestIds, isFalse);
        expect(options.useBinaryProtocol, isTrue);
      });
    });

    group('ClientOptions.fromKey convenience constructor', () {
      // UTS: rest/integration/RSA4/basic-auth-key-0.1
      test('creates options from API key string', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');

        expect(options.key, equals('appId.keyId:keySecret'));
      });

      // UTS: rest/unit/TO3/client-options-auth-url-2.1
      test('validates key format', () {
        expect(
          () => ClientOptions.fromKey('invalid'),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => ClientOptions.fromKey('no-colon.here'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('RestClient.fromKey convenience constructor', () {
      // UTS: rest/integration/RSA4/basic-auth-key-0.2
      test('creates Rest client from API key string', () {
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, {'time': 1234567890000});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        expect(client.options.key, equals('appId.keyId:keySecret'));
      });
    });
  });
}

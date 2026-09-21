import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// Options Types Tests
///
/// Spec points: TO1, TO2, TO3, AO1, AO2
void main() {
  group('ClientOptions', () {
    group('TO3 - ClientOptions attributes with defaults', () {
      // UTS: rest/unit/TO3/client-options-attributes-0
      test('has correct default values', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');

        expect(options.authMethod, equals('GET'));
        expect(options.tls, isTrue);
        expect(options.httpRequestTimeout, equals(10000));
        expect(options.httpMaxRetryCount, equals(3));
        expect(options.useBinaryProtocol, isTrue);
        expect(options.idempotentRestPublishing, isTrue);
        expect(options.addRequestIds, isFalse);
        expect(options.queryTime, isFalse);
        expect(options.maxMessageSize, equals(65536));
      });

      // UTS: rest/unit/TO3/client-options-attributes-0.1
      test('accepts custom values', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          clientId: 'my-client',
          endpoint: 'test',
          tls: false,
          httpRequestTimeout: 30000,
          useBinaryProtocol: false,
          idempotentRestPublishing: false,
          addRequestIds: true,
        );

        expect(options.key, equals('appId.keyId:keySecret'));
        expect(options.clientId, equals('my-client'));
        expect(options.endpoint, equals('test'));
        expect(options.tls, isFalse);
        expect(options.httpRequestTimeout, equals(30000));
        expect(options.useBinaryProtocol, isFalse);
        expect(options.idempotentRestPublishing, isFalse);
        expect(options.addRequestIds, isTrue);
      });
    });

    group('TO3 - ClientOptions with custom hosts', () {
      // UTS: rest/unit/TO3/client-options-custom-hosts-1
      test('accepts custom host configuration', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'custom.ably.example.com',
          fallbackHosts: ['fallback1.example.com', 'fallback2.example.com'],
          useBinaryProtocol: false,
        );

        expect(options.endpoint, equals('custom.ably.example.com'));
        expect(
          options.fallbackHosts,
          equals(['fallback1.example.com', 'fallback2.example.com']),
        );
      });
    });

    group('TO3 - ClientOptions with auth URL', () {
      // UTS: rest/unit/TO3/client-options-auth-url-2
      test('accepts auth URL configuration', () {
        final options = ClientOptions(
          authUrl: 'https://auth.example.com/token',
          authMethod: 'POST',
          authHeaders: {'X-API-Key': 'secret'},
          authParams: {'scope': 'full'},
          useBinaryProtocol: false,
        );

        expect(options.authUrl, equals('https://auth.example.com/token'));
        expect(options.authMethod, equals('POST'));
        expect(options.authHeaders?['X-API-Key'], equals('secret'));
        expect(options.authParams?['scope'], equals('full'));
      });
    });

    group('TO3 - ClientOptions with defaultTokenParams', () {
      // UTS: rest/unit/TO3/client-options-default-token-params-3
      test('accepts default token parameters', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          useBinaryProtocol: false,
          defaultTokenParams: const TokenParams(
            ttl: 7200000,
            clientId: 'default-client',
            capability: '{"*":["subscribe"]}',
          ),
        );

        expect(options.defaultTokenParams?.ttl, equals(7200000));
        expect(options.defaultTokenParams?.clientId, equals('default-client'));
        expect(
          options.defaultTokenParams?.capability,
          equals('{"*":["subscribe"]}'),
        );
      });
    });

    group('TO - Conflicting options validation', () {
      // UTS: rest/unit/TO/conflicting-options-validation-1
      test('throws when no auth options provided', () {
        expect(
          () => RestClient(options: ClientOptions(useBinaryProtocol: false)),
          throwsA(isA<AblyException>()),
        );
      });
    });
  });

  group('AuthOptions', () {
    group('AO2 - AuthOptions attributes', () {
      // UTS: rest/unit/AO2/auth-options-attributes-0
      test('has all required attributes', () {
        const authOptions = AuthOptions(
          authUrl: 'https://auth.example.com/token',
          authMethod: 'POST',
          authHeaders: {'Authorization': 'Bearer api-key'},
          authParams: {'user': 'test'},
          queryTime: true,
        );

        expect(authOptions.authUrl, equals('https://auth.example.com/token'));
        expect(authOptions.authMethod, equals('POST'));
        expect(
          authOptions.authHeaders?['Authorization'],
          equals('Bearer api-key'),
        );
        expect(authOptions.authParams?['user'], equals('test'));
        expect(authOptions.queryTime, isTrue);
      });
    });

    group('AO - AuthOptions with authCallback', () {
      // UTS: rest/unit/AO/auth-options-with-callback-0
      test('can hold and invoke authCallback function', () async {
        var callbackCalled = false;

        Future<Object> testCallback(TokenParams params) async {
          callbackCalled = true;
          return TokenDetails(
            token: 'callback-token',
            expires: DateTime.now().millisecondsSinceEpoch + 3600000,
          );
        }

        final authOptions = AuthOptions(authCallback: testCallback);

        // Verify callback is stored and callable
        final result = await authOptions.authCallback!(const TokenParams());
        expect(callbackCalled, isTrue);
        expect((result as TokenDetails).token, equals('callback-token'));
      });
    });
  });
}

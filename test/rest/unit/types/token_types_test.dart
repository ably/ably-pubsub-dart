import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

/// Token Types Tests
///
/// Spec points: TD1, TD2, TD3, TD4, TD5, TK1, TK2, TK3, TK4, TK5, TK6,
///              TE1, TE2, TE3, TE4, TE5, TE6
void main() {
  group('TokenDetails', () {
    group('TD1-TD5 - TokenDetails structure', () {
      // UTS: rest/unit/TD1/token-details-attributes-0
      test('TD1 - token attribute', () {
        const tokenDetails = TokenDetails(
          token: 'test-token',
          expires: 1234567890000,
        );
        expect(tokenDetails.token, equals('test-token'));
      });

      // UTS: rest/unit/TD1/token-details-attributes-0.1
      test('TD2 - expires attribute (milliseconds since epoch)', () {
        const tokenDetails = TokenDetails(
          token: 'test-token',
          expires: 1234567890000,
        );
        expect(tokenDetails.expires, equals(1234567890000));
      });

      // UTS: rest/unit/TD1/token-details-attributes-0.2
      test('TD3 - issued attribute', () {
        const tokenWithIssued = TokenDetails(
          token: 'test-token',
          expires: 1234567890000,
          issued: 1234567800000,
        );
        expect(tokenWithIssued.issued, equals(1234567800000));
      });

      // UTS: rest/unit/TD1/token-details-attributes-0.3
      test('TD4 - capability attribute (JSON string)', () {
        const tokenWithCapability = TokenDetails(
          token: 'test-token',
          expires: 1234567890000,
          capability: '{"*":["*"]}',
        );
        expect(tokenWithCapability.capability, equals('{"*":["*"]}'));
      });

      // UTS: rest/unit/TD1/token-details-attributes-0.4
      test('TD5 - clientId attribute', () {
        const tokenWithClient = TokenDetails(
          token: 'test-token',
          expires: 1234567890000,
          clientId: 'my-client',
        );
        expect(tokenWithClient.clientId, equals('my-client'));
      });
    });

    group('TD - TokenDetails from JSON', () {
      // UTS: rest/unit/TD/token-details-from-json-0
      test('deserializes from JSON response', () {
        final jsonData = {
          'token': 'deserialized-token',
          'expires': 1234567890000,
          'issued': 1234567800000,
          'capability': '{"channel-1":["publish"]}',
          'clientId': 'json-client',
          'keyName': 'appId.keyId',
        };

        final tokenDetails = TokenDetails.fromJson(jsonData);

        expect(tokenDetails.token, equals('deserialized-token'));
        expect(tokenDetails.expires, equals(1234567890000));
        expect(tokenDetails.issued, equals(1234567800000));
        expect(tokenDetails.capability, equals('{"channel-1":["publish"]}'));
        expect(tokenDetails.clientId, equals('json-client'));
      });
    });
  });

  group('TokenParams', () {
    group('TK1-TK6 - TokenParams structure', () {
      // UTS: rest/unit/TK1/token-params-attributes-0
      test('TK1 - ttl attribute (milliseconds)', () {
        const params = TokenParams(ttl: 3600000);
        expect(params.ttl, equals(3600000));
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.1
      test('TK1 - ttl defaults to null when not specified', () {
        // RSA5 depends on this — null means "let server decide"
        const params = TokenParams();
        expect(params.ttl, isNull);
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.2
      test('TK2 - capability attribute', () {
        const params = TokenParams(capability: '{"*":["subscribe"]}');
        expect(params.capability, equals('{"*":["subscribe"]}'));
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.3
      test('TK2 - capability defaults to null when not specified', () {
        // RSA6 depends on this — null means "use key capabilities"
        const params = TokenParams();
        expect(params.capability, isNull);
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.4
      test('TK3 - clientId attribute', () {
        const params = TokenParams(clientId: 'param-client');
        expect(params.clientId, equals('param-client'));
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.5
      test('TK4 - timestamp attribute (milliseconds since epoch)', () {
        const params = TokenParams(timestamp: 1234567890000);
        expect(params.timestamp, equals(1234567890000));
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.6
      test('TK5 - nonce attribute', () {
        const params = TokenParams(nonce: 'unique-nonce-value');
        expect(params.nonce, equals('unique-nonce-value'));
      });

      // UTS: rest/unit/TK1/token-params-attributes-0.7
      test('TK6 - All attributes together', () {
        const params = TokenParams(
          ttl: 7200000,
          capability: '{"*":["*"]}',
          clientId: 'full-client',
          timestamp: 1234567890000,
          nonce: 'full-nonce',
        );

        expect(params.ttl, equals(7200000));
        expect(params.capability, equals('{"*":["*"]}'));
        expect(params.clientId, equals('full-client'));
        expect(params.timestamp, equals(1234567890000));
        expect(params.nonce, equals('full-nonce'));
      });
    });

    group('TK - TokenParams to query string', () {
      // UTS: rest/unit/TK/token-params-to-query-string-0
      test('converts to query parameters', () {
        const params = TokenParams(
          ttl: 3600000,
          clientId: 'query-client',
          capability: '{"ch":["pub"]}',
        );

        final queryMap = params.toQueryParams();

        expect(queryMap['ttl'], equals('3600000'));
        expect(queryMap['clientId'], equals('query-client'));
        expect(queryMap['capability'], equals('{"ch":["pub"]}'));
      });
    });
  });

  group('TokenRequest', () {
    group('TE1-TE6 - TokenRequest structure', () {
      // UTS: rest/unit/TE1/token-request-attributes-0
      test('TE1 - keyName attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'nonce-1',
        );
        expect(request.keyName, equals('appId.keyId'));
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.1
      test('TE2 - ttl attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          ttl: 3600000,
          timestamp: 1234567890000,
          nonce: 'nonce-2',
        );
        expect(request.ttl, equals(3600000));
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.2
      test('TE2 - ttl defaults to null when not specified', () {
        // RSA5 depends on this — createTokenRequest must be able to omit ttl
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'nonce-2b',
        );
        expect(request.ttl, isNull);
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.3
      test('TE3 - capability attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          capability: '{"*":["*"]}',
          timestamp: 1234567890000,
          nonce: 'nonce-3',
        );
        expect(request.capability, equals('{"*":["*"]}'));
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.4
      test('TE3 - capability defaults to null when not specified', () {
        // RSA6 depends on this — createTokenRequest must be able to omit capability
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'nonce-3b',
        );
        expect(request.capability, isNull);
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.5
      test('TE4 - clientId attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          clientId: 'request-client',
          timestamp: 1234567890000,
          nonce: 'nonce-4',
        );
        expect(request.clientId, equals('request-client'));
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.6
      test('TE5 - timestamp attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'nonce-5',
        );
        expect(request.timestamp, equals(1234567890000));
      });

      // UTS: rest/unit/TE1/token-request-attributes-0.7
      test('TE6 - nonce attribute', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'unique-nonce',
        );
        expect(request.nonce, equals('unique-nonce'));
      });
    });

    group('TE - TokenRequest with mac (signature)', () {
      // UTS: rest/unit/TE/token-request-mac-signature-0
      test('includes mac signature', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          timestamp: 1234567890000,
          nonce: 'nonce-value',
          mac: 'signature-base64',
        );

        expect(request.mac, equals('signature-base64'));
      });
    });

    group('TE - TokenRequest to JSON', () {
      // UTS: rest/unit/TE/token-request-to-json-1
      test('serializes correctly for transmission', () {
        const request = TokenRequest(
          keyName: 'appId.keyId',
          ttl: 3600000,
          capability: '{"*":["*"]}',
          clientId: 'json-client',
          timestamp: 1234567890000,
          nonce: 'json-nonce',
          mac: 'json-mac',
        );

        final jsonData = request.toJson();

        expect(jsonData['keyName'], equals('appId.keyId'));
        expect(jsonData['ttl'], equals(3600000));
        expect(jsonData['capability'], equals('{"*":["*"]}'));
        expect(jsonData['clientId'], equals('json-client'));
        expect(jsonData['timestamp'], equals(1234567890000));
        expect(jsonData['nonce'], equals('json-nonce'));
        expect(jsonData['mac'], equals('json-mac'));
      });
    });

    group('TE - TokenRequest from JSON', () {
      // UTS: rest/unit/TE/token-request-from-json-2
      test('deserializes from JSON', () {
        final jsonData = {
          'keyName': 'appId.keyId',
          'ttl': 7200000,
          'capability': '{"ch":["sub"]}',
          'clientId': 'from-json-client',
          'timestamp': 1234567899999,
          'nonce': 'from-json-nonce',
          'mac': 'from-json-mac',
        };

        final request = TokenRequest.fromJson(jsonData);

        expect(request.keyName, equals('appId.keyId'));
        expect(request.ttl, equals(7200000));
        expect(request.capability, equals('{"ch":["sub"]}'));
        expect(request.clientId, equals('from-json-client'));
        expect(request.timestamp, equals(1234567899999));
        expect(request.nonce, equals('from-json-nonce'));
        expect(request.mac, equals('from-json-mac'));
      });
    });
  });
}

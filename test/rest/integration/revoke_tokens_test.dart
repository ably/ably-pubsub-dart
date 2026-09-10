@Tags(['integration'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/jwt_helper.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/wait_for_state.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  // Helper: build a key-authenticated REST client (key[4] has revocableTokens).
  RestClient buildRevocableKeyClient() => RestClient(
        options: ClientOptions(
          key: testApp.keys[4].keyStr,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );

  // ---------------------------------------------------------------------------
  // RSA17g+RSA17b+RSA17c+TRS2 — Issue token, connect Realtime, revoke, verify disconnect
  // ---------------------------------------------------------------------------
  group('RSA17g+RSA17b+RSA17c+TRS2 - revokeTokens and Realtime disconnect', () {
    test(
        'RSA17g+RSA17b+RSA17c+TRS2 - issue revocable token for clientId, connect Realtime, '
        'revoke via REST, verify successCount==1, target, issuedBefore, appliesAt, '
        'and Realtime disconnects with code 40141', () async {
      final clientId = 'rsa17-client-${DateTime.now().millisecondsSinceEpoch}';

      // Build REST client with key[4] (revocableTokens)
      final restClient = buildRevocableKeyClient();
      addTearDown(restClient.close);

      // RSA17g: Issue a token for the clientId
      final token = await restClient.auth.requestToken(
        tokenParams: TokenParams(clientId: clientId),
      );
      expect(token.token, isNotNull);

      // Connect a Realtime client with the token
      final realtimeClient = RealtimeClient(
        options: ClientOptions(
          token: token.token,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
          // Disable auto-reconnect after token revocation
          disconnectedRetryTimeout: 60000,
        ),
      );
      addTearDown(realtimeClient.close);

      // Wait for the Realtime connection to be established
      realtimeClient.connect();
      await waitForConnectionState(
        realtimeClient.connection,
        ConnectionState.connected,
      );

      // Set up listener for disconnected/failed state change before revoking
      final disconnectedCompleter = Completer<ConnectionStateChange>();
      final subscription = realtimeClient.connection.on().listen((change) {
        if (!disconnectedCompleter.isCompleted &&
            (change.current == ConnectionState.disconnected ||
                change.current == ConnectionState.failed)) {
          disconnectedCompleter.complete(change);
        }
      });
      addTearDown(subscription.cancel);

      // RSA17b: Revoke tokens for the clientId
      final response = await restClient.auth.revokeTokens([
        TokenRevocationTargetSpecifier(type: 'clientId', value: clientId),
      ]);

      // RSA17c: Verify successCount and result fields
      expect(response.successCount, equals(1));
      expect(response.failureCount, equals(0));
      expect(response.results, hasLength(1));

      final result = response.results.first;
      expect(result, isA<TokenRevocationSuccessResult>());

      final successResult = result as TokenRevocationSuccessResult;

      // RSA17b: Target string should be "clientId:<clientId>"
      expect(successResult.target, equals('clientId:$clientId'));

      // TRS2: issuedBefore and appliesAt must be present
      expect(successResult.issuedBefore, isNotNull);
      expect(successResult.appliesAt, isNotNull);

      // Wait for Realtime to disconnect due to token revocation (code 40141)
      final stateChange = await disconnectedCompleter.future
          .timeout(const Duration(seconds: 30));

      // RSA17g: The connection should be disconnected/failed with a token
      // revocation code (40141 in v2, 40171 in v5)
      expect(stateChange.reason, isNotNull);
      expect(
        stateChange.reason!.code,
        anyOf(equals(40141), equals(40171)),
        reason: 'Expected error code 40141 or 40171 (token revoked), '
            'got ${stateChange.reason?.code}',
      );

      // Close before test exits to prevent async SocketException from
      // the internal reconnection attempt leaking into the test zone.
      await subscription.cancel();
      await realtimeClient.close();
    });
  });

  // ---------------------------------------------------------------------------
  // RSA17d — Token auth client rejected (not key auth)
  // ---------------------------------------------------------------------------
  group('RSA17d - Token auth client cannot revoke tokens', () {
    // UTS: rest/integration/RSA17d/token-auth-revoke-rejected-0
    test(
        'RSA17d - REST client using JWT token calling revokeTokens throws 40162',
        () async {
      final jwt = JwtHelper.generateToken(
        apiKey: testApp.keys[4].keyStr,
      );

      final tokenClient = RestClient(
        options: ClientOptions(
          token: jwt,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
        ),
      );
      addTearDown(tokenClient.close);

      try {
        await tokenClient.auth.revokeTokens([
          const TokenRevocationTargetSpecifier(
            type: 'clientId',
            value: 'some-client',
          ),
        ]);
        fail('Expected AblyException to be thrown for token auth client');
      } on AblyException catch (e) {
        expect(
          e.code,
          equals(40162),
          reason:
              'Expected error code 40162 (token auth cannot revoke), got ${e.code}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // RSA17e+RSA17f — issuedBefore + allowReauthMargin
  // ---------------------------------------------------------------------------
  group('RSA17e+RSA17f - issuedBefore and allowReauthMargin', () {
    test(
        'RSA17e+RSA17f - revoke with issuedBefore and allowReauthMargin:true, '
        'verify appliesAt > serverTime + 30s', () async {
      final restClient = buildRevocableKeyClient();
      addTearDown(restClient.close);

      final clientId =
          'rsa17ef-client-${DateTime.now().millisecondsSinceEpoch}';

      // RSA17e: Set issuedBefore to current server time
      final serverTime = await restClient.time();
      final issuedBefore = serverTime.millisecondsSinceEpoch;

      // RSA17f: allowReauthMargin=true should delay revocation by ~30s
      final response = await restClient.auth.revokeTokens(
        [
          TokenRevocationTargetSpecifier(type: 'clientId', value: clientId),
        ],
        options: RevokeTokensOptions(
          issuedBefore: issuedBefore,
          allowReauthMargin: true,
        ),
      );

      expect(response.results, isNotEmpty);
      final result = response.results.first;
      expect(result, isA<TokenRevocationSuccessResult>());

      final successResult = result as TokenRevocationSuccessResult;

      // RSA17e: The issuedBefore in the response should match or be close to
      // the one we sent
      expect(successResult.issuedBefore, isNotNull);

      // RSA17f: appliesAt should be at least 30 seconds after server time
      // because allowReauthMargin adds ~30s delay
      final appliesAt = successResult.appliesAt;
      expect(appliesAt, isNotNull);
      expect(
        appliesAt,
        greaterThan(issuedBefore + 30000),
        reason:
            'Expected appliesAt to be > serverTime + 30s when allowReauthMargin=true',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RSA17c+TRF2 — Mixed success/failure results
  // ---------------------------------------------------------------------------
  group('RSA17c+TRF2 - Mixed success/failure results', () {
    test(
        'RSA17c+TRF2 - revoke with valid clientId + invalid type, '
        'verify successCount==1, failureCount==1, failure has error statusCode 400',
        () async {
      final restClient = buildRevocableKeyClient();
      addTearDown(restClient.close);

      final clientId = 'rsa17c-mixed-${DateTime.now().millisecondsSinceEpoch}';

      final response = await restClient.auth.revokeTokens([
        // Valid target
        TokenRevocationTargetSpecifier(type: 'clientId', value: clientId),
        // Invalid target type — should produce a failure result (TRF2)
        const TokenRevocationTargetSpecifier(
          type: 'invalidType',
          value: 'abc',
        ),
      ]);

      expect(response.successCount, equals(1));
      expect(response.failureCount, equals(1));
      expect(response.results, hasLength(2));

      // Find the failure result
      final failures =
          response.results.whereType<TokenRevocationFailureResult>().toList();
      expect(failures, hasLength(1));

      // TRF2: Failure result should have an error with statusCode 400
      final failure = failures.first;
      expect(failure.error, isNotNull);
      expect(
        failure.error.statusCode,
        equals(400),
        reason:
            'Expected failure error statusCode 400, got ${failure.error.statusCode}',
      );
    });
  });
}

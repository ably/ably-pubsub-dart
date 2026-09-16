@Tags(['integration'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

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

  group('Realtime Auth Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTC8a - In-band reauthorization on CONNECTED client
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RTC8a/in-band-reauth-connected-0
    test('RTC8a - In-band reauthorization on CONNECTED client', () async {
      final apiKey = testApp.keys[0].keyStr;

      final client = PubSubClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED state
      client.connect();
      await waitForConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Record the connection ID
      final connectionId = client.connection.id;
      expect(connectionId, isNotNull);

      // Collect state changes during reauthorization
      final stateChanges = <ConnectionStateChange>[];
      final subscription = client.connection.on().listen(stateChanges.add);

      // Perform in-band reauthorization
      final token = await client.auth.authorize();

      // Allow a brief period for any state changes to propagate
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await subscription.cancel();

      // Assert: token returned is non-null
      expect(token, isNotNull);

      // Assert: connection ID unchanged (no disconnect)
      expect(client.connection.id, equals(connectionId));

      // Assert: no state transitions where current != previous
      // (i.e., the connection stayed connected throughout)
      final disruptiveChanges =
          stateChanges.where((sc) => sc.current != sc.previous).toList();
      expect(
        disruptiveChanges,
        isEmpty,
        reason: 'Expected no disruptive state transitions during '
            'reauthorization, but got: $disruptiveChanges',
      );
    });

    // -------------------------------------------------------------------------
    // RTC8c - authorize() from INITIALIZED initiates connection
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RTC8c/authorize-initiates-connection-0
    test('RTC8c - authorize() from INITIALIZED initiates connection', () async {
      final apiKey = testApp.keys[0].keyStr;

      final client = PubSubClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await client.close());

      // Assert: starts in INITIALIZED
      expect(client.connection.state, equals(ConnectionState.initialized));

      // Call authorize() which should initiate a connection
      final token = await client.auth.authorize();

      // Await CONNECTED state
      await waitForConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Assert: token non-null
      expect(token, isNotNull);

      // Assert: state == connected
      expect(client.connection.state, equals(ConnectionState.connected));

      // Assert: connection.id non-null
      expect(client.connection.id, isNotNull);
    });

    // -------------------------------------------------------------------------
    // RSA8 - Token auth via authCallback on realtime
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RSA8/token-auth-connect-0
    test('RSA8 - Token auth via authCallback on realtime', () async {
      final apiKey = testApp.keys[0].keyStr;

      final client = PubSubClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      client.connect();
      await waitForConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      expect(client.connection.id, isNotNull);
      expect(client.connection.errorReason, isNull);
    });

    // -------------------------------------------------------------------------
    // RSA7 - matching clientId succeeds
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RSA7/matching-clientid-succeeds-0
    test('RSA7 - matching clientId succeeds', () async {
      final apiKey = testApp.keys[0].keyStr;
      final testClientId =
          'test-client-${DateTime.now().millisecondsSinceEpoch}';

      final client = PubSubClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(
              apiKey: apiKey,
              clientId: testClientId,
            );
          },
          clientId: testClientId,
          endpoint: 'nonprod:sandbox',
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await client.close());

      // Connect and await CONNECTED
      client.connect();
      await waitForConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Assert: auth.clientId matches
      expect(client.auth.clientId, equals(testClientId));
    });
  });
}

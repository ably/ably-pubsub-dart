@Tags(['integration', 'proxy'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/jwt_helper.dart';
import '../../../helpers/poll_until.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    await ensureProxy();
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
    stopProxy();
  });

  group('Auth Re-authentication Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTN22/RTC8a - Server-initiated AUTH triggers re-authentication
    // -------------------------------------------------------------------------
    test(
      'RTN22/RTC8a - Server-initiated AUTH triggers re-authentication',
      () async {
        final apiKey = testApp.keys[0].keyStr;
        var authCallbackCount = 0;

        // Create session with no rules (passthrough)
        final session = await ProxySession.create();
        addTearDown(() async => await session.close());

        final client = RealtimeClient(
          options: ClientOptions(
            authCallback: (params) async {
              authCallbackCount++;
              return JwtHelper.generateToken(apiKey: apiKey);
            },
            endpoint: 'localhost',
            port: session.proxyPort,
            tls: false,
            useBinaryProtocol: false,
            autoConnect: false,
          ),
        );
        addTearDown(() async => await client.close());

        // Connect and await CONNECTED
        await client.connect();
        expect(client.connection.state, equals(ConnectionState.connected));

        // Record connection ID and initial callback count
        final connectionId = client.connection.id;
        expect(connectionId, isNotNull);
        final initialCallbackCount = authCallbackCount;

        // Start recording state changes
        final stateChanges = <ConnectionStateChange>[];
        final subscription = client.connection.on().listen(stateChanges.add);
        addTearDown(() async => await subscription.cancel());

        // Inject AUTH message (action 17) from server to client
        await session.triggerAction({
          'type': 'inject_to_client',
          'message': {
            'action': 17, // AUTH
          },
        });

        // Poll until auth callback count increases
        await pollUntil(
          () async {
            if (authCallbackCount > initialCallbackCount) {
              return true;
            }
            return null;
          },
        );

        // Allow time for state changes to settle
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Assert: callback count increased by at least 1
        expect(
          authCallbackCount,
          greaterThan(initialCallbackCount),
          reason: 'Auth callback should have been invoked after AUTH injection',
        );

        // Assert: connection ID unchanged (no disconnect/reconnect)
        expect(
          client.connection.id,
          equals(connectionId),
          reason: 'Connection ID should remain the same after re-auth',
        );

        // Assert: still connected
        expect(client.connection.state, equals(ConnectionState.connected));

        // Assert: no non-connected state transitions
        final disruptiveChanges = stateChanges
            .where(
              (sc) =>
                  sc.current != ConnectionState.connected &&
                  sc.event != ConnectionEvent.update,
            )
            .toList();
        expect(
          disruptiveChanges,
          isEmpty,
          reason: 'Expected no disruptive state transitions during re-auth, '
              'but got: $disruptiveChanges',
        );

        // Check proxy log for AUTH frame (action 17) from client to server
        final log = await session.getLog();
        final authFramesFromClient = log.where((event) {
          if (event['type'] != 'ws_frame') return false;
          if (event['direction'] != 'client_to_server') return false;
          final message = event['message'] as Map<String, dynamic>? ?? {};
          return message['action'] == 17;
        }).toList();
        expect(
          authFramesFromClient,
          isNotEmpty,
          reason:
              'Proxy log should contain an AUTH frame from client to server',
        );
      },
    );
  });
}

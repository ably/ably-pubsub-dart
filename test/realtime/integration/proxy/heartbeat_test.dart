@Tags(['integration', 'proxy'])
library;

import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/jwt_helper.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

Future<Object> Function(TokenParams params) makeAuthCallback(String apiKey) {
  return (params) async => JwtHelper.generateToken(apiKey: apiKey);
}

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

  group('Heartbeat Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTN23a - Transport failure causes disconnect and reconnect
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN23a/heartbeat-starvation-reconnect-0
    test('RTN23a - Transport failure causes disconnect and reconnect',
        () async {
      final session = await ProxySession.create(
        rules: [
          {
            'match': {'type': 'delay_after_ws_connect', 'delayMs': 2000},
            'action': {'type': 'close'},
            'times': 1,
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;
      final stateChanges = <ConnectionStateChange>[];

      final client = RealtimeClient(
        options: ClientOptions(
          authCallback: makeAuthCallback(apiKey),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(client.close);

      client.connection.on().listen(stateChanges.add);

      // connect() internally awaits CONNECTED, so it returns in
      // connected state — no need for a separate event listener.
      await client.connect();

      final originalId = client.connection.id;
      expect(originalId, isNotNull);

      // Wait for DISCONNECTED (proxy closes after 2s)
      await client.connection
          .on(ConnectionEvent.disconnected)
          .first
          .timeout(const Duration(seconds: 10));

      // Wait for reconnect CONNECTED
      await client.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 15));

      // Assert state changes contain the expected sequence:
      // connecting -> connected -> disconnected -> connecting -> connected
      final states = stateChanges.map((e) => e.current).toList();

      // Verify key transitions exist in order
      final firstConnecting = states.indexOf(ConnectionState.connecting);
      final firstConnected = states.indexOf(ConnectionState.connected);
      final disconnected = states.indexOf(ConnectionState.disconnected);
      final secondConnecting =
          states.indexOf(ConnectionState.connecting, disconnected + 1);
      final secondConnected =
          states.indexOf(ConnectionState.connected, disconnected + 1);

      expect(
        firstConnecting,
        greaterThanOrEqualTo(0),
        reason: 'Should have initial CONNECTING',
      );
      expect(
        firstConnected,
        greaterThan(firstConnecting),
        reason: 'Should have initial CONNECTED after CONNECTING',
      );
      expect(
        disconnected,
        greaterThan(firstConnected),
        reason: 'Should have DISCONNECTED after CONNECTED',
      );
      expect(
        secondConnecting,
        greaterThan(disconnected),
        reason: 'Should have second CONNECTING after DISCONNECTED',
      );
      expect(
        secondConnected,
        greaterThan(secondConnecting),
        reason: 'Should have second CONNECTED after second CONNECTING',
      );

      // Verify proxy log shows >= 2 ws_connect and second has resume param
      final log = await session.getLog();
      final wsConnects = log.where((e) => e['type'] == 'ws_connect').toList();
      expect(
        wsConnects.length,
        greaterThanOrEqualTo(2),
        reason: 'Should have at least 2 WebSocket connections',
      );

      final secondUrl = wsConnects[1]['url'] as String? ?? '';
      expect(
        secondUrl,
        contains('resume='),
        reason: 'Second connection should include resume parameter',
      );
    });
  });
}

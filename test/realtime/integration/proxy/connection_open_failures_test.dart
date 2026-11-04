@Tags(['integration', 'proxy'])
library;

import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/jwt_helper.dart';
import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

Future<Object> Function(TokenParams params) makeAuthCallback(
  String apiKey, {
  void Function()? onCalled,
}) {
  return (params) async {
    onCalled?.call();
    return JwtHelper.generateToken(apiKey: apiKey);
  };
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

  group('Connection Open Failures Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RTN14a - Fatal error during connection -> FAILED
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN14a/fatal-connect-error-0
    test('RTN14a - Fatal error during connection -> FAILED', () async {
      final session = await ProxySession.create(
        rules: [
          // Replace first CONNECTED with ERROR action=9, code=40005
          {
            'match': {
              'type': 'ws_frame_to_client',
              'action': 'CONNECTED',
            },
            'action': {
              'type': 'replace',
              'message': {
                'action': 9, // ERROR
                'error': {
                  'message': 'Application not found',
                  'code': 40005,
                  'statusCode': 404,
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;

      final client = createClient(
        ClientOptions(
          authCallback: makeAuthCallback(apiKey),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(client.close);

      // Register listener before connect — connect() may complete with
      // FAILED before returning, so a post-connect listener misses it.
      final failedFuture = client.connection
          .on(ConnectionEvent.failed)
          .first
          .timeout(const Duration(seconds: 10));

      unawaited(client.connect());

      await failedFuture;

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(40005));
    });

    // -------------------------------------------------------------------------
    // RTN14b - Token error triggers renewal and reconnect
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN14b/token-error-renew-reconnect-0
    test('RTN14b - Token error triggers renewal and reconnect', () async {
      final session = await ProxySession.create(
        rules: [
          // Replace first CONNECTED with ERROR action=9, code=40142
          {
            'match': {
              'type': 'ws_frame_to_client',
              'action': 'CONNECTED',
            },
            'action': {
              'type': 'replace',
              'message': {
                'action': 9, // ERROR
                'error': {
                  'message': 'Token expired',
                  'code': 40142,
                  'statusCode': 401,
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;
      var authCallbackCount = 0;

      final client = createClient(
        ClientOptions(
          authCallback: makeAuthCallback(
            apiKey,
            onCalled: () => authCallbackCount++,
          ),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(client.close);

      await client.connect();

      // Should eventually reach CONNECTED after token renewal
      await client.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 15));

      expect(client.connection.state, equals(ConnectionState.connected));
      expect(
        authCallbackCount,
        greaterThanOrEqualTo(2),
        reason: 'authCallback should be called at least twice '
            '(initial + renewal)',
      );
    });

    // -------------------------------------------------------------------------
    // RTN14d - Connection refused -> DISCONNECTED -> retry -> CONNECTED
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN14d/retry-after-refused-0
    test('RTN14d - Connection refused -> DISCONNECTED -> retry -> CONNECTED',
        () async {
      final session = await ProxySession.create(
        rules: [
          // Refuse first ws_connect
          {
            'match': {'type': 'ws_connect'},
            'action': {'type': 'refuse_connection'},
            'times': 1,
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;
      final stateChanges = <ConnectionStateChange>[];

      final client = createClient(
        ClientOptions(
          authCallback: makeAuthCallback(apiKey),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
          disconnectedRetryTimeout: 2000,
        ),
      );
      addTearDown(client.close);

      client.connection.on().listen(stateChanges.add);

      await client.connect();

      // Should eventually reach CONNECTED after retry
      await client.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 15));

      expect(client.connection.state, equals(ConnectionState.connected));

      // Verify state sequence: connecting -> disconnected -> connecting -> connected
      final states = stateChanges.map((e) => e.current).toList();
      expect(states, contains(ConnectionState.connecting));
      expect(states, contains(ConnectionState.disconnected));
      expect(states, contains(ConnectionState.connected));

      // Verify the sequence order
      final firstConnecting = states.indexOf(ConnectionState.connecting);
      final disconnected = states.indexOf(ConnectionState.disconnected);
      final lastConnected = states.lastIndexOf(ConnectionState.connected);
      expect(firstConnecting, lessThan(disconnected));
      expect(disconnected, lessThan(lastConnected));
    });

    // -------------------------------------------------------------------------
    // RTN14g - Connection-level ERROR 50000 -> FAILED
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN14g/server-error-causes-failed-0
    test('RTN14g - Connection-level ERROR 50000 -> FAILED', () async {
      final session = await ProxySession.create(
        rules: [
          // Replace first CONNECTED with ERROR action=9, code=50000
          {
            'match': {
              'type': 'ws_frame_to_client',
              'action': 'CONNECTED',
            },
            'action': {
              'type': 'replace',
              'message': {
                'action': 9, // ERROR
                'error': {
                  'message': 'Internal server error',
                  'code': 50000,
                  'statusCode': 500,
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;

      final client = createClient(
        ClientOptions(
          authCallback: makeAuthCallback(apiKey),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(client.close);

      final failedFuture = client.connection
          .on(ConnectionEvent.failed)
          .first
          .timeout(const Duration(seconds: 10));

      unawaited(client.connect());

      await failedFuture;

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason, isNotNull);
      expect(client.connection.errorReason!.code, equals(50000));
    });

    // -------------------------------------------------------------------------
    // RTN14c - Connection timeout (CONNECTED suppressed)
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTN14c/connection-timeout-0
    test('RTN14c - Connection timeout (CONNECTED suppressed)', () async {
      final session = await ProxySession.create(
        rules: [
          // Suppress all CONNECTED messages
          {
            'match': {
              'type': 'ws_frame_to_client',
              'action': 'CONNECTED',
            },
            'action': {'type': 'suppress'},
          },
        ],
      );
      addTearDown(session.close);

      final apiKey = testApp.keys[0].keyStr;

      final client = createClient(
        ClientOptions(
          authCallback: makeAuthCallback(apiKey),
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
          realtimeRequestTimeout: 3000,
        ),
      );
      addTearDown(client.close);

      final disconnectedFuture = client.connection
          .on(ConnectionEvent.disconnected)
          .first
          .timeout(const Duration(seconds: 10));

      unawaited(client.connect());

      await disconnectedFuture;

      expect(client.connection.state, equals(ConnectionState.disconnected));
      expect(
        client.connection.errorReason,
        isNotNull,
        reason: 'Should have timeout error',
      );
    });
  });
}

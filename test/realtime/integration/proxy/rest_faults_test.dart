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

  group('REST Fault Proxy Integration Tests', () {
    // -------------------------------------------------------------------------
    // RSC10 - Token renewal on HTTP 401
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RSC10/token-renewal-on-401-0
    test('RSC10 - Token renewal on HTTP 401', () async {
      final apiKey = testApp.keys[0].keyStr;
      final channelName =
          'rsc10-token-renewal-${DateTime.now().millisecondsSinceEpoch}';
      var authCallbackCount = 0;

      // Proxy rule: first HTTP request to /channels/ returns 401 with
      // error 40142 (token expired), then passthrough
      final session = await ProxySession.create(
        rules: [
          {
            'match': {
              'type': 'http_request',
              'pathContains': '/channels/',
            },
            'action': {
              'type': 'http_respond',
              'status': 401,
              'body': {
                'error': {
                  'code': 40142,
                  'statusCode': 401,
                  'message': 'Token expired',
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(() async => await session.close());

      final client = RestClient(
        options: ClientOptions(
          authCallback: (params) async {
            authCallbackCount++;
            final innerRestClient = RestClient(
              options: ClientOptions(
                key: apiKey,
                endpoint: 'nonprod:sandbox',
                useBinaryProtocol: false,
              ),
            );
            final tokenDetails = await innerRestClient.auth.requestToken();
            await innerRestClient.close();
            return tokenDetails;
          },
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
        ),
      );
      addTearDown(() async => await client.close());

      final channel = client.channels.get(channelName);

      // Publish should succeed after automatic token renewal
      await channel.publish(name: 'event', data: 'data');

      // Assert: authCallback called at least 2 times
      // (once for initial token, once for renewal after 401)
      expect(
        authCallbackCount,
        greaterThanOrEqualTo(2),
        reason: 'Auth callback should be called at least twice: '
            'initial + renewal after 401',
      );
    });

    // -------------------------------------------------------------------------
    // RSC15m/REC2c2 - HTTP 503 error (no fallback through proxy)
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RSC15m/http-503-no-fallback-0
    test('RSC15m/REC2c2 - HTTP 503 error (no fallback through proxy)',
        () async {
      final apiKey = testApp.keys[0].keyStr;
      final channelName = 'rsc15m-503-${DateTime.now().millisecondsSinceEpoch}';

      // Proxy rule: HTTP request to /channels/ returns 503
      final session = await ProxySession.create(
        rules: [
          {
            'match': {
              'type': 'http_request',
              'pathContains': '/channels/',
            },
            'action': {
              'type': 'http_respond',
              'status': 503,
              'body': {
                'error': {
                  'code': 50300,
                  'statusCode': 503,
                  'message': 'Service unavailable',
                },
              },
            },
            'times': 1,
          },
        ],
      );
      addTearDown(() async => await session.close());

      final client = RestClient(
        options: ClientOptions(
          authCallback: (params) async {
            final innerRestClient = RestClient(
              options: ClientOptions(
                key: apiKey,
                endpoint: 'nonprod:sandbox',
                useBinaryProtocol: false,
              ),
            );
            final tokenDetails = await innerRestClient.auth.requestToken();
            await innerRestClient.close();
            return tokenDetails;
          },
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
        ),
      );
      addTearDown(() async => await client.close());

      final channel = client.channels.get(channelName);

      // Publish should throw with code 50300
      try {
        await channel.publish(name: 'event', data: 'data');
        fail('Expected publish to throw with 503 error');
      } on ErrorInfo catch (e) {
        expect(e.code, equals(50300));
      } on AblyException catch (e) {
        expect(e.code, equals(50300));
      }

      // Check proxy log: should have only 1 HTTP request to channels
      // (no fallback since endpoint is explicit hostname)
      final log = await session.getLog();
      final channelRequests = log.where((event) {
        final type = event['type'] as String? ?? '';
        if (type != 'http_request') return false;
        final path = event['path'] as String? ?? '';
        return path.contains('/channels/');
      }).toList();
      expect(
        channelRequests.length,
        equals(1),
        reason: 'Should have only 1 HTTP request (no fallback for '
            'explicit hostname)',
      );
    });

    // -------------------------------------------------------------------------
    // RTL6 - End-to-end publish and history through proxy
    // -------------------------------------------------------------------------
    // UTS: realtime/proxy/RTL6/publish-history-through-proxy-0
    test('RTL6 - End-to-end publish and history through proxy', () async {
      final apiKey = testApp.keys[0].keyStr;
      final channelName =
          'rtl6-e2e-publish-${DateTime.now().millisecondsSinceEpoch}';

      // No proxy rules (passthrough)
      final session = await ProxySession.create();
      addTearDown(() async => await session.close());

      // Create Realtime client
      final realtimeClient = RealtimeClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
          autoConnect: false,
        ),
      );
      addTearDown(() async => await realtimeClient.close());

      await realtimeClient.connect();

      final realtimeChannel = realtimeClient.channels.get(channelName);

      // Attach and publish
      await realtimeChannel.attach();
      await realtimeChannel.publish(name: 'test-msg', data: 'hello world');

      // Allow message to propagate
      await Future<void>.delayed(const Duration(seconds: 1));

      // Create REST client through the same proxy
      final restClient = RestClient(
        options: ClientOptions(
          authCallback: (params) async {
            return JwtHelper.generateToken(apiKey: apiKey);
          },
          endpoint: 'localhost',
          port: session.proxyPort,
          tls: false,
          useBinaryProtocol: false,
        ),
      );
      addTearDown(() async => await restClient.close());

      final restChannel = restClient.channels.get(channelName);

      // Poll until history contains the published message
      final result = await pollUntil(
        () async {
          final history = await restChannel.history();
          if (history.items.isNotEmpty) return history;
          return null;
        },
        timeout: const Duration(seconds: 15),
      );

      // Assert: history contains the published message
      expect(result.items, isNotEmpty);
      final message = result.items.first;
      expect(message.name, equals('test-msg'));
      expect(message.data, equals('hello world'));
    });
  });
}

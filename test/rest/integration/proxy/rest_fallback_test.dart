@Tags(['integration', 'proxy'])
library;

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/proxy_helper.dart';
import '../../../helpers/test_app_helper.dart';

Future<Object> Function(TokenParams params) _tokenAuthCallback(String apiKey) {
  return (params) async {
    final innerRestClient = RestClient(
      options: ClientOptions(
        key: apiKey,
        endpoint: 'nonprod:sandbox',
        useBinaryProtocol: false,
      ),
    );
    try {
      return await innerRestClient.auth.requestToken();
    } finally {
      await innerRestClient.close();
    }
  };
}

/// REST Fallback Proxy Integration Tests
///
/// Spec points: RSC15l, RSC15l2, RSC15l4, RSL1k4
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

  // ---------------------------------------------------------------------------
  // RSC15l2 - Request timeout triggers fallback via proxy
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l2/timeout-triggers-fallback-0
  test('RSC15l2 - Request timeout triggers fallback via proxy', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_delay',
            'delayMs': 20000,
          },
          'times': 1,
          'comment':
              'RSC15l2: Delay first /time request beyond httpRequestTimeout',
        },
      ],
    );
    addTearDown(() async => session.close());

    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        fallbackHosts: ['localhost'],
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
        httpRequestTimeout: 3000,
      ),
    );
    addTearDown(() async => client.close());

    final result = await client.time();
    expect(result, isA<DateTime>());

    final log = await session.getLog();
    final httpRequests = log.where((e) {
      final type = e['type'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      return type == 'http_request' && path.contains('/time');
    }).toList();
    expect(httpRequests.length, greaterThanOrEqualTo(2));
  });

  // ---------------------------------------------------------------------------
  // RSC15l4 - CloudFront Server header triggers fallback via proxy
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l4/cloudfront-header-fallback-0
  test('RSC15l4 - CloudFront Server header triggers fallback via proxy',
      () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_respond',
            'status': 403,
            'body': {
              'error': {
                'message': 'Forbidden',
                'code': 40300,
                'statusCode': 403,
              },
            },
            'headers': {
              'Server': 'CloudFront',
            },
          },
          'times': 1,
          'comment': 'RSC15l4: CloudFront 403 on first /time request',
        },
      ],
    );
    addTearDown(() async => session.close());

    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        fallbackHosts: ['localhost'],
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    final result = await client.time();
    expect(result, isA<DateTime>());

    final log = await session.getLog();
    final httpRequests = log.where((e) {
      final type = e['type'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      return type == 'http_request' && path.contains('/time');
    }).toList();
    expect(httpRequests.length, greaterThanOrEqualTo(2));

    final httpResponses = log.where((e) {
      final type = e['type'] as String? ?? '';
      return type == 'http_response';
    }).toList();
    expect((httpResponses[0]['status'] as num?)?.toInt(), equals(403));
  });

  // ---------------------------------------------------------------------------
  // Unreachable endpoint surfaces correct error (no proxy)
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l/unreachable-endpoint-error-0
  test('Unreachable endpoint surfaces correct error (no proxy)', () async {
    final apiKey = testApp.keys[0].keyStr;
    const nonListeningPort = 19999;

    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        port: nonListeningPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    try {
      await client.time();
      fail('Expected connection error');
    } catch (e) {
      expect(e, isNotNull);
      if (e is AblyException) {
        expect(
          e.statusCode != null || e.code != null,
          isTrue,
          reason: 'Error should have statusCode or code',
        );
      }
    }
  });

  // ---------------------------------------------------------------------------
  // Connection drop mid-response retried on fallback (http_drop)
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l/connection-drop-fallback-1
  test('Connection drop mid-response retried on fallback', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_drop',
          },
          'times': 1,
          'comment': 'Drop TCP connection on first /time request (ECONNRESET)',
        },
      ],
    );
    addTearDown(() async => session.close());

    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        fallbackHosts: ['localhost'],
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    final result = await client.time();
    expect(result, isA<DateTime>());

    final log = await session.getLog();
    final httpRequests = log.where((e) {
      final type = e['type'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      return type == 'http_request' && path.contains('/time');
    }).toList();
    expect(httpRequests.length, greaterThanOrEqualTo(2));
  });

  // ---------------------------------------------------------------------------
  // HTTP 5xx with JSON error body -- error parsed correctly
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l/http-5xx-json-error-parsed-0
  test('HTTP 5xx with JSON error body -- error parsed correctly', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_respond',
            'status': 503,
            'body': {
              'error': {
                'code': 50300,
                'statusCode': 503,
                'message': 'Service temporarily unavailable',
              },
            },
          },
          'times': 1,
          'comment': 'Return 503 with JSON error body on first /time request',
        },
      ],
    );
    addTearDown(() async => session.close());

    // No fallbackHosts -- endpoint="localhost" disables fallback (REC2c2)
    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    try {
      await client.time();
      fail('Expected 503 error');
    } catch (e) {
      expect(e, isA<AblyException>());
      final err = e as AblyException;
      expect(err.code, equals(50300));
      expect(err.statusCode, equals(503));
      expect(err.message, contains('Service temporarily unavailable'));
    }
  });

  // ---------------------------------------------------------------------------
  // HTTP 5xx without JSON error body -- error synthesized
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l/http-5xx-no-json-synthesized-1
  test('HTTP 5xx without JSON error body -- error synthesized', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_respond',
            'status': 503,
            'body': {},
          },
          'times': 1,
          'comment':
              'Return 503 with empty JSON body (no error field) on first /time request',
        },
      ],
    );
    addTearDown(() async => session.close());

    // No fallbackHosts -- endpoint="localhost" disables fallback (REC2c2)
    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    try {
      await client.time();
      fail('Expected 503 error');
    } catch (e) {
      expect(e, isA<AblyException>());
      final err = e as AblyException;
      expect(err.statusCode, equals(503));
    }
  });

  // ---------------------------------------------------------------------------
  // HTTP 4xx with JSON error body -- not retried, error parsed
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSC15l/http-4xx-not-retried-0
  test('HTTP 4xx with JSON error body -- not retried, error parsed', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'pathContains': '/time',
          },
          'action': {
            'type': 'http_respond',
            'status': 403,
            'body': {
              'error': {
                'code': 40300,
                'statusCode': 403,
                'message': 'Forbidden',
              },
            },
          },
          'times': 1,
          'comment': 'Return 403 with JSON error body on first /time request',
        },
      ],
    );
    addTearDown(() async => session.close());

    // Fallback hosts ARE configured -- but 403 should NOT trigger fallback
    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        fallbackHosts: ['localhost'],
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    try {
      await client.time();
      fail('Expected 403 error');
    } catch (e) {
      expect(e, isA<AblyException>());
      final err = e as AblyException;
      expect(err.code, equals(40300));
      expect(err.statusCode, equals(403));
    }

    // Proxy event log shows exactly 1 HTTP request to /time (no fallback retry)
    final log = await session.getLog();
    final httpRequests = log.where((e) {
      final type = e['type'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      return type == 'http_request' && path.contains('/time');
    }).toList();
    expect(httpRequests.length, equals(1));
  });

  // ---------------------------------------------------------------------------
  // RSL1k4 - Idempotent publish retry deduplication
  // ---------------------------------------------------------------------------
  // UTS: rest/proxy/RSL1k4/idempotent-retry-dedup-0
  test('RSL1k4 - Idempotent publish retry deduplication', () async {
    final apiKey = testApp.keys[0].keyStr;

    final session = await ProxySession.create(
      rules: [
        {
          'match': {
            'type': 'http_request',
            'method': 'POST',
            'pathContains': '/channels/',
          },
          'action': {
            'type': 'http_replace_response',
            'status': 503,
            'body': {
              'error': {
                'code': 50300,
                'statusCode': 503,
                'message': 'Service temporarily unavailable',
              },
            },
          },
          'times': 1,
          'comment': 'RSL1k4: Forward first publish to server, return fake 503',
        },
      ],
    );
    addTearDown(() async => session.close());

    final client = RestClient(
      options: ClientOptions(
        authCallback: _tokenAuthCallback(apiKey),
        endpoint: 'localhost',
        fallbackHosts: ['localhost'],
        port: session.proxyPort,
        tls: false,
        useBinaryProtocol: false,
      ),
    );
    addTearDown(() async => client.close());

    final channelName = 'test-RSL1k4-${DateTime.now().millisecondsSinceEpoch}';
    final channel = client.channels.get(channelName);

    // Publish — first attempt succeeds server-side but client sees 503,
    // SDK retries, server deduplicates the retry
    await channel.publish(name: 'test', data: 'data');

    // Verify via history that only one copy of the message exists
    final history = await channel.history();
    final matching = history.items
        .where((m) => m.name == 'test' && m.data == 'data')
        .toList();
    expect(matching.length, equals(1));

    // Proxy event log shows at least two POST requests to /channels/
    final log = await session.getLog();
    final httpRequests = log.where((e) {
      final type = e['type'] as String? ?? '';
      final method = e['method'] as String? ?? '';
      final path = e['path'] as String? ?? '';
      return type == 'http_request' &&
          method == 'POST' &&
          path.contains('/channels/');
    }).toList();
    expect(httpRequests.length, greaterThanOrEqualTo(2));
  });
}

import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Fallback and Endpoint Configuration Tests
///
/// Spec points: REC1, REC2, REC3, RSC15f
void main() {
  group('Fallback and Endpoint Configuration', () {
    group('REC1 - Primary Domain Configuration', () {
      // UTS: rest/unit/REC1a/default-primary-domain-0
      test('REC1a - Default primary domain is main.realtime.ably.net', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');
        expect(options.primaryDomain, equals('main.realtime.ably.net'));
        expect(options.effectiveRestHost, equals('main.realtime.ably.net'));
        expect(options.effectiveRealtimeHost, equals('main.realtime.ably.net'));
      });

      group('REC1b2 - Endpoint as explicit hostname', () {
        // UTS: rest/unit/REC1b2/explicit-hostname-with-period-0
        test('hostname with period is explicit', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'custom.host.com',
          );
          expect(options.primaryDomain, equals('custom.host.com'));
        });

        // UTS: rest/unit/REC1b2/endpoint-localhost-1
        test('localhost is explicit hostname', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'localhost',
          );
          expect(options.primaryDomain, equals('localhost'));
        });

        // UTS: rest/unit/REC1b2/endpoint-ipv6-address-2
        test('IPv6 address with :: is explicit hostname', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: '::1',
          );
          expect(options.primaryDomain, equals('::1'));
        });
      });

      group('REC1b3 - Endpoint as nonprod routing policy', () {
        // UTS: rest/unit/REC1b3/nonprod-routing-policy-0
        test('nonprod:id format creates nonprod domain', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'nonprod:myapp',
          );
          expect(
            options.primaryDomain,
            equals('myapp.realtime.ably-nonprod.net'),
          );
        });
      });

      group('REC1b4 - Endpoint as production routing policy', () {
        // UTS: rest/unit/REC1b4/production-routing-policy-0
        test('non-explicit endpoint creates production domain', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'myapp',
          );
          expect(
            options.primaryDomain,
            equals('myapp.realtime.ably.net'),
          );
        });

        // UTS: rest/unit/REC2c5/production-environment-fallback-domains-0
        test('test is a production routing policy', () {
          final options = ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'test',
          );
          expect(
            options.primaryDomain,
            equals('test.realtime.ably.net'),
          );
        });
      });
    });

    group('REC2 - Fallback Domains Configuration', () {
      // UTS: rest/unit/REC2c1/default-fallback-domains-0
      test('REC2c1 - Default fallback domains', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');
        // effectiveFallbackHosts returns null to use default from constants
        expect(options.effectiveFallbackHosts, isNull);
      });

      // UTS: rest/unit/REC2a2/custom-fallback-hosts-0
      test('REC2a2 - Custom fallbackHosts option', () {
        final customHosts = ['fallback1.example.com', 'fallback2.example.com'];
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          fallbackHosts: customHosts,
        );
        expect(options.effectiveFallbackHosts, equals(customHosts));
      });

      // UTS: rest/unit/REC2c2/explicit-hostname-no-fallbacks-0
      test('REC2c2 - Explicit hostname endpoint has no fallbacks', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'custom.host.com',
        );
        expect(options.effectiveFallbackHosts, isNull);
      });

      // UTS: rest/unit/REC2c3/nonprod-fallback-domains-0
      test('REC2c3 - Nonprod routing policy fallback domains', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'nonprod:myapp',
        );
        final fallbacks = options.effectiveFallbackHosts!;
        expect(fallbacks.length, equals(5));
        expect(
          fallbacks[0],
          equals('myapp.a.fallback.ably-realtime-nonprod.com'),
        );
        expect(
          fallbacks[1],
          equals('myapp.b.fallback.ably-realtime-nonprod.com'),
        );
      });

      // UTS: rest/unit/REC2c4/production-endpoint-fallback-domains-0
      test('REC2c4 - Production routing policy fallback domains (via endpoint)',
          () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'myapp',
        );
        final fallbacks = options.effectiveFallbackHosts!;
        expect(fallbacks.length, equals(5));
        expect(fallbacks[0], equals('myapp.a.fallback.ably-realtime.com'));
        expect(fallbacks[1], equals('myapp.b.fallback.ably-realtime.com'));
      });
    });

    group('REC3 - Connectivity Check URL', () {
      // UTS: rest/unit/REC3a/default-connectivity-check-url-0
      test('REC3a - Default connectivity check URL', () {
        final options = ClientOptions.fromKey('appId.keyId:keySecret');
        expect(
          options.effectiveConnectivityCheckUrl,
          equals(
            'https://internet-up.ably-realtime.com/is-the-internet-up.txt',
          ),
        );
      });

      // UTS: rest/unit/REC3b/custom-connectivity-check-url-0
      test('REC3b - Custom connectivity check URL', () {
        final options = ClientOptions(
          key: 'appId.keyId:keySecret',
          connectivityCheckUrl: 'https://custom-check.example.com/check',
        );
        expect(
          options.effectiveConnectivityCheckUrl,
          equals('https://custom-check.example.com/check'),
        );
      });
    });

    // Note: UTS tests for legacy options (REC1b1, REC1c1, REC1c2, REC1d,
    // REC1d1, REC1d2, REC2a1, REC2b, REC2c6) test restHost, realtimeHost,
    // environment, and fallbackHostsUseDefault — deprecated options that this
    // SDK does not implement. The Dart SDK uses `endpoint` exclusively per the
    // modern spec (REC1b). These UTS test IDs are not applicable here.

    group('RSC15m - Fallback with empty hosts', () {
      // UTS: rest/unit/RSC15m/no-fallback-empty-hosts-0
      test('RSC15m - empty fallbackHosts means no fallback retry', () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            req.respondWith(500, {
              'error': {
                'message': 'Server error',
                'code': 50000,
                'statusCode': 500,
              },
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            fallbackHosts: [],
          ),
          httpClient: mockHttp,
        );

        try {
          await client.time();
          fail('Expected an exception');
        } on AblyException catch (e) {
          expect(e.errorInfo?.statusCode, equals(500));
        }

        // Only 1 request - no fallback attempted
        expect(requestCount, equals(1));
        expect(mockHttp.capturedRequests, hasLength(1));
      });
    });

    group('RSC15a - Fallback host order', () {
      // UTS: rest/unit/RSC15a/fallback-random-order-0
      test('RSC15a - primary tried first, then fallback hosts', () async {
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(500, {
              'error': {
                'message': 'Server error',
                'code': 50000,
                'statusCode': 500,
              },
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        try {
          await client.time();
          fail('Expected an exception');
        } on AblyException {
          // Expected
        }

        // Primary + up to httpMaxRetryCount fallbacks
        expect(mockHttp.capturedRequests.length, greaterThan(1));

        // First request goes to primary
        expect(
          mockHttp.capturedRequests[0].url.host,
          equals('main.realtime.ably.net'),
        );

        // Subsequent requests go to fallback hosts
        const expectedFallbacks = [
          'main.a.fallback.ably-realtime.com',
          'main.b.fallback.ably-realtime.com',
          'main.c.fallback.ably-realtime.com',
          'main.d.fallback.ably-realtime.com',
          'main.e.fallback.ably-realtime.com',
        ];

        for (var i = 1; i < mockHttp.capturedRequests.length; i++) {
          expect(
            expectedFallbacks,
            contains(mockHttp.capturedRequests[i].url.host),
          );
        }
      });
    });

    group('RSC15l - Qualifying errors trigger fallback', () {
      // UTS: rest/unit/RSC15l/qualifying-errors-trigger-fallback-0
      test('RSC15l - qualifying errors trigger fallback (overview)', () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              req.respondWith(500, {
                'error': {
                  'message': 'Server error',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else {
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(requestCount, equals(2));
        expect(
          mockHttp.capturedRequests[0].url.host,
          equals('main.realtime.ably.net'),
        );
        expect(
          mockHttp.capturedRequests[1].url.host,
          isNot(equals('main.realtime.ably.net')),
        );
      });

      // UTS: rest/unit/RSC15l/connection-refused-fallback-0
      test('RSC15l - connection refused on primary triggers fallback',
          () async {
        var connectionCount = 0;

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            if (connectionCount == 1) {
              conn.respondWithRefused();
            } else {
              conn.respondWithSuccess();
            }
          },
          onRequest: (req) {
            req.respondWith(200, [1000]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(connectionCount, equals(2));
      });

      // UTS: rest/unit/RSC15l/dns-error-fallback-1
      test('RSC15l - DNS error on primary triggers fallback', () async {
        var connectionCount = 0;

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            if (connectionCount == 1) {
              conn.respondWithDnsError();
            } else {
              conn.respondWithSuccess();
            }
          },
          onRequest: (req) {
            req.respondWith(200, [1000]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(connectionCount, equals(2));
      });

      // UTS: rest/unit/RSC15l/connection-timeout-fallback-2
      test('RSC15l - connection timeout on primary triggers fallback',
          () async {
        var connectionCount = 0;

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) {
            connectionCount++;
            if (connectionCount == 1) {
              conn.respondWithTimeout();
            } else {
              conn.respondWithSuccess();
            }
          },
          onRequest: (req) {
            req.respondWith(200, [1000]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(connectionCount, equals(2));
      });

      // UTS: rest/unit/RSC15l/request-timeout-fallback-3
      test('RSC15l - request timeout triggers fallback', () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              req.respondWithTimeout();
            } else {
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(requestCount, equals(2));
        expect(
          mockHttp.capturedRequests[0].url.host,
          isNot(equals(mockHttp.capturedRequests[1].url.host)),
        );
      });

      // UTS: rest/unit/RSC15l/http-5xx-triggers-fallback-4
      test('RSC15l - HTTP 5xx status codes trigger fallback', () async {
        for (final statusCode in [500, 501, 502, 503, 504]) {
          var requestCount = 0;

          final mockHttp = MockHttpClient(
            onRequest: (req) {
              requestCount++;
              if (requestCount == 1) {
                req.respondWith(statusCode, {
                  'error': {
                    'message': 'Server error',
                    'code': statusCode * 100,
                    'statusCode': statusCode,
                  },
                });
              } else {
                req.respondWith(200, [1000]);
              }
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(key: 'appId.keyId:keySecret'),
            httpClient: mockHttp,
          );

          await client.time();

          expect(
            requestCount,
            equals(2),
            reason: 'HTTP $statusCode should trigger fallback',
          );
        }
      });

      // UTS: rest/unit/RSC15l/http-4xx-no-fallback-5
      test('RSC15l - HTTP 4xx status codes do NOT trigger fallback', () async {
        for (final statusCode in [400, 401, 404]) {
          var requestCount = 0;

          final mockHttp = MockHttpClient(
            onRequest: (req) {
              requestCount++;
              req.respondWith(statusCode, {
                'error': {
                  'message': 'Client error',
                  'code': statusCode * 100,
                  'statusCode': statusCode,
                },
              });
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(key: 'appId.keyId:keySecret'),
            httpClient: mockHttp,
          );

          try {
            await client.time();
            fail('Expected an exception for HTTP $statusCode');
          } on AblyException catch (e) {
            expect(e.errorInfo?.statusCode, equals(statusCode));
          }

          // Only 1 request - no fallback
          expect(
            requestCount,
            equals(1),
            reason: 'HTTP $statusCode should NOT trigger fallback',
          );
        }
      });

      // UTS: rest/unit/RSC15l4/cloudfront-error-triggers-fallback-0
      test(
        'RSC15l4 - CloudFront Server header with status >= 400 '
        'triggers fallback',
        () async {
          var requestCount = 0;

          final mockHttp = MockHttpClient(
            onRequest: (req) {
              requestCount++;
              if (requestCount == 1) {
                req.respondWith(
                  403,
                  {
                    'error': {
                      'message': 'Forbidden',
                      'code': 40300,
                      'statusCode': 403,
                    },
                  },
                  headers: {'Server': 'CloudFront'},
                );
              } else {
                req.respondWith(200, [1000]);
              }
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions(key: 'appId.keyId:keySecret'),
            httpClient: mockHttp,
          );

          final result = await client.time();
          expect(result, isA<DateTime>());
          expect(
            requestCount,
            equals(2),
            reason: 'CloudFront 403 should trigger fallback retry',
          );
        },
      );
    });

    group('RSC15j - Host header', () {
      // UTS: rest/unit/RSC15j/host-header-matches-request-0
      test('RSC15j - Host header matches request host for fallback requests',
          () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              req.respondWith(500, {
                'error': {
                  'message': 'fail',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else {
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(key: 'appId.keyId:keySecret'),
          httpClient: mockHttp,
        );

        await client.time();

        expect(mockHttp.capturedRequests, hasLength(2));

        final request1 = mockHttp.capturedRequests[0];
        final request2 = mockHttp.capturedRequests[1];

        // Each request URL host should be different (primary vs fallback)
        expect(request1.url.host, isNot(equals(request2.url.host)));

        // The URL host should match the actual host the request was sent to.
        // Dart http library sets the Host header automatically from the URL,
        // so the URL host IS the host being requested.
        expect(request1.url.host, equals('main.realtime.ably.net'));
        expect(request2.url.host, isNot(equals('main.realtime.ably.net')));
      });
    });

    group('RSC15f - Fallback host caching', () {
      // UTS: rest/unit/RSC15f/successful-fallback-cached-0
      test(
          'RSC15f - successful fallback host is cached for subsequent requests',
          () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // Primary fails
              req.respondWith(500, {
                'error': {
                  'message': 'fail',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else {
              // Fallback and subsequent requests succeed
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            fallbackRetryTimeout: 60000,
          ),
          httpClient: mockHttp,
        );

        // First request: primary fails, fallback succeeds and gets cached
        await client.time();
        final fallbackHost = mockHttp.capturedRequests[1].url.host;
        expect(fallbackHost, isNot(equals('main.realtime.ably.net')));

        // Second request: should go directly to cached fallback
        await client.time();

        expect(mockHttp.capturedRequests, hasLength(3));
        expect(
          mockHttp.capturedRequests[0].url.host,
          equals('main.realtime.ably.net'),
        );
        expect(mockHttp.capturedRequests[1].url.host, equals(fallbackHost));
        // Third request goes to cached fallback, not primary
        expect(mockHttp.capturedRequests[2].url.host, equals(fallbackHost));
      });

      // UTS: rest/unit/RSC15f/cached-fallback-expires-1
      test('RSC15f - cached fallback expires after fallbackRetryTimeout',
          () async {
        var requestCount = 0;

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // Primary fails
              req.respondWith(500, {
                'error': {
                  'message': 'fail',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else {
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            fallbackRetryTimeout: 100,
          ),
          httpClient: mockHttp,
        );

        // First request: primary fails, fallback succeeds
        await client.time();

        // Wait for cache to expire
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Next request should try primary again
        await client.time();

        expect(mockHttp.capturedRequests, hasLength(3));
        // After timeout, primary is tried again
        expect(
          mockHttp.capturedRequests[2].url.host,
          equals('main.realtime.ably.net'),
        );
      });
    });

    group('RSC15f - Fallback host caching (legacy)', () {
      // UTS: rest/unit/RSC15f/expired-not-resurrected-2
      test(
          'RSC15f - expired preferred fallback not resurrected by late '
          'in-flight success', () async {
        PendingRequest? heldRequest;
        var requestIndex = 0;
        final hosts = <String>[];

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestIndex++;
            hosts.add(req.url.host);
            if (requestIndex == 1) {
              req.respondWith(500, {
                'error': {
                  'message': 'fail',
                  'code': 50000,
                  'statusCode': 500,
                },
              });
            } else if (requestIndex == 2) {
              req.respondWith(200, [1000]);
            } else if (requestIndex == 3) {
              heldRequest = req;
            } else {
              req.respondWith(200, [1000]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            fallbackRetryTimeout: 100,
          ),
          httpClient: mockHttp,
        );

        // Request 1+2: primary fails → fallback succeeds → cached
        await client.time();
        final fallbackHost = hosts[1];
        expect(fallbackHost, isNot(equals('main.realtime.ably.net')));

        // Request 3: goes to cached fallback, hold the response
        final requestFuture = client.time();

        // Advance past fallbackRetryTimeout so cache expires
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Request 4: cache expired → primary again
        await client.time();
        expect(hosts[3], equals('main.realtime.ably.net'));

        // Complete the held request
        expect(heldRequest, isNotNull);
        heldRequest!.respondWith(200, [1000]);
        await requestFuture;

        // Request 5: late success must NOT re-pin fallback
        await client.time();

        expect(hosts, hasLength(5));
        expect(hosts[0], equals('main.realtime.ably.net'));
        expect(hosts[1], equals(fallbackHost));
        expect(hosts[2], equals(fallbackHost));
        expect(hosts[3], equals('main.realtime.ably.net'));
        expect(hosts[4], equals('main.realtime.ably.net'));
      });
    });
  });
}

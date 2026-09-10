import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// PaginatedResult Types Tests
///
/// Spec points: TG1, TG2, TG3, TG4
void main() {
  group('PaginatedResult', () {
    group('TG1 - PaginatedResult items attribute', () {
      // UTS: rest/unit/TG1/paginated-result-items-0
      test('contains items array', () async {
        final channelName = testChannelName('TG1');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'item1', 'name': 'e1', 'data': 'd1'},
                {'id': 'item2', 'name': 'e2', 'data': 'd2'},
              ],
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        expect(result.items, isList);
        expect(result.items.length, equals(2));
        expect(result.items[0].id, equals('item1'));
        expect(result.items[1].id, equals('item2'));
      });
    });

    group('TG2 - hasNext() and isLast() methods', () {
      // UTS: rest/unit/TG2/has-next-is-last-0
      test('returns true when more pages exist', () async {
        final channelName = testChannelName('TG2-hasNext');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'item1'},
              ],
              headers: {
                'Link':
                    '</channels/$channelName/messages?cursor=next123>; rel="next"',
              },
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        expect(result.hasNext(), isTrue);
        expect(result.isLast(), isFalse);
      });

      // UTS: rest/unit/TG2/has-next-is-last-0.1
      test('returns false when no more pages', () async {
        final channelName = testChannelName('TG2-isLast');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'item1'},
              ],
              headers: {},
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        expect(result.hasNext(), isFalse);
        expect(result.isLast(), isTrue);
      });
    });

    group('TG3 - next() method', () {
      // UTS: rest/unit/TG3/next-fetches-next-page-0
      test('fetches the next page of results', () async {
        var requestCount = 0;
        final channelName = testChannelName('TG3');

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // First page
              req.respondWith(
                200,
                [
                  {'id': 'page1-item1'},
                  {'id': 'page1-item2'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=abc123>; rel="next"',
                },
              );
            } else {
              // Second page
              req.respondWith(
                200,
                [
                  {'id': 'page2-item1'},
                ],
                headers: {},
              );
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        final page2 = await page1.next();

        // First page
        expect(page1.items.length, equals(2));
        expect(page1.items[0].id, equals('page1-item1'));
        expect(page1.hasNext(), isTrue);

        // Second page
        expect(page2, isNotNull);
        expect(page2!.items.length, equals(1));
        expect(page2.items[0].id, equals('page2-item1'));
        expect(page2.hasNext(), isFalse);

        // Verify next request used cursor from Link header
        final nextRequest = mockHttp.capturedRequests[1];
        expect(nextRequest.url.queryParameters['cursor'], equals('abc123'));
      });
    });

    group('TG4 - first() method', () {
      // UTS: rest/unit/TG4/first-returns-first-page-0
      test('returns to the first page', () async {
        var requestCount = 0;
        final channelName = testChannelName('TG4');

        final mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // Initial request
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=next>; rel="next", </channels/$channelName/messages>; rel="first"',
                },
              );
            } else if (requestCount == 2) {
              // Next page
              req.respondWith(
                200,
                [
                  {'id': 'item2'},
                ],
                headers: {
                  'Link': '</channels/$channelName/messages>; rel="first"',
                },
              );
            } else {
              // First page again
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=next>; rel="next"',
                },
              );
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        final page2 = await page1.next();
        final firstPage = await page2!.first();

        expect(firstPage.items[0].id, equals('item1'));
      });
    });

    group('TG - Empty result', () {
      // UTS: rest/unit/TG/empty-result-handling-0
      test('handles empty results correctly', () async {
        final channelName = testChannelName('TG-empty');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [], headers: {});
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        expect(result.items, isList);
        expect(result.items.length, equals(0));
        expect(result.hasNext(), isFalse);
        expect(result.isLast(), isTrue);
      });
    });

    group('TG - Link header parsing', () {
      final testCases = [
        (
          linkHeader: '</path?cursor=abc>; rel="next"',
          expectedHasNext: true,
          description: 'simple next link',
        ),
        (
          linkHeader: '</path?cursor=abc>; rel="next", </path>; rel="first"',
          expectedHasNext: true,
          description: 'next and first links',
        ),
        (
          linkHeader: '</path>; rel="first"',
          expectedHasNext: false,
          description: 'only first link',
        ),
        (
          linkHeader: null,
          expectedHasNext: false,
          description: 'no Link header',
        ),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/TG/link-header-parsing-1
        test('parses ${testCase.description}', () async {
          final channelName = testChannelName(
            'TG-link-${testCase.description.replaceAll(' ', '-')}',
          );
          final mockHttp = MockHttpClient(
            onRequest: (req) {
              req.respondWith(
                200,
                [
                  {'id': 'item'},
                ],
                headers: testCase.linkHeader != null
                    ? {'Link': testCase.linkHeader!}
                    : {},
              );
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final result = await client.channels.get(channelName).history();

          expect(result.hasNext(), equals(testCase.expectedHasNext));
        });
      }
    });

    group('TG - PaginatedResult type parameter', () {
      // UTS: rest/unit/TG/type-parameter-items-2
      test('items are correctly typed as Message', () async {
        final channelName = testChannelName('TG-type');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'msg1', 'name': 'event', 'data': 'test'},
              ],
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final historyResult = await channel.history();

        expect(historyResult.items[0], isA<Message>());
      });
    });

    group('TG - next() on last page', () {
      // UTS: rest/unit/TG/next-on-last-page-3
      test('returns null when calling next on last page', () async {
        final channelName = testChannelName('TG-lastPage');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'item'},
              ],
              headers: {},
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();
        expect(result.isLast(), isTrue);

        final nextResult = await result.next();

        // Implementation may return null or empty PaginatedResult
        expect(
          nextResult == null || nextResult.items.isEmpty,
          isTrue,
        );
      });
    });

    group('TG - Pagination preserves authentication', () {
      // UTS: rest/unit/TG/pagination-preserves-auth-4
      test('pagination requests include same auth credentials', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-auth');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=next>; rel="next"',
                },
              );
            } else {
              req.respondWith(200, [
                {'id': 'item2'},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        await page1.next();

        // Both requests should have Authorization header
        expect(capturedRequests[0].headers['Authorization'], isNotNull);
        expect(capturedRequests[1].headers['Authorization'], isNotNull);
        expect(
          capturedRequests[0].headers['Authorization'],
          equals(capturedRequests[1].headers['Authorization']),
        );
      });
    });

    group('TG - Pagination with relative URLs', () {
      // UTS: rest/unit/TG/pagination-relative-urls-5
      test('relative URLs are resolved against base REST host', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-relative');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?page=2>; rel="next"',
                },
              );
            } else {
              req.respondWith(200, [
                {'id': 'item2'},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            endpoint: 'test.example.com',
          ),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        await page1.next();

        // Second request should use the same host
        expect(capturedRequests[1].url.host, equals('test.example.com'));
        expect(
          capturedRequests[1].url.path,
          contains('/channels/$channelName/messages'),
        );
        expect(capturedRequests[1].url.queryParameters['page'], equals('2'));
      });
    });

    group('TG - Pagination with absolute URLs', () {
      // UTS: rest/unit/TG/pagination-presence-results-7
      test('absolute URLs extract path and query, use primary domain',
          () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-absolute');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '<https://other.host.example/channels/$channelName/messages?cursor=abc>; rel="next"',
                },
              );
            } else {
              req.respondWith(200, [
                {'id': 'item2'},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        await page1.next();

        // Path and query params from Link header are followed
        expect(
          capturedRequests[1].url.path,
          contains('/channels/$channelName/messages'),
        );
        expect(
          capturedRequests[1].url.queryParameters['cursor'],
          equals('abc'),
        );
        // But the request goes to the client's primary domain, not the Link host
        expect(
          capturedRequests[1].url.host,
          equals(client.options.primaryDomain),
        );
      });
    });

    group('TG - Multiple Link relations', () {
      // UTS: rest/unit/TG/multiple-link-relations-6
      test('parses multiple Link relations correctly', () async {
        final channelName = testChannelName('TG-multiLink');
        final mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'item1'},
              ],
              headers: {
                'Link':
                    '</channels/$channelName/messages?page=2>; rel="next", </channels/$channelName/messages?page=1>; rel="first", </channels/$channelName/messages?page=5>; rel="last"',
              },
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.history();

        expect(result.hasNext(), isTrue);
        // Implementation should be able to navigate to next page
      });
    });

    group('TG - Pagination includes request headers', () {
      // UTS: rest/unit/TG/pagination-includes-headers-8
      test('pagination requests include standard Ably headers', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-headers');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=next>; rel="next"',
                },
              );
            } else {
              req.respondWith(200, [
                {'id': 'item2'},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();
        await page1.next();

        // Check headers on pagination request
        final nextRequest = capturedRequests[1];
        expect(nextRequest.headers['X-Ably-Version'], isNotNull);
        expect(nextRequest.headers['Ably-Agent'], isNotNull);
        expect(nextRequest.headers['Ably-Agent'], contains('ably-'));
      });
    });

    group('TG - Error handling on next()', () {
      // UTS: rest/unit/TG/error-handling-on-next-9
      test('404 error during pagination raises AblyException', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-error404');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=invalid>; rel="next"',
                },
              );
            } else {
              req.respondWith(404, {
                'error': {
                  'code': 40400,
                  'statusCode': 404,
                  'message': 'Not found',
                },
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();

        await expectLater(
          page1.next(),
          throwsA(
            isA<AblyException>().having(
              (e) => e.statusCode,
              'statusCode',
              equals(404),
            ),
          ),
        );
      });

      // UTS: rest/unit/TG/error-handling-on-next-9.1
      test('500 error during pagination raises AblyException', () async {
        final capturedRequests = <CapturedRequest>[];
        var requestCount = 0;
        final channelName = testChannelName('TG-error500');

        final mockHttp = MockHttpClient(
          onConnectionAttempt: (conn) => conn.respondWithSuccess(),
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            requestCount++;
            if (requestCount == 1) {
              req.respondWith(
                200,
                [
                  {'id': 'item1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/messages?cursor=next>; rel="next"',
                },
              );
            } else {
              req.respondWith(500, {
                'error': {
                  'code': 50000,
                  'statusCode': 500,
                  'message': 'Internal server error',
                },
              });
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.history();

        await expectLater(
          page1.next(),
          throwsA(
            isA<AblyException>().having(
              (e) => e.statusCode,
              'statusCode',
              equals(500),
            ),
          ),
        );
      });
    });
  });
}

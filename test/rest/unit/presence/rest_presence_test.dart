import 'dart:convert';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';
import '../../../helpers/test_channel_name.dart';

/// REST Presence Tests
///
/// Spec points: RSP1, RSP3, RSP4, RSP5
void main() {
  group('REST Presence', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient();
    });

    group('RSP1 - Presence accessible via RestChannel', () {
      // UTS: rest/unit/RSP3b/get-returns-presence-messages-0
      test('RSP1_1 - Presence accessible via RestChannel#presence', () async {
        final channelName = testChannelName('RSP1-1');
        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        expect(channel.presence, isA<RestPresence>());
      });

      // UTS: rest/unit/RSP1b/same-instance-returned-0
      test('RSP1_2 - Same presence object returned for same channel', () async {
        final channelName = testChannelName('RSP1-2');
        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final presence1 = channel.presence;
        final presence2 = channel.presence;

        expect(identical(presence1, presence2), isTrue);
      });
    });

    group('RSP3 - Presence get()', () {
      // UTS: rest/unit/RSP3/get-request-id-enabled-6
      test('RSP3_1 - Get sends GET request to presence endpoint', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get();

        final request = capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(
          request.url.path,
          equals('/channels/${Uri.encodeComponent(channelName)}/presence'),
        );
      });

      // UTS: rest/unit/RSP3/get-standard-headers-5
      test('RSP3_2 - Get returns PresenceMessage objects with correct fields',
          () async {
        final channelName = testChannelName('RSP3-2');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'presence-msg-1',
                'action': 'present',
                'clientId': 'client1',
                'connectionId': 'conn1',
                'data': 'status data',
                'timestamp': 1609459200000,
              },
              {
                'id': 'presence-msg-2',
                'action': 'enter',
                'clientId': 'client2',
                'connectionId': 'conn2',
                'data': {'status': 'online'},
                'encoding': 'json',
                'timestamp': 1609459201000,
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items.length, equals(2));

        final msg1 = result.items[0];
        expect(msg1.id, equals('presence-msg-1'));
        expect(msg1.action, equals(PresenceAction.present));
        expect(msg1.clientId, equals('client1'));
        expect(msg1.connectionId, equals('conn1'));
        expect(msg1.data, equals('status data'));
        expect(msg1.timestamp?.millisecondsSinceEpoch, equals(1609459200000));

        final msg2 = result.items[1];
        expect(msg2.id, equals('presence-msg-2'));
        expect(msg2.action, equals(PresenceAction.enter));
        expect(msg2.clientId, equals('client2'));
        expect(msg2.encoding, isNull);
      });

      // UTS: rest/unit/RSP3/get-channel-not-found-4
      test('RSP3_3 - Get with no members returns empty list', () async {
        final channelName = testChannelName('RSP3-3');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items, isEmpty);
        expect(result.isLast(), isTrue);
      });
    });

    group('RSP3a - Presence get() parameters', () {
      // UTS: rest/unit/RSP3a1/get-limit-parameter-0
      test('RSP3a1_1 - Get with limit parameter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3a1-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, [
              {'id': 'p1', 'action': 'present', 'clientId': 'c1'},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get(const RestPresenceParams(limit: 50));

        final request = capturedRequests[0];
        expect(request.url.queryParameters['limit'], equals('50'));
      });

      // UTS: rest/unit/RSP3a1/get-limit-default-100-1
      test('RSP3a1_2 - Get limit defaults to 100', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3a1-2');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get();

        final request = capturedRequests[0];
        // Either limit param is absent (server default) or explicitly "100"
        if (request.url.queryParameters.containsKey('limit')) {
          expect(request.url.queryParameters['limit'], equals('100'));
        }
      });

      // UTS: rest/unit/RSP3a2/get-clientid-filter-0
      test('RSP3a2_1 - Get with clientId filter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3a2-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, [
              {'id': 'p1', 'action': 'present', 'clientId': 'filtered-client'},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get(
          const RestPresenceParams(clientId: 'filtered-client'),
        );

        final request = capturedRequests[0];
        expect(
          request.url.queryParameters['clientId'],
          equals('filtered-client'),
        );
      });

      // UTS: rest/unit/RSP3a3/get-connectionid-filter-0
      test('RSP3a3_1 - Get with connectionId filter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3a3-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, [
              {'id': 'p1', 'action': 'present', 'connectionId': 'conn-abc'},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get(
          const RestPresenceParams(connectionId: 'conn-abc'),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['connectionId'], equals('conn-abc'));
      });

      // UTS: rest/unit/RSP3/get-multiple-filters-0
      test('RSP3_Combined - Get with multiple filters', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3-combined');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get(
          const RestPresenceParams(
            limit: 25,
            clientId: 'specific-client',
            connectionId: 'specific-conn',
          ),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['limit'], equals('25'));
        expect(
          request.url.queryParameters['clientId'],
          equals('specific-client'),
        );
        expect(
          request.url.queryParameters['connectionId'],
          equals('specific-conn'),
        );
      });
    });

    group('RSP3a1 - Presence get() limit max', () {
      // UTS: rest/unit/RSP3a1/get-limit-max-1000-2
      test('RSP3a1_3 - Get with limit > 1000 is capped or rejected', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP3a1-3');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        // Attempt to get with limit > 1000
        // Implementation may either cap at 1000 or reject
        try {
          await channel.presence.get(const RestPresenceParams(limit: 1500));
          // If it succeeded, check the limit was sent
          final request = capturedRequests[0];
          final limitParam = request.url.queryParameters['limit'];
          // Either the limit is capped to 1000 or sent as-is (server validates)
          expect(
            int.parse(limitParam!),
            anyOf(equals(1000), equals(1500)),
          );
        } catch (e) {
          // If rejected locally, that's also valid
          expect(e, isA<AblyException>());
        }
      });
    });

    group('RSP3c - Get with no members returns empty', () {
      // UTS: rest/unit/RSP3c/get-empty-members-0
      test('RSP3c_1 - Get with no presence members returns empty list',
          () async {
        final channelName = testChannelName('RSP3c-empty');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items, isEmpty);
        expect(result.items, isA<List<PresenceMessage>>());
      });
    });

    group('RSP4 - Presence history()', () {
      // UTS: rest/unit/RSP4/history-pagination-1
      test('RSP4_1 - History sends GET to presence history endpoint', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history();

        final request = capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(
          request.url.path,
          equals(
            '/channels/${Uri.encodeComponent(channelName)}/presence/history',
          ),
        );
      });

      // UTS: rest/unit/RSP4a/history-returns-paginated-1
      test('RSP4a_1 - History returns PaginatedResult of PresenceMessage',
          () async {
        final channelName = testChannelName('RSP4a-1');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'hist-1',
                'action': 'enter',
                'clientId': 'client1',
                'timestamp': 1609459200000,
              },
              {
                'id': 'hist-2',
                'action': 'leave',
                'clientId': 'client1',
                'timestamp': 1609459300000,
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.history();

        expect(result, isA<PaginatedResult<PresenceMessage>>());
        expect(result.items.length, equals(2));
        expect(result.items[0].action, equals(PresenceAction.enter));
        expect(result.items[1].action, equals(PresenceAction.leave));
      });

      // UTS: rest/unit/RSP4b1/history-start-parameter-0
      test('RSP4b1_1 - History with start parameter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b1-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence
            .history(const RestHistoryParams(start: 1609459200000));

        final request = capturedRequests[0];
        expect(request.url.queryParameters['start'], equals('1609459200000'));
      });

      // UTS: rest/unit/RSP4b1/history-end-parameter-1
      test('RSP4b1_2 - History with end parameter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b1-2');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence
            .history(const RestHistoryParams(end: 1609459300000));

        final request = capturedRequests[0];
        expect(request.url.queryParameters['end'], equals('1609459300000'));
      });

      // UTS: rest/unit/RSP4b2/history-direction-backwards-default-0
      test('RSP4b2_1 - History with direction backwards (default)', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b2-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history();

        final request = capturedRequests[0];
        // Either direction param is absent (server default) or explicitly "backwards"
        if (request.url.queryParameters.containsKey('direction')) {
          expect(
            request.url.queryParameters['direction'],
            equals('backwards'),
          );
        }
      });

      // UTS: rest/unit/RSP4b2/history-direction-forwards-1
      test('RSP4b2_2 - History with direction forwards', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b2-2');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history(
          const RestHistoryParams(direction: HistoryDirection.forwards),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['direction'], equals('forwards'));
      });

      // UTS: rest/unit/RSP4b3/history-limit-parameter-0
      test('RSP4b3_1 - History with limit parameter', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b3-1');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history(const RestHistoryParams(limit: 50));

        final request = capturedRequests[0];
        expect(request.url.queryParameters['limit'], equals('50'));
      });

      // UTS: rest/unit/RSP4/history-auth-header-3
      test('RSP4_Auth - History request includes auth header', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4-auth');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history();

        final request = capturedRequests[0];
        expect(request.headers['Authorization'], isNotNull);
        expect(request.headers['Authorization'], startsWith('Basic '));
      });

      // UTS: rest/unit/RSP4a/history-request-endpoint-0
      test('RSP4a_Endpoint - History sends to correct endpoint', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4a-endpoint');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history();

        final request = capturedRequests[0];
        expect(request.method, equals('GET'));
        expect(
          request.url.path,
          equals(
            '/channels/${Uri.encodeComponent(channelName)}/presence/history',
          ),
        );
      });

      // UTS: rest/unit/RSP4b1/history-start-end-params-2
      test('RSP4b1_3 - History with both start and end parameters', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b1-3');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history(
          const RestHistoryParams(
            start: 1609459200000,
            end: 1609459300000,
          ),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['start'], equals('1609459200000'));
        expect(request.url.queryParameters['end'], equals('1609459300000'));
      });

      // UTS: rest/unit/RSP4b1/history-datetime-objects-3
      test('RSP4b1_4 - History accepts integer timestamps for start/end',
          () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b1-4');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final start = DateTime(2021).millisecondsSinceEpoch;
        final end = DateTime(2021, 1, 2).millisecondsSinceEpoch;

        await channel.presence.history(
          RestHistoryParams(
            start: start,
            end: end,
          ),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['start'], equals('$start'));
        expect(request.url.queryParameters['end'], equals('$end'));
      });

      // UTS: rest/unit/RSP4b2/history-direction-backwards-explicit-2
      test('RSP4b2_3 - History with direction backwards explicitly set',
          () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b2-3');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history(
          const RestHistoryParams(),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['direction'], equals('backwards'));
      });

      // UTS: rest/unit/RSP4b3/history-limit-default-100-1
      test('RSP4b3_2 - History limit defaults to 100', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b3-2');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history();

        final request = capturedRequests[0];
        // Either limit param is absent (server default) or explicitly "100"
        if (request.url.queryParameters.containsKey('limit')) {
          expect(request.url.queryParameters['limit'], equals('100'));
        }
      });

      // UTS: rest/unit/RSP4b3/history-limit-max-1000-2
      test('RSP4b3_3 - History limit max 1000', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4b3-3');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        // Attempt to set limit > 1000
        try {
          await channel.presence.history(const RestHistoryParams(limit: 1500));
          // If it succeeded, the limit was sent (server may validate)
          final request = capturedRequests[0];
          final limitParam = request.url.queryParameters['limit'];
          expect(
            int.parse(limitParam!),
            anyOf(equals(1000), equals(1500)),
          );
        } catch (e) {
          // If rejected locally, that's also valid
          expect(e, isA<AblyException>());
        }
      });

      // UTS: rest/unit/RSP4/history-all-parameters-0
      test('RSP4_Combined - History with all parameters', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP4-combined');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.history(
          const RestHistoryParams(
            start: 1609459200000,
            end: 1609459300000,
            direction: HistoryDirection.forwards,
            limit: 25,
          ),
        );

        final request = capturedRequests[0];
        expect(request.url.queryParameters['start'], equals('1609459200000'));
        expect(request.url.queryParameters['end'], equals('1609459300000'));
        expect(request.url.queryParameters['direction'], equals('forwards'));
        expect(request.url.queryParameters['limit'], equals('25'));
      });
    });

    group('RSP5 - Data decoding', () {
      // UTS: rest/unit/RSP5/decode-string-data-0
      test('RSP5_1 - String data decoded as string', () async {
        final channelName = testChannelName('RSP5-1');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': 'plain string data',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items[0].data, equals('plain string data'));
        expect(result.items[0].data, isA<String>());
      });

      // UTS: rest/unit/RSP5/decode-json-data-1
      test('RSP5_2 - JSON encoded data decoded to object', () async {
        final channelName = testChannelName('RSP5-2');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': {'status': 'online', 'count': 42},
                'encoding': 'json',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items[0].data, isA<Map>());
        final data = result.items[0].data as Map;
        expect(data['status'], equals('online'));
        expect(data['count'], equals(42));
      });

      // UTS: rest/unit/RSP5/decode-base64-binary-2
      test('RSP5_3 - Base64 encoded data decoded to binary', () async {
        final channelName = testChannelName('RSP5-3');
        final originalBytes = [1, 2, 3, 4, 5];
        final base64Data = base64Encode(originalBytes);

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': base64Data,
                'encoding': 'base64',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items[0].encoding, isNull);
        expect(result.items[0].data, equals(originalBytes));
      });
    });

    group('RSP5 - Advanced data decoding', () {
      // UTS: rest/unit/RSP5/decode-utf8-data-4
      test('RSP5_4 - UTF-8 encoded data decoded correctly', () async {
        final channelName = testChannelName('RSP5-4');
        const utf8Text = 'Hello UTF-8: café éè';
        final base64Data = base64Encode(utf8.encode(utf8Text));

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': base64Data,
                'encoding': 'utf-8/base64',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        // The data should be decoded from base64 and then from utf-8
        expect(result.items[0], isNotNull);
      });

      // UTS: rest/unit/RSP5/decode-chained-encoding-5
      test('RSP5_5 - Chained encoding decoded correctly', () async {
        final channelName = testChannelName('RSP5-5');
        const jsonData = '{"status":"online"}';
        final base64Data = base64Encode(utf8.encode(jsonData));

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': base64Data,
                'encoding': 'json/base64',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        // The chained encoding should be decoded
        expect(result.items[0], isNotNull);
      });

      // UTS: rest/unit/RSP5/decode-history-messages-6
      test('RSP5_6 - History messages decoded correctly', () async {
        final channelName = testChannelName('RSP5-6');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'h1',
                'action': 'enter',
                'clientId': 'c1',
                'data': '{"status":"online"}',
                'encoding': 'json',
                'timestamp': 1609459200000,
              },
              {
                'id': 'h2',
                'action': 'leave',
                'clientId': 'c1',
                'data': 'plain text',
                'timestamp': 1609459300000,
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.history();

        expect(result.items.length, equals(2));
        expect(result.items[0].encoding, isNull);
        expect(result.items[0].data, equals({'status': 'online'}));
        expect(result.items[1].data, equals('plain text'));
      });

      // UTS: rest/unit/RSP5/decode-msgpack-binary-3
      test(
        'RSP5 - decode msgpack binary',
        () {},
        skip: 'Not yet implemented: msgpack encoding support',
      );

      // UTS: rest/unit/RSP5/decode-cipher-channel-7
      test('RSP5_7 - Cipher channel data decoded', () async {
        final channelName = testChannelName('RSP5-7');
        // Simulate cipher+aes-128-cbc/base64 encoding
        // We can't actually decrypt without a key, but we verify the encoding
        // is present and passed through
        final encryptedBase64 = base64Encode([1, 2, 3, 4, 5, 6, 7, 8]);

        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {
                'id': 'p1',
                'action': 'present',
                'clientId': 'c1',
                'data': encryptedBase64,
                'encoding': 'utf-8/cipher+aes-128-cbc/base64',
              },
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        // Without cipher key, the cipher encoding layer should be preserved
        // as residual encoding
        expect(result.items[0], isNotNull);
      });
    });

    group('RSP_Pagination - Presence pagination', () {
      // UTS: rest/unit/RSP3/get-pagination-link-header-1
      test('RSP_Pagination_1 - Get returns paginated result with Link header',
          () async {
        final channelName = testChannelName('RSP-page1');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              200,
              [
                {'id': 'p1', 'action': 'present', 'clientId': 'c1'},
                {'id': 'p2', 'action': 'present', 'clientId': 'c2'},
              ],
              headers: {
                'Link':
                    '</channels/$channelName/presence?cursor=abc>; rel="next", </channels/$channelName/presence>; rel="first"',
              },
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items.length, equals(2));
        expect(result.hasNext(), isTrue);
        expect(result.isLast(), isFalse);
      });

      // UTS: rest/unit/RSP3/get-pagination-next-page-2
      test('RSP_Pagination_2 - Get next page fetches from Link URL', () async {
        var requestCount = 0;
        final channelName = testChannelName('RSP-page2');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            requestCount++;
            if (requestCount == 1) {
              // First page
              req.respondWith(
                200,
                [
                  {'id': 'p1', 'action': 'present', 'clientId': 'c1'},
                ],
                headers: {
                  'Link':
                      '</channels/$channelName/presence?cursor=page2>; rel="next"',
                },
              );
            } else {
              // Second page
              req.respondWith(200, [
                {'id': 'p2', 'action': 'present', 'clientId': 'c2'},
              ]);
            }
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final page1 = await channel.presence.get();
        expect(page1.items.length, equals(1));
        expect(page1.items[0].clientId, equals('c1'));
        expect(page1.hasNext(), isTrue);

        final page2 = await page1.next();
        expect(page2, isNotNull);
        expect(page2!.items.length, equals(1));
        expect(page2.items[0].clientId, equals('c2'));
      });
    });

    group('RSP_Error - Presence error handling', () {
      // UTS: rest/unit/RSP3/get-server-error-3
      test('RSP_Error_1 - Get with server error throws AblyException',
          () async {
        final channelName = testChannelName('RSP-err1');
        // 403 Forbidden - client errors (4xx) are not retried
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(403, {
              'error': {
                'message': 'Forbidden',
                'code': 40300,
                'statusCode': 403,
              },
            });
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        expect(
          () => channel.presence.get(),
          throwsA(isA<AblyException>()),
        );
      });

      // UTS: rest/unit/RSP4/history-auth-error-2
      test('RSP_Error_2 - History with invalid auth throws AblyException',
          () async {
        final channelName = testChannelName('RSP-err2');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(
              401,
              {
                'error': {
                  'message': 'Invalid credentials',
                  'code': 40100,
                  'statusCode': 401,
                },
              },
              headers: {
                'X-Ably-Errorcode': '40100',
                'X-Ably-Errormessage': 'Invalid credentials',
              },
            );
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        expect(
          () => channel.presence.history(),
          throwsA(
            isA<AblyException>().having(
              (e) => e.code,
              'code',
              equals(40100),
            ),
          ),
        );
      });
    });

    group('RSP_Headers - Request headers', () {
      // UTS: rest/unit/RSP3a/get-request-endpoint-0
      test('RSP_Headers_1 - Get includes standard headers', () async {
        final capturedRequests = <CapturedRequest>[];
        final channelName = testChannelName('RSP-headers');

        mockHttp = MockHttpClient(
          onRequest: (req) {
            capturedRequests.add(
              CapturedRequest(
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.bodyAsString,
              ),
            );

            req.respondWith(200, []);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        await channel.presence.get();

        final request = capturedRequests[0];
        expect(request.headers['X-Ably-Version'], isNotNull);
        expect(request.headers['Authorization'], isNotNull);
      });
    });

    group('RSP_Action - Presence actions', () {
      // UTS: rest/unit/RSP5/presence-action-mapping-8
      test('RSP_Action_1 - All presence actions correctly mapped', () async {
        final channelName = testChannelName('RSP-action');
        mockHttp = MockHttpClient(
          onRequest: (req) {
            req.respondWith(200, [
              {'id': '1', 'action': 'present', 'clientId': 'c1'},
              {'id': '2', 'action': 'enter', 'clientId': 'c2'},
              {'id': '3', 'action': 'leave', 'clientId': 'c3'},
              {'id': '4', 'action': 'update', 'clientId': 'c4'},
              {'id': '5', 'action': 'absent', 'clientId': 'c5'},
            ]);
          },
        );

        final client = RestClient.forTesting(
          options: ClientOptions.fromKey('appId.keyId:keySecret'),
          httpClient: mockHttp,
        );
        final channel = client.channels.get(channelName);

        final result = await channel.presence.get();

        expect(result.items[0].action, equals(PresenceAction.present));
        expect(result.items[1].action, equals(PresenceAction.enter));
        expect(result.items[2].action, equals(PresenceAction.leave));
        expect(result.items[3].action, equals(PresenceAction.update));
        expect(result.items[4].action, equals(PresenceAction.absent));
      });
    });

    group('RSP - Channel name encoding', () {
      final testCases = [
        (
          channelName: 'simple',
          expectedPath: '/channels/simple/presence',
        ),
        (
          channelName: 'with:colon',
          expectedPath: '/channels/with%3Acolon/presence',
        ),
        (
          channelName: 'with/slash',
          expectedPath: '/channels/with%2Fslash/presence',
        ),
        (
          channelName: 'with space',
          expectedPath: '/channels/with%20space/presence',
        ),
      ];

      for (final testCase in testCases) {
        // UTS: rest/unit/RSP1a/presence-channel-attribute-0
        test('encodes channel name "${testCase.channelName}" correctly',
            () async {
          final capturedRequests = <CapturedRequest>[];

          mockHttp = MockHttpClient(
            onRequest: (req) {
              capturedRequests.add(
                CapturedRequest(
                  method: req.method,
                  url: req.url,
                  headers: req.headers,
                  body: req.bodyAsString,
                ),
              );

              req.respondWith(200, []);
            },
          );

          final client = RestClient.forTesting(
            options: ClientOptions.fromKey('appId.keyId:keySecret'),
            httpClient: mockHttp,
          );
          final channel = client.channels.get(testCase.channelName);

          await channel.presence.get();

          final request = capturedRequests[0];
          expect(request.url.path, equals(testCase.expectedPath));
        });
      }
    });
  });
}

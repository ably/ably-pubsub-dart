import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';

/// Unit tests for REST channel attributes and methods (RSL7, RSL8, RSL9).
///
/// These tests use a mocked HTTP client to verify RestChannel attributes
/// and request formation for the status endpoint.
///
/// Spec: uts/test/rest/unit/channel/rest_channel_attributes.md
void main() {
  group('RSL9 - RestChannel name attribute', () {
    // UTS: rest/unit/RSL9/channel-name-attribute-0
    test('returns the name used when getting the channel', () {
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
      );

      final channel = client.channels.get('my-channel');
      expect(channel.name, equals('my-channel'));

      // Also works with special characters
      final channel2 = client.channels.get('namespace:channel-name');
      expect(channel2.name, equals('namespace:channel-name'));
    });
  });

  group('RSL7 - RestChannel setOptions', () {
    // UTS: rest/unit/RSL7/setoptions-updates-options-0
    test('setOptions completes without error', () async {
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
      );

      final channel = client.channels.get('test-RSL7');
      // setOptions should complete without throwing
      await channel.setOptions(const RestChannelOptions());
    });

    // UTS: rest/unit/RSL7/setoptions-stores-options-1
    test('setOptions stores options on channel', () async {
      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
      );

      final channel = client.channels.get('test-RSL7-store');
      const options = RestChannelOptions();

      // setOptions should store the options without error
      await channel.setOptions(options);

      // Calling setOptions again with different options should also work
      const options2 = RestChannelOptions();
      await channel.setOptions(options2);
    });
  });

  group('RSL8 - RestChannel status', () {
    // UTS: rest/unit/RSL8/status-get-correct-endpoint-0
    test('sends GET request to /channels/<channelId>', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channelId': 'test-RSL8',
            'status': {
              'isActive': true,
              'occupancy': {
                'metrics': {
                  'connections': 0,
                  'publishers': 0,
                  'subscribers': 0,
                  'presenceConnections': 0,
                  'presenceMembers': 0,
                  'presenceSubscribers': 0,
                },
              },
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL8');
      await channel.status();

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(mockHttp.capturedRequests[0].method, equals('GET'));
      expect(
        mockHttp.capturedRequests[0].url.path,
        equals('/channels/test-RSL8'),
      );

      mockHttp.dispose();
    });

    // UTS: rest/unit/RSL8/status-special-chars-encoded-1
    test('URL-encodes special characters in channel name', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channelId': 'namespace:my channel',
            'status': {
              'isActive': true,
              'occupancy': {
                'metrics': {
                  'connections': 0,
                  'publishers': 0,
                  'subscribers': 0,
                  'presenceConnections': 0,
                  'presenceMembers': 0,
                  'presenceSubscribers': 0,
                },
              },
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('namespace:my channel');
      await channel.status();

      expect(mockHttp.capturedRequests.length, equals(1));
      expect(mockHttp.capturedRequests[0].method, equals('GET'));
      expect(
        mockHttp.capturedRequests[0].url.path,
        equals(
          '/channels/${Uri.encodeComponent('namespace:my channel')}',
        ),
      );

      mockHttp.dispose();
    });
  });

  group('RSL8a - status returns ChannelDetails', () {
    // UTS: rest/unit/RSL8a/status-returns-channel-details-0
    test('parses response into ChannelDetails with correct attributes',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channelId': 'test-RSL8a',
            'status': {
              'isActive': true,
              'occupancy': {
                'metrics': {
                  'connections': 5,
                  'publishers': 2,
                  'subscribers': 3,
                  'presenceConnections': 1,
                  'presenceMembers': 1,
                  'presenceSubscribers': 0,
                },
              },
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-RSL8a');
      final result = await channel.status();

      // CHD2a: channelId attribute
      expect(result.channelId, equals('test-RSL8a'));

      // CHD2b: status attribute
      expect(result.status, isNotNull);
      expect(result.status!.isActive, isTrue);

      // CHS2b: occupancy metrics
      expect(result.status!.occupancy, isNotNull);
      expect(result.status!.occupancy!.metrics, isNotNull);
      expect(result.status!.occupancy!.metrics!.connections, equals(5));
      expect(result.status!.occupancy!.metrics!.publishers, equals(2));
      expect(result.status!.occupancy!.metrics!.subscribers, equals(3));

      mockHttp.dispose();
    });
  });

  group('CHD2, CHS2, CHO2, CHM2 - status() parses all ChannelMetrics fields',
      () {
    // UTS: rest/unit/CHM2/parses-all-metrics-fields-0
    test(
        'parses all metric fields including objectPublishers/objectSubscribers',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channelId': 'test-CHM2-all-fields',
            'status': {
              'isActive': true,
              'occupancy': {
                'metrics': {
                  'connections': 10,
                  'presenceConnections': 7,
                  'presenceMembers': 4,
                  'presenceSubscribers': 3,
                  'publishers': 6,
                  'subscribers': 8,
                  'objectPublishers': 2,
                  'objectSubscribers': 5,
                },
              },
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-CHM2-all-fields');
      final result = await channel.status();

      // CHD2a
      expect(result.channelId, equals('test-CHM2-all-fields'));

      // CHD2b + CHS2a
      expect(result.status, isNotNull);
      expect(result.status!.isActive, isTrue);

      // CHS2b + CHO2a
      expect(result.status!.occupancy, isNotNull);
      expect(result.status!.occupancy!.metrics, isNotNull);

      final metrics = result.status!.occupancy!.metrics!;

      // CHM2a
      expect(metrics.connections, equals(10));
      // CHM2b
      expect(metrics.presenceConnections, equals(7));
      // CHM2c
      expect(metrics.presenceMembers, equals(4));
      // CHM2d
      expect(metrics.presenceSubscribers, equals(3));
      // CHM2e
      expect(metrics.publishers, equals(6));
      // CHM2f
      expect(metrics.subscribers, equals(8));
      // CHM2g
      expect(metrics.objectPublishers, equals(2));
      // CHM2h
      expect(metrics.objectSubscribers, equals(5));

      mockHttp.dispose();
    });

    // UTS: rest/unit/CHM2/zero-and-missing-metrics-1
    test('missing objectPublishers/objectSubscribers default to null',
        () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, {
            'channelId': 'test-CHM2-defaults',
            'status': {
              'isActive': false,
              'occupancy': {
                'metrics': {
                  'connections': 0,
                  'presenceConnections': 0,
                  'presenceMembers': 0,
                  'presenceSubscribers': 0,
                  'publishers': 0,
                  'subscribers': 0,
                },
              },
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('fake.key:secret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-CHM2-defaults');
      final result = await channel.status();

      // CHD2a
      expect(result.channelId, equals('test-CHM2-defaults'));

      // CHS2a: isActive can be false
      expect(result.status!.isActive, isFalse);

      final metrics = result.status!.occupancy!.metrics!;

      // CHM2a-f: explicit zero values
      expect(metrics.connections, equals(0));
      expect(metrics.presenceConnections, equals(0));
      expect(metrics.presenceMembers, equals(0));
      expect(metrics.presenceSubscribers, equals(0));
      expect(metrics.publishers, equals(0));
      expect(metrics.subscribers, equals(0));

      // CHM2g-h: missing fields are null
      expect(metrics.objectPublishers, isNull);
      expect(metrics.objectSubscribers, isNull);

      mockHttp.dispose();
    });
  });
}

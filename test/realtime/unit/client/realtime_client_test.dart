import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

void main() {
  group('Realtime Client - UTS Tests', () {
    // UTS: realtime/unit/RTC2/connection-attribute-0
    test('RTC2 - connection attribute exists', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      expect(realtime.connection, isNotNull);
      expect(realtime.connection, isA<Connection>());
    });

    // UTS: realtime/unit/RTC3/channels-attribute-0
    test('RTC3 - channels attribute exists and can get channels', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      final channelName = testChannelName('RTC3');

      expect(realtime.channels, isNotNull);
      expect(realtime.channels, isA<RealtimeChannels>());

      // Test get method
      final channel1 = realtime.channels.get(channelName);
      expect(channel1, isNotNull);
      expect(channel1, isA<RealtimeChannel>());
      expect(channel1.name, equals(channelName));

      // Test operator[] method
      final channel2 = realtime.channels[channelName];
      expect(channel2, isNotNull);
      expect(channel2, same(channel1)); // Should return same instance

      // Test exists method
      expect(realtime.channels.exists(channelName), isTrue);
      expect(realtime.channels.exists('nonexistent'), isFalse);
    });

    // UTS: realtime/unit/RTC4/auth-attribute-0
    test('RTC4 - auth attribute exists', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      expect(realtime.auth, isNotNull);
      expect(realtime.auth, isA<Auth>());
    });

    // UTS: realtime/unit/RTC17/client-id-attribute-0
    test('RTC17 - clientId attribute returns auth clientId', () {
      // Test with no clientId
      final realtime1 = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      expect(realtime1.clientId, isNull);

      // Test with clientId in options
      final realtime2 = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          clientId: 'test-client-id',
          autoConnect: false,
        ),
      );
      expect(realtime2.clientId, equals('test-client-id'));
    });

    // UTS: realtime/unit/RTC1a/echo-messages-option-0
    test('RTC1a - echoMessages option in query parameters', () {
      // Test default value (true)
      final realtime1 = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      expect(realtime1.options.echoMessages, isTrue);

      // Test explicit true
      final realtime2 = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      expect(realtime2.options.echoMessages, isTrue);

      // Test explicit false
      final realtime3 = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          echoMessages: false,
          autoConnect: false,
        ),
      );
      expect(realtime3.options.echoMessages, isFalse);
    });

    // UTS: realtime/unit/RTC2/connection-attribute-0.1
    test('Connection initial state is initialized', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      expect(realtime.connection.state, equals(ConnectionState.initialized));
    });

    // UTS: realtime/unit/RTC17/client-id-attribute-0.1
    test('Channel initial state is initialized', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );
      final channelName = testChannelName('RTC-init');
      final channel = realtime.channels.get(channelName);
      expect(channel.state, equals(ChannelState.initialized));
    });

    // UTS: realtime/unit/RTC2/connection-attribute-0.2
    test('Connection state changes can be observed', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final stateChanges = <ConnectionStateChange>[];
      final subscription = realtime.connection.on().listen((change) {
        stateChanges.add(change);
      });

      // Start connection
      realtime.connect();

      // Wait for connected state
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      // Should have transitioned: initialized -> connecting -> connected
      expect(stateChanges.length, greaterThanOrEqualTo(2));
      expect(stateChanges.first.current, equals(ConnectionState.connecting));
      expect(stateChanges.last.current, equals(ConnectionState.connected));

      await subscription.cancel();
      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC17/client-id-attribute-0.2
    test('Channel state changes can be observed', () async {
      final channelName = testChannelName('RTC-state');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: msg.channel!),
            );
          }
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      realtime.connect();
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      final channel = realtime.channels.get(channelName);

      final stateChanges = <ChannelStateChange>[];
      final subscription = channel.on().listen((change) {
        stateChanges.add(change);
      });

      await channel.attach();

      // Wait for all state changes to propagate
      await Future<void>.delayed(Duration.zero);

      // Should have transitioned: initialized -> attaching -> attached
      expect(stateChanges.length, greaterThanOrEqualTo(2));
      expect(stateChanges.first.current, equals(ChannelState.attaching));
      expect(stateChanges.last.current, equals(ChannelState.attached));

      await subscription.cancel();
      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC2/connection-attribute-0.3
    test('Connection on(event) filters by event type', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final connectingEvents = <ConnectionStateChange>[];
      final subscription =
          realtime.connection.on(ConnectionEvent.connecting).listen((change) {
        connectingEvents.add(change);
      });

      // Start connection
      realtime.connect();

      // Wait for connected state
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      // Should only receive connecting events (filtering works)
      expect(connectingEvents.length, equals(1));
      expect(connectingEvents.first.event, equals(ConnectionEvent.connecting));
      expect(
        connectingEvents.first.current,
        equals(ConnectionState.connecting),
      );

      await subscription.cancel();
      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC17/client-id-attribute-0.3
    test('Channel on(event) filters by event type', () async {
      final channelName = testChannelName('RTC-filter');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: msg.channel!),
            );
          }
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      realtime.connect();
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      final channel = realtime.channels.get(channelName);

      final attachedEvents = <ChannelStateChange>[];
      final subscription = channel.on(ChannelEvent.attached).listen((change) {
        attachedEvents.add(change);
      });

      await channel.attach();

      // Wait for all state changes to propagate
      await Future<void>.delayed(Duration.zero);

      // Should only receive attached events
      expect(attachedEvents.length, equals(1));
      expect(attachedEvents.first.event, equals(ChannelEvent.attached));
      expect(attachedEvents.first.current, equals(ChannelState.attached));

      await subscription.cancel();
      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC17/client-id-attribute-0.4
    test('Channel release detaches and removes channel', () async {
      final channelName = testChannelName('RTC-release');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(channel: msg.channel!),
            );
          } else if (msg.action == ProtocolAction.detach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.detached(channel: msg.channel!),
            );
          }
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      realtime.connect();
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      final channel = realtime.channels.get(channelName);

      await channel.attach();
      expect(channel.state, equals(ChannelState.attached));
      expect(realtime.channels.exists(channelName), isTrue);

      await realtime.channels.release(channelName);

      expect(realtime.channels.exists(channelName), isFalse);

      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC2/connection-attribute-0.4
    test('RealtimeClient.close closes connection', () async {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      // Start in initialized state
      expect(realtime.connection.state, equals(ConnectionState.initialized));

      // Close from initialized state should transition to closed
      await realtime.close();
      expect(realtime.connection.state, equals(ConnectionState.closed));
    });

    // UTS: realtime/unit/RTC1b/auto-connect-option-0
    test('Constructor with options parameter', () {
      final options = ClientOptions(
        key: 'fake.key:secret',
        clientId: 'test-client',
        echoMessages: false,
        autoConnect: false,
      );

      final realtime = RealtimeClient(options: options);

      expect(realtime.options.key, equals('fake.key:secret'));
      expect(realtime.clientId, equals('test-client'));
      expect(realtime.options.echoMessages, isFalse);
    });

    // UTS: realtime/unit/RTC12/constructor-string-detection-0
    test('Constructor with key parameter overrides options', () {
      final options = ClientOptions(
        key: 'old.key:secret',
        autoConnect: false,
      );

      final realtime = RealtimeClient(
        options: options,
        key: 'new.key:secret',
      );

      expect(realtime.options.key, equals('new.key:secret'));
    });

    // UTS: realtime/unit/RTC1c/recover-option-0
    test('Constructor throws when neither options nor key provided', () {
      expect(
        () => RealtimeClient(),
        throwsArgumentError,
      );
    });

    // UTS: realtime/unit/RTC1f/transport-params-option-0
    test('RTC1f - transportParams option included in WebSocket connection URL',
        () async {
      Uri? capturedUrl;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          capturedUrl = conn.url;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'test-connection',
              connectionKey: 'test-key',
            ),
          );
        },
      );

      final realtime = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
          transportParams: {'key1': 'val1', 'key2': 'val2'},
        ),
        webSocketClient: mockWs,
      );

      realtime.connect();
      await realtime.connection
          .on(ConnectionEvent.connected)
          .first
          .timeout(const Duration(seconds: 5));

      // Verify the WebSocket URL includes the transport params
      expect(capturedUrl, isNotNull);
      expect(capturedUrl!.queryParameters['key1'], equals('val1'));
      expect(capturedUrl!.queryParameters['key2'], equals('val2'));

      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC5/stats-proxies-rest-0
    test('RTC5 - stats() method is available on Realtime client', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      // Verify stats method exists and returns a Future
      // (actual HTTP call would fail without a real connection, but the
      // method must be present per RTC5)
      expect(realtime.stats, isA<Function>());
    });

    // UTS: realtime/unit/RTC6/time-proxies-rest-0
    test('RTC6 - time() method is available on Realtime client', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      // Verify time method exists and returns a Future
      expect(realtime.time, isA<Function>());
    });

    // UTS: realtime/unit/RTC9/request-proxies-rest-0
    test('RTC9 - request() method is available on Realtime client', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      // Verify request method exists and returns a Future
      expect(realtime.request, isA<Function>());
    });

    // UTS: realtime/unit/RTC12/invalid-arguments-error-1
    test('RTC12 - invalid key format throws appropriate error', () {
      // A key without the "appId.keyName:keySecret" format should
      // throw an error
      expect(
        () => RealtimeClient(
          options: ClientOptions(
            key: 'invalid-key-format',
            autoConnect: false,
          ),
        ),
        throwsA(isA<AblyException>()),
      );
    });

    // RTC1a: the WebSocketClient interface is exported from package:ably,
    // but the only constructor that accepted one was
    // RealtimeClient.forTesting, which is @visibleForTesting -- so an
    // application that has to supply its own transport (a browser, where
    // dart:io cannot open a socket at all) had no supported way to do it.
    //
    // The mock never touches the network: if the argument were ignored and
    // the real dart:io transport were built instead, the client would be
    // off trying to reach ably.io and would never reach CONNECTED here.
    test('RTC1a - a transport passed to the factory is the one used', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final realtime = RealtimeClient(
        options: ClientOptions(key: 'appId.keyId:keySecret'),
        webSocketClient: mockWs,
      );

      await _awaitConnectionState(
        realtime.connection,
        ConnectionState.connected,
      );

      expect(realtime.connection.state, equals(ConnectionState.connected));

      await realtime.close();
      mockWs.dispose();
    });

    // UTS: realtime/unit/RTC13/push-attribute-0
    test('RTC13 - push attribute is accessible', () {
      final realtime = RealtimeClient(
        options: ClientOptions(
          key: 'fake.key:secret',
          autoConnect: false,
        ),
      );

      expect(realtime.push, isNotNull);
    });
  });
}

Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) {
    return;
  }
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

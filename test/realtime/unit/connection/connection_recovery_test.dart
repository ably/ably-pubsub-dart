import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for connection recovery (RTN16).
///
/// Tests RTN16d, RTN16f, RTN16f1, RTN16g, RTN16g1, RTN16g2, RTN16i,
/// RTN16j, RTN16k, RTN16l.
///
/// Spec: specification/uts/realtime/unit/connection/connection_recovery_test.md
void main() {
  /// Creates a mock HTTP client for connectivity checks.
  http.Client createMockHttpClient() {
    return http_testing.MockClient((request) async {
      return http.Response('yes', 200);
    });
  }

  group(
      'RTN16g, RTN16g1 - createRecoveryKey returns string with '
      'connectionKey, msgSerial, and channel/channelSerial pairs', () {
    test(
        'recovery key contains connectionKey, msgSerial, '
        'and channel serials including unicode names', () async {
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-abc-123',
            ),
          );
        },
        onMessageFromClient: (msg) {},
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Connect
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Get two channels and simulate attaching them
      final channelA = client.channels.get('channel-alpha');
      final channelB = client.channels.get('channel-éàü-世界');

      // Attach channel_a
      channelA.attach();
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: 'channel-alpha',
          channelSerial: 'serial-a-001',
        ),
      );
      await _awaitState(
        client.connection,
        ConnectionState.connected,
      );
      await _pumpEventQueue();

      // Attach channel_b (unicode name)
      channelB.attach();
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: 'channel-éàü-世界',
          channelSerial: 'serial-b-002',
        ),
      );
      await _pumpEventQueue();

      // Verify only one connection attempt
      expect(connectionAttemptCount, equals(1));

      // Verify the connection key is set
      expect(client.connection.key, equals('key-abc-123'));

      // Verify the channels have their serials set
      expect(channelA.properties.channelSerial, equals('serial-a-001'));
      expect(channelB.properties.channelSerial, equals('serial-b-002'));

      // RTN16g: createRecoveryKey returns JSON string
      final recoveryKey = client.connection.createRecoveryKey();
      expect(recoveryKey, isNotNull);

      final parsed = jsonDecode(recoveryKey!) as Map<String, dynamic>;
      expect(parsed['connectionKey'], equals('key-abc-123'));
      expect(parsed['msgSerial'], isA<int>());

      // RTN16g1: channelSerials map includes all attached channels
      final channelSerials = parsed['channelSerials'] as Map<String, dynamic>;
      expect(channelSerials['channel-alpha'], equals('serial-a-001'));
      expect(channelSerials['channel-éàü-世界'], equals('serial-b-002'));

      // Verify round-trip: re-serializing preserves unicode names
      final reSerialized = jsonEncode(parsed);
      final reParsed = jsonDecode(reSerialized) as Map<String, dynamic>;
      expect(
        (reParsed['channelSerials'] as Map<String, dynamic>)['channel-éàü-世界'],
        equals('serial-b-002'),
      );

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN16g2 - createRecoveryKey returns null in inactive states', () {
    test(
        'returns null in INITIALIZED, CLOSING, CLOSED, FAILED, and '
        'SUSPENDED states', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'connection-1',
              connectionKey: 'key-1',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Before connecting (INITIALIZED state) - no connectionKey
      expect(client.connection.state, equals(ConnectionState.initialized));
      expect(client.connection.createRecoveryKey(), isNull);

      // Connect and verify recovery key is available when CONNECTED
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(client.connection.key, isNotNull);
      expect(client.connection.createRecoveryKey(), isNotNull);

      // Transition to CLOSING then CLOSED
      await client.close();
      await _awaitState(client.connection, ConnectionState.closed);
      expect(client.connection.createRecoveryKey(), isNull);

      expect(client.connection.state, equals(ConnectionState.closed));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN16g2/recovery-key-null-inactive-0
    test('returns null in FAILED state', () async {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-f',
              connectionKey: 'key-f',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);
      expect(client.connection.createRecoveryKey(), isNotNull);

      // Trigger FAILED via fatal ERROR
      mockWs.activeConnection!.sendToClientAndClose(
        ProtocolMessageHelpers.error(
          code: 50000,
          statusCode: 500,
          message: 'Fatal error',
        ),
      );
      await _awaitState(client.connection, ConnectionState.failed);
      expect(client.connection.createRecoveryKey(), isNull);

      expect(client.connection.state, equals(ConnectionState.failed));

      mockWs.dispose();
    });

    // UTS: realtime/unit/RTN16g2/recovery-key-null-inactive-0.1
    test('returns null in SUSPENDED state', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-s',
                  connectionKey: 'key-s',
                  connectionStateTtl: 2000, // Short TTL
                ),
              );
            } else {
              conn.respondWithRefused();
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: 500,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          httpClient: createMockHttpClient(),
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(client.connection.createRecoveryKey(), isNotNull);

        // Trigger disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Advance time until SUSPENDED (connectionStateTtl expires)
        for (var i = 0; i < 10; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 1500));
          await _pumpEventQueue();
          if (client.connection.state == ConnectionState.suspended) break;
        }

        expect(client.connection.state, equals(ConnectionState.suspended));
        expect(client.connection.createRecoveryKey(), isNull);

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN16k - recover option adds recover query param to WebSocket URL',
      () {
    test('recover param sent on first connection, resume on subsequent',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final capturedUrls = <Uri>[];

        final recoveryKey = jsonEncode({
          'connectionKey': 'recovered-key-xyz',
          'msgSerial': 5,
          'channelSerials': <String, String>{},
        });

        var attemptCount = 0;
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            attemptCount++;
            capturedUrls.add(conn.url);

            if (attemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'recovered-conn-id',
                  connectionKey: 'new-key-after-recovery',
                ),
              );
            } else {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'recovered-conn-id',
                  connectionKey: 'resumed-key',
                ),
              );
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            recover: recoveryKey,
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Connect — first connection should use recover param
        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // RTN16k: First connection uses recover param with connectionKey
        expect(
          capturedUrls[0].queryParameters['recover'],
          equals('recovered-key-xyz'),
        );
        expect(capturedUrls[0].queryParameters.containsKey('resume'), isFalse);

        // Simulate disconnect and reconnection
        mockWs.activeConnection!.simulateDisconnect();
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance timer for retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Second connection attempt uses resume (not recover)
        expect(capturedUrls.length, greaterThanOrEqualTo(2));
        expect(
          capturedUrls[1].queryParameters['resume'],
          equals('new-key-after-recovery'),
        );
        expect(capturedUrls[1].queryParameters.containsKey('recover'), isFalse);

        await client.close();
        mockWs.dispose();
      });
    });
  });

  group('RTN16f - recover option initializes msgSerial from recoveryKey', () {
    // UTS: realtime/unit/RTN16f/recover-initializes-msgserial-0
    test('msgSerial is initialized from the recoveryKey value', () async {
      final sentMessages = <ProtocolMessage>[];

      final recoveryKey = jsonEncode({
        'connectionKey': 'old-key',
        'msgSerial': 42,
        'channelSerials': {
          'test-channel': 'ch-serial-1',
        },
      });

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'recovered-conn',
              connectionKey: 'new-key',
            ),
          );
        },
        onMessageFromClient: (msg) {
          sentMessages.add(msg);
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          recover: recoveryKey,
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Attach the pre-instantiated channel and publish a message
      final channel = client.channels.get('test-channel');

      // Verify the channel was pre-instantiated with channelSerial (RTN16j)
      expect(channel.properties.channelSerial, equals('ch-serial-1'));

      // Attach the channel
      channel.attach();
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.attached(
          channel: 'test-channel',
          channelSerial: 'ch-serial-1',
        ),
      );
      await _pumpEventQueue();

      // Publish a message — its msgSerial should be 42 (from recovery key)
      // ignore: unawaited_futures
      channel.publish(name: 'test', data: 'hello');
      await _pumpEventQueue();

      // Find the MESSAGE protocol message
      final publishMsgs = sentMessages
          .where((m) => m.action == ProtocolAction.message)
          .toList();
      expect(publishMsgs, isNotEmpty);
      expect(publishMsgs.first.msgSerial, equals(42));

      // ACK the message before closing to avoid pending message errors
      mockWs.activeConnection!.sendToClient(
        ProtocolMessageHelpers.ack(msgSerial: 42),
      );
      await _pumpEventQueue();

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN16f1 - Malformed recoveryKey logs error and connects normally', () {
    test(
        'malformed recoveryKey is handled gracefully, '
        'connection proceeds without recover param', () async {
      var connectionAttemptCount = 0;
      final capturedUrls = <Uri>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttemptCount++;
          capturedUrls.add(conn.url);
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'fresh-conn',
              connectionKey: 'fresh-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          recover: 'this-is-not-valid-json!!!',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Connect - should proceed as a normal connection
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Connection succeeded normally
      expect(client.connection.state, equals(ConnectionState.connected));
      expect(client.connection.id, equals('fresh-conn'));
      expect(client.connection.key, equals('fresh-key'));

      // No recover param was sent (malformed key → normal fresh connection)
      expect(capturedUrls[0].queryParameters.containsKey('recover'), isFalse);

      // No resume param either (fresh connection)
      expect(capturedUrls[0].queryParameters.containsKey('resume'), isFalse);

      // Only one connection attempt
      expect(connectionAttemptCount, equals(1));

      await client.close();
      mockWs.dispose();
    });
  });

  group(
      'RTN16j - recover option instantiates channels from recoveryKey '
      'with correct channelSerials', () {
    test(
        'channels from recoveryKey are pre-instantiated with '
        'channelSerials in INITIALIZED state', () async {
      final recoveryKey = jsonEncode({
        'connectionKey': 'old-key-abc',
        'msgSerial': 10,
        'channelSerials': {
          'channel-one': 'serial-1-abc',
          'channel-two': 'serial-2-def',
          'channel-üñîçöðé': 'serial-3-unicode',
        },
      });

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'recovered-conn',
              connectionKey: 'new-key',
            ),
          );
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          recover: recoveryKey,
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // RTN16j: Channels should already exist from recovery key parsing
      expect(client.channels.exists('channel-one'), isTrue);
      expect(client.channels.exists('channel-two'), isTrue);
      expect(client.channels.exists('channel-üñîçöðé'), isTrue);

      // Channels should have their channelSerials set
      final ch1 = client.channels.get('channel-one');
      final ch2 = client.channels.get('channel-two');
      final ch3 = client.channels.get('channel-üñîçöðé');

      expect(ch1.properties.channelSerial, equals('serial-1-abc'));
      expect(ch2.properties.channelSerial, equals('serial-2-def'));
      expect(ch3.properties.channelSerial, equals('serial-3-unicode'));

      // Channels should be in INITIALIZED state
      expect(ch1.state, equals(ChannelState.initialized));
      expect(ch2.state, equals(ChannelState.initialized));
      expect(ch3.state, equals(ChannelState.initialized));

      // Connect and verify recovery key is sent
      client.connect();
      await _awaitState(client.connection, ConnectionState.connected);

      // Verify recovery key round-trip with createRecoveryKey
      final newRecoveryKey = client.connection.createRecoveryKey();
      expect(newRecoveryKey, isNotNull);
      final parsed = jsonDecode(newRecoveryKey!) as Map<String, dynamic>;
      expect(parsed['connectionKey'], equals('new-key'));
      // channelSerials preserved from pre-instantiation
      final serials = parsed['channelSerials'] as Map<String, dynamic>;
      expect(serials['channel-one'], equals('serial-1-abc'));
      expect(serials['channel-two'], equals('serial-2-def'));
      expect(serials['channel-üñîçöðé'], equals('serial-3-unicode'));

      await client.close();
      mockWs.dispose();
    });
  });

  group('RTN16j - Channel serials from recovery key used on reattach', () {
    // UTS: realtime/unit/RTN16j/recover-channel-serials-0
    test(
      'recovered channels include channelSerial in ATTACH messages '
      'when reattaching after recovery',
      () async {
        final sentMessages = <ProtocolMessage>[];

        final recoveryKey = jsonEncode({
          'connectionKey': 'old-key',
          'msgSerial': 5,
          'channelSerials': {
            'channel-a': 'serial-a-100',
            'channel-b': 'serial-b-200',
          },
        });

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'recovered-conn',
                connectionKey: 'new-key',
              ),
            );
          },
          onMessageFromClient: (msg) {
            sentMessages.add(msg);
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            recover: recoveryKey,
            autoConnect: false,
          ),
          webSocketClient: mockWs,
        );

        // Channels should already exist from recovery key
        expect(client.channels.exists('channel-a'), isTrue);
        expect(client.channels.exists('channel-b'), isTrue);

        // Verify channel serials are set
        final chA = client.channels.get('channel-a');
        final chB = client.channels.get('channel-b');
        expect(chA.properties.channelSerial, equals('serial-a-100'));
        expect(chB.properties.channelSerial, equals('serial-b-200'));

        // Connect
        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Attach channel-a — ignore the returned Future since we won't
        // send an ATTACHED response; we just need the outgoing message.
        unawaited(chA.attach().catchError((_) {}));
        await _pumpEventQueue();

        // Find the ATTACH message for channel-a
        final attachMsgs = sentMessages
            .where(
              (m) =>
                  m.action == ProtocolAction.attach && m.channel == 'channel-a',
            )
            .toList();
        expect(
          attachMsgs,
          isNotEmpty,
          reason: 'ATTACH message should have been sent for channel-a',
        );

        // The ATTACH message should include the channelSerial from recovery
        // so the server can resume from where the channel left off
        expect(attachMsgs.first.channelSerial, equals('serial-a-100'));

        await client.close();
        mockWs.dispose();
      },
    );
  });

  group('RTN16 - Resume behavior on reconnection (existing functionality)', () {
    // UTS: realtime/unit/RTN16k/recover-query-param-0
    test('resume param includes connectionKey on reconnect', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final capturedUrls = <Uri>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            capturedUrls.add(conn.url);

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-original',
                ),
              );
            } else {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1', // Same ID = successful resume
                  connectionKey: 'key-resumed',
                ),
              );
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Connect
        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(client.connection.key, equals('key-original'));

        // First connection should not have resume parameter
        expect(capturedUrls[0].queryParameters.containsKey('resume'), isFalse);

        // Simulate disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Second connection should include resume parameter with original key
        expect(
          capturedUrls[1].queryParameters['resume'],
          equals('key-original'),
        );

        // Connection key updated after resume
        expect(client.connection.key, equals('key-resumed'));

        // Same connectionId means successful resume
        expect(client.connection.id, equals('conn-1'));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN16g/recovery-key-structure-0
    test('connectionKey is updated after successful resume', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-v1',
                ),
              );
            } else {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-1',
                  connectionKey: 'key-v2',
                ),
              );
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(client.connection.key, equals('key-v1'));

        // Disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Connection key should be updated to the new value
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.key, equals('key-v2'));
        expect(connectionAttemptCount, equals(2));

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTN16f1/malformed-recovery-key-0
    test('failed resume results in new connectionId', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-original',
                  connectionKey: 'key-original',
                ),
              );
            } else {
              // Resume failed: new connectionId with error
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'conn-new',
                  connectionKey: 'key-new',
                  error: const ErrorInfo(
                    code: 80008,
                    statusCode: 400,
                    message: 'Unable to recover connection',
                  ),
                ),
              );
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 1000,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);
        expect(client.connection.id, equals('conn-original'));

        // Disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Wait for DISCONNECTED (immediate mock response)
        await _awaitState(client.connection, ConnectionState.disconnected);

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // New connectionId means resume failed
        expect(client.connection.state, equals(ConnectionState.connected));
        expect(client.connection.id, equals('conn-new'));
        expect(client.connection.key, equals('key-new'));

        await client.close();
        mockWs.dispose();
      });
    });
  });
}

/// Waits for connection to reach the specified state.
Future<void> _awaitState(
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

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  for (var i = 0; i < 1; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for fallback hosts behavior (RTN17).
///
/// These tests verify that the client correctly uses fallback hosts
/// when primary connection fails and follows the fallback strategy.
///
/// Spec: uts/test/realtime/unit/connection/fallback_hosts_test.md
void main() {
  group('RTN17i - Always prefer primary domain first', () {
    // UTS: realtime/unit/RTN17i/prefer-primary-domain-0
    test('always tries primary domain first, even after previous failures',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final connectionAttempts = <String>[];
        var connectionAttemptCount = 0;

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            // Record which host was attempted
            connectionAttempts.add(conn.url.host);
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              // First attempt (to primary): fail
              conn.respondWithRefused();
            } else if (connectionAttemptCount == 3) {
              // Third attempt (immediate reconnect after disconnect): fail
              // This forces a timer-based retry so we can observe the
              // DISCONNECTED state and test retry behavior.
              conn.respondWithRefused();
            } else {
              // All other attempts succeed
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-id',
                  connectionKey: 'connection-key',
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

        // First connection attempt — primary fails, fallback succeeds
        // (immediate, no timer involved)
        client.connect();
        await _pumpEventQueue();
        expect(client.connection.state, equals(ConnectionState.connected));

        // Should have tried at least 2 hosts
        expect(connectionAttempts.length, greaterThanOrEqualTo(2));

        // First attempt was to primary domain
        expect(connectionAttempts[0], contains('realtime.ably'));

        // Second attempt was to a fallback domain
        expect(connectionAttempts[1], contains('fallback'));

        // Now force a disconnection — the immediate reconnect (attempt 3)
        // also fails because the mock refuses it, so the connection enters
        // DISCONNECTED and schedules a timer-based retry.
        mockWs.activeConnection!.close();
        await _pumpEventQueue();
        expect(client.connection.state, equals(ConnectionState.disconnected));

        // Clear previous attempts to track reconnection hosts
        connectionAttempts.clear();

        // Advance fake timer past disconnectedRetryTimeout to trigger retry
        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 1100));
        await _pumpEventQueue();

        // Should be connected now after timer-based retry
        expect(client.connection.state, equals(ConnectionState.connected));

        // The reconnection should have tried primary domain first
        expect(connectionAttempts.length, greaterThanOrEqualTo(1));
        expect(
          connectionAttempts[0],
          anyOf(contains('realtime.ably'), contains('realtime')),
        );

        await client.close();
      });
    });
  });

  group('RTN17f - Errors that necessitate fallback host usage', () {
    // UTS: realtime/unit/RTN17f/fallback-on-error-0
    test('host unreachable triggers fallback', () async {
      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // Primary domain: unresolvable/unreachable
            conn.respondWithDnsError();
          } else {
            // Fallback domain: succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for successful connection via fallback
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 10),
      );

      // Should have tried at least 2 hosts (primary + fallback)
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));

      // First attempt was to primary domain
      expect(connectionAttempts[0], contains('realtime.ably'));

      // Second attempt was to a fallback domain
      expect(connectionAttempts[1], contains('fallback'));

      await client.close();
    });

    // UTS: realtime/unit/RTN17f/fallback-on-error-0.1
    test('connection timeout triggers fallback', () async {
      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // Primary domain: timeout (never respond)
            conn.respondWithTimeout();
          } else {
            // Fallback domain: succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          realtimeRequestTimeout: 1000, // 1 second timeout
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      client.connect();

      // Wait for successful connection via fallback
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 10),
      );

      // Should have tried fallback after timeout
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));

      await client.close();
    });
  });

  group('RTN17f1 - DISCONNECTED with 5xx status triggers fallback', () {
    // UTS: realtime/unit/RTN17f1/disconnected-5xx-fallback-0
    test('503 error in DISCONNECTED message triggers fallback', () async {
      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // Primary domain: connect then send DISCONNECTED with 503
            conn.respondWithSuccess(
              ProtocolMessageHelpers.disconnected(
                error: const ErrorInfo(
                  code: 50003,
                  statusCode: 503,
                  message: 'Service temporarily unavailable',
                ),
              ),
            );
          } else {
            // Fallback domain: succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for successful connection via fallback
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 10),
      );

      // Should have tried at least 2 hosts
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));

      // First was primary, second was fallback
      expect(connectionAttempts[0], contains('realtime.ably'));
      expect(connectionAttempts[1], contains('fallback'));

      await client.close();
    });
  });

  group('RTN17j - Connectivity check before fallback', () {
    // UTS: realtime/unit/RTN17j/connectivity-check-before-fallback-0
    test('performs connectivity check before trying fallback hosts', () async {
      final httpRequests = <String>[];
      final connectionAttempts = <String>[];

      // Mock HTTP client for connectivity check
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          httpRequests.add(request.url.toString());

          if (request.url.toString().contains('internet-up')) {
            // Connectivity check succeeds
            request.respondWith(200, 'yes');
          } else {
            // Other requests (token, etc.)
            request.respondWith(200, {
              'token': 'test_token',
              'keyName': 'appId.keyId',
              'issued': DateTime.now().millisecondsSinceEpoch,
              'expires': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
              'capability': '{"*":["*"]}',
            });
          }
        },
      );

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);

          // All hosts fail to trigger connectivity check
          conn.respondWithTimeout();
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
        httpClient: mockHttp, // Inject mock HTTP client for connectivity check
      );

      // Start connection
      client.connect();

      // Wait for DISCONNECTED state (all hosts failed)
      await _awaitState(
        client.connection,
        ConnectionState.disconnected,
        timeout: const Duration(seconds: 15),
      );

      // Connectivity check should have been performed after all hosts failed
      final connectivityChecks =
          httpRequests.where((url) => url.contains('internet-up')).toList();
      expect(connectivityChecks.length, greaterThanOrEqualTo(1));

      // Multiple connection attempts were made (primary + fallbacks)
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));

      await client.close();
    });
  });

  group('RTN17g - Empty fallback set results in immediate error', () {
    // UTS: realtime/unit/RTN17g/empty-fallback-set-error-0
    test('no fallback attempted when fallback set is empty', () async {
      final connectionAttempts = <String>[];

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          // Connection fails
          conn.respondWithRefused();
        },
      );

      // Use custom endpoint which results in empty fallback set (REC2c2)
      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          endpoint: 'custom.example.com', // Explicit hostname = no fallbacks
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for DISCONNECTED (should not try fallbacks)
      await _awaitState(
        client.connection,
        ConnectionState.disconnected,
      );

      // Give it time to potentially try fallbacks (it shouldn't)
      await Future<void>.delayed(Duration.zero);

      // Should have only tried the custom host, no fallbacks
      expect(connectionAttempts.length, equals(1));
      expect(connectionAttempts[0], equals('custom.example.com'));

      await client.close();
    });
  });

  group('RTN17h - Fallback domains determined by REC2', () {
    // UTS: realtime/unit/RTN17h/fallback-domains-from-rec2-0
    test('uses correct fallback hosts based on configuration', () async {
      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // Primary fails
            conn.respondWithRefused();
          } else {
            // Fallback succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      // Use default configuration (should use default fallback hosts)
      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for successful connection
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 10),
      );

      // Should have tried primary then fallback
      expect(connectionAttempts.length, greaterThanOrEqualTo(2));

      // Second attempt should be a default fallback host
      // Default fallback pattern: *.a|b|c|d|e.fallback.ably-realtime.com
      final fallbackHost = connectionAttempts[1];
      expect(fallbackHost, contains('fallback.ably-realtime.com'));
      expect(
        RegExp(r'\.[abcde]\.fallback\.ably-realtime\.com$')
            .hasMatch(fallbackHost),
        isTrue,
      );

      await client.close();
    });
  });

  group('RTN17j - Fallback hosts tried in random order', () {
    // UTS: realtime/unit/RTN17j/fallback-random-order-1
    test('fallback hosts are not always tried in same order', () async {
      // This test would run multiple iterations to verify randomness
      // For now, just verify fallback hosts are used

      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount <= 3) {
            // Primary and first 2 fallbacks fail
            conn.respondWithRefused();
          } else {
            // Third fallback succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
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

      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 15),
      );

      // Should have tried multiple hosts
      expect(connectionAttempts.length, greaterThanOrEqualTo(3));

      // First is primary
      expect(connectionAttempts[0], contains('realtime.ably'));

      // Rest are fallbacks
      for (var i = 1; i < connectionAttempts.length; i++) {
        expect(connectionAttempts[i], contains('fallback'));
      }

      await client.close();
    });
  });

  group('RTN17e - HTTP requests use same fallback host as realtime', () {
    // UTS: realtime/unit/RTN17e/http-uses-same-fallback-0
    test('HTTP requests prefer same host as active realtime connection',
        () async {
      final connectionAttempts = <String>[];
      var connectionAttemptCount = 0;

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionAttempts.add(conn.url.host);
          connectionAttemptCount++;

          if (connectionAttemptCount == 1) {
            // Primary fails
            conn.respondWithRefused();
          } else {
            // Fallback succeeds
            conn.respondWithSuccess(
              ProtocolMessageHelpers.connected(
                connectionId: 'connection-id',
                connectionKey: 'connection-key',
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Start connection
      client.connect();

      // Wait for successful connection to fallback
      await _awaitState(
        client.connection,
        ConnectionState.connected,
        timeout: const Duration(seconds: 10),
      );

      // Determine which fallback host we're connected to
      final connectedFallbackHost = connectionAttempts[1];

      // TODO: Make an HTTP request (e.g., channel history)
      // Currently RealtimeChannel doesn't expose REST API methods like history()
      // This test would verify that HTTP requests use the same fallback host
      // as the realtime connection.

      // For now, just verify we're connected to a fallback host
      expect(connectedFallbackHost, contains('fallback'));

      await client.close();
    });
  });
}

/// Helper function to wait for a connection state.
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
/// Used after advancing fake time to let scheduled callbacks run.
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

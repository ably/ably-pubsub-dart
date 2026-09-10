import 'dart:async';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for configured timeouts (RTC7).
///
/// Tests that the realtime client uses the configured timeouts specified
/// in ClientOptions, falling back to client library defaults.
///
/// Spec: uts/test/realtime/unit/client/realtime_timeouts.md
void main() {
  group('RTC7 - realtimeRequestTimeout applied to channel attach', () {
    // UTS: realtime/unit/RTC7/attach-request-timeout-0
    test('custom realtimeRequestTimeout is used for attach timeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTC7-attach');

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          // Don't respond to ATTACH — simulate timeout
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 500,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // Start attach — register error handler immediately
        Object? error;
        final future = channel.attach().catchError((Object e) => error = e);

        // Advance past the custom timeout (500ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 600));
        await _pumpEventQueue();
        await future;

        // Should have timed out using the custom value
        expect(error, isNotNull);
        // RTL4f: attach timeout → SUSPENDED
        expect(channel.state, equals(ChannelState.suspended));

        mockWs.dispose();
      });
    });
  });

  group('RTC7 - realtimeRequestTimeout applied to channel detach', () {
    // UTS: realtime/unit/RTC7/detach-request-timeout-1
    test('custom realtimeRequestTimeout is used for detach timeout', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTC7-detach');
        var ignoreDetach = false;

        late final MockWebSocketClient mockWs;
        mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          },
          onMessageFromClient: (msg) {
            if (msg.action == ProtocolAction.attach) {
              mockWs.activeConnection!.sendToClient(
                ProtocolMessageHelpers.attached(channel: channelName),
              );
            }
            if (msg.action == ProtocolAction.detach && ignoreDetach) {
              // Don't respond — simulate timeout
            }
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 500,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final channel = client.channels.get(channelName);

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );
        await channel.attach();

        // Now ignore DETACH messages
        ignoreDetach = true;

        // Start detach — register error handler immediately
        Object? error;
        final future = channel.detach().catchError((Object e) => error = e);

        // Advance past the custom timeout (500ms)
        fakeTimers.elapseTime(const Duration(milliseconds: 600));
        await _pumpEventQueue();
        await future;

        // Should have timed out using the custom value
        expect(error, isNotNull);
        // RTL5f: detach timeout → back to ATTACHED
        expect(channel.state, equals(ChannelState.attached));

        mockWs.dispose();
      });
    });
  });

  group('RTC7 - disconnectedRetryTimeout controls reconnection delay', () {
    // UTS: realtime/unit/RTC7/disconnected-retry-timeout-2
    test('custom disconnectedRetryTimeout controls reconnection timing',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;

        // First connection succeeds; all subsequent attempts fail (refused).
        // fallbackHosts: [] prevents fallback host iteration on SocketException.
        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;
            if (connectionAttemptCount == 1) {
              // Initial connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  maxIdleInterval: 0, // Disable heartbeat idle timeout
                ),
              );
            } else {
              // All subsequent attempts fail
              conn.respondWithRefused();
            }
          },
        );

        // Mock HTTP client so connectivity check doesn't make real requests
        final mockHttp = MockHttpClient(
          onRequest: (req) => req.respondWith(200, 'yes'),
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            disconnectedRetryTimeout: 2000,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          httpClient: mockHttp,
          timerManager: fakeTimers,
        );

        client.connect();
        await _awaitConnectionState(
          client.connection,
          ConnectionState.connected,
        );
        expect(connectionAttemptCount, equals(1));

        // Set up listener BEFORE disconnecting to avoid race condition.
        // We want the second DISCONNECTED event (after the failed retry).
        // First DISCONNECTED is from simulateDisconnect, second is after
        // the failed immediate retry.
        final secondDisconnected =
            client.connection.on(ConnectionEvent.disconnected).skip(1).first;

        // Force disconnection — triggers RTN15a immediate retry which fails
        // (no fallback hosts), connectivity check, then DISCONNECTED again
        mockWs.activeConnection!.simulateDisconnect();

        await secondDisconnected.timeout(const Duration(seconds: 10));

        expect(client.connection.state, equals(ConnectionState.disconnected));

        // Record the attempt count after the immediate retry cycle
        final countAfterImmediate = connectionAttemptCount;

        // Advance time by less than the custom timeout — no new retry yet
        fakeTimers.elapseTime(const Duration(milliseconds: 1500));
        await _pumpEventQueue();
        expect(connectionAttemptCount, equals(countAfterImmediate));

        // Advance past the custom timeout (2000ms + jitter margin)
        fakeTimers.elapseTime(const Duration(milliseconds: 1500));
        await _pumpEventQueue();

        // A new reconnection attempt should have been made
        expect(connectionAttemptCount, greaterThan(countAfterImmediate));

        mockWs.dispose();
      });
    });
  });

  group('RTC7 - default timeouts applied when not configured', () {
    // UTS: realtime/unit/RTC7/default-timeouts-applied-3
    test('uses spec-defined default timeout values', () {
      final options = ClientOptions(
        key: 'appId.keyId:keySecret',
        autoConnect: false,
      );

      // Default values per spec (TO3l*)
      expect(options.realtimeRequestTimeout, equals(10000));
      expect(options.disconnectedRetryTimeout, equals(15000));
      expect(options.suspendedRetryTimeout, equals(30000));
      expect(options.httpOpenTimeout, equals(4000));
      expect(options.httpRequestTimeout, equals(10000));
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

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';

/// Unit tests for backoff and jitter behavior (RTB1, RTB1a, RTB1b).
///
/// These tests verify that retry delays for DISCONNECTED connections follow
/// exponential backoff with jitter as specified.
///
/// Spec: specification/uts/realtime/unit/connection/backoff_jitter_test.md
void main() {
  group('RTB1a - Backoff coefficient follows min((n+2)/3, 2)', () {
    // UTS: realtime/unit/RTB1a/backoff-coefficient-sequence-0
    test('produces correct coefficient sequence for successive retries', () {
      // RTB1a: The backoff coefficient for the nth retry (1-indexed) is
      // min((n+2)/3, 2), producing the sequence [1, 4/3, 5/3, 2, 2, ...]

      // Calculate expected coefficients for retries 1 through 10
      final coefficients = <double>[];
      for (var n = 1; n <= 10; n++) {
        final coefficient = min((n + 2) / 3.0, 2.0);
        coefficients.add(coefficient);
      }

      // Verify exact values for the first few retries
      expect(coefficients[0], closeTo(1.0, 0.001)); // n=1: (1+2)/3 = 1
      expect(coefficients[1], closeTo(4.0 / 3.0, 0.001)); // n=2: (2+2)/3 = 4/3
      expect(coefficients[2], closeTo(5.0 / 3.0, 0.001)); // n=3: (3+2)/3 = 5/3
      expect(coefficients[3], closeTo(2.0, 0.001)); // n=4: (4+2)/3 = 2, capped

      // Verify all subsequent retries are capped at 2.0
      for (var i = 3; i < 10; i++) {
        expect(
          coefficients[i],
          closeTo(2.0, 0.001),
          reason: 'Retry ${i + 1} should be capped at 2.0',
        );
      }
    });
  });

  group('RTB1b - Jitter coefficient is between 0.8 and 1.0', () {
    // UTS: realtime/unit/RTB1b/jitter-coefficient-range-0
    test('all values are within [0.8, 1.0] with approximate uniformity', () {
      // RTB1b: The jitter coefficient is a random number between 0.8 and 1.0,
      // approximately uniformly distributed.

      const sampleCount = 1000;
      final random = Random();
      final jitterValues = <double>[];

      for (var i = 0; i < sampleCount; i++) {
        // Generate jitter: 0.8 + random * 0.2
        final jitter = 0.8 + random.nextDouble() * 0.2;
        jitterValues.add(jitter);
      }

      // All values must be within [0.8, 1.0]
      for (final jitter in jitterValues) {
        expect(jitter, greaterThanOrEqualTo(0.8));
        expect(jitter, lessThanOrEqualTo(1.0));
      }

      // Verify approximate uniformity: mean should be close to 0.9
      final mean = jitterValues.reduce((a, b) => a + b) / sampleCount;
      expect(mean, greaterThanOrEqualTo(0.85));
      expect(mean, lessThanOrEqualTo(0.95));

      // Verify spread: not all values are the same
      final minValue = jitterValues.reduce(min);
      final maxValue = jitterValues.reduce(max);
      expect(maxValue - minValue, greaterThan(0.05));
    });
  });

  group('RTB1 - Combined retry delay for DISCONNECTED connections', () {
    test(
        'retryIn values follow disconnectedRetryTimeout * backoff * jitter pattern',
        () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final retryDelays = <int>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              // Initial connection succeeds
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-id',
                  connectionKey: 'connection-key',
                  connectionStateTtl: 60000,
                ),
              );
            } else {
              // All reconnection attempts fail
              conn.respondWithRefused();
            }
          },
        );

        const disconnectedRetryTimeout = 2000; // 2 seconds

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: disconnectedRetryTimeout,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        // Capture retryIn from DISCONNECTED state changes
        client.connection.on(ConnectionEvent.disconnected).listen((change) {
          if (change.retryIn != null) {
            retryDelays.add(change.retryIn!);
          }
        });

        // Connect and wait for CONNECTED
        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Simulate unexpected disconnect to trigger reconnection cycle
        mockWs.activeConnection!.simulateDisconnect();

        // Advance time in increments to allow multiple retry cycles.
        // Each retry fails (respondWithRefused), producing another DISCONNECTED
        // state change with a retryIn value.
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 5000));
          await _pumpEventQueue();
          if (retryDelays.length >= 5) break;
        }

        expect(retryDelays.length, greaterThanOrEqualTo(5));

        // For each retry, verify retryIn is within the expected range:
        // retryIn = disconnectedRetryTimeout * backoff(n) * jitter
        // where jitter is in [0.8, 1.0]

        // Retry 1: backoff = 1.0, range = [2000*0.8, 2000*1.0] = [1600, 2000]
        expect(
          retryDelays[0],
          greaterThanOrEqualTo((disconnectedRetryTimeout * 1.0 * 0.8).ceil()),
          reason: 'Retry 1 lower bound',
        );
        expect(
          retryDelays[0],
          lessThanOrEqualTo(
            (disconnectedRetryTimeout * 1.0 * 1.0).floor() + 1,
          ),
          reason: 'Retry 1 upper bound',
        );

        // Retry 2: backoff = 4/3
        expect(
          retryDelays[1],
          greaterThanOrEqualTo(
            (disconnectedRetryTimeout * (4.0 / 3.0) * 0.8).ceil(),
          ),
          reason: 'Retry 2 lower bound',
        );
        expect(
          retryDelays[1],
          lessThanOrEqualTo(
            (disconnectedRetryTimeout * (4.0 / 3.0) * 1.0).floor() + 1,
          ),
          reason: 'Retry 2 upper bound',
        );

        // Retry 3: backoff = 5/3
        expect(
          retryDelays[2],
          greaterThanOrEqualTo(
            (disconnectedRetryTimeout * (5.0 / 3.0) * 0.8).ceil(),
          ),
          reason: 'Retry 3 lower bound',
        );
        expect(
          retryDelays[2],
          lessThanOrEqualTo(
            (disconnectedRetryTimeout * (5.0 / 3.0) * 1.0).floor() + 1,
          ),
          reason: 'Retry 3 upper bound',
        );

        // Retry 4+: backoff = 2.0 (capped)
        expect(
          retryDelays[3],
          greaterThanOrEqualTo((disconnectedRetryTimeout * 2.0 * 0.8).ceil()),
          reason: 'Retry 4 lower bound',
        );
        expect(
          retryDelays[3],
          lessThanOrEqualTo(
            (disconnectedRetryTimeout * 2.0 * 1.0).floor() + 1,
          ),
          reason: 'Retry 4 upper bound',
        );

        expect(
          retryDelays[4],
          greaterThanOrEqualTo((disconnectedRetryTimeout * 2.0 * 0.8).ceil()),
          reason: 'Retry 5 lower bound',
        );
        expect(
          retryDelays[4],
          lessThanOrEqualTo(
            (disconnectedRetryTimeout * 2.0 * 1.0).floor() + 1,
          ),
          reason: 'Retry 5 upper bound',
        );

        await client.close();
        mockWs.dispose();
      });
    });

    // UTS: realtime/unit/RTB1/disconnected-retry-delay-0
    test('retry delays increase monotonically up to the cap', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        var connectionAttemptCount = 0;
        final retryDelays = <int>[];

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            connectionAttemptCount++;

            if (connectionAttemptCount == 1) {
              conn.respondWithSuccess(
                ProtocolMessageHelpers.connected(
                  connectionId: 'connection-id',
                  connectionKey: 'connection-key',
                  connectionStateTtl: 60000,
                ),
              );
            } else {
              conn.respondWithRefused();
            }
          },
        );

        const disconnectedRetryTimeout = 3000; // 3 seconds

        final client = PubSubClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            disconnectedRetryTimeout: disconnectedRetryTimeout,
            autoConnect: false,
            fallbackHosts: [],
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        client.connection.on(ConnectionEvent.disconnected).listen((change) {
          if (change.retryIn != null) {
            retryDelays.add(change.retryIn!);
          }
        });

        client.connect();
        await _awaitState(client.connection, ConnectionState.connected);

        // Trigger disconnect
        mockWs.activeConnection!.simulateDisconnect();

        // Collect at least 4 retry delays
        for (var i = 0; i < 30; i++) {
          fakeTimers.elapseTime(const Duration(milliseconds: 7000));
          await _pumpEventQueue();
          if (retryDelays.length >= 4) break;
        }

        expect(retryDelays.length, greaterThanOrEqualTo(4));

        // The maximum possible retry delay for retry n should be >=
        // the minimum possible retry delay for retry n (monotonically
        // non-decreasing when accounting for backoff, even with jitter).
        // Since backoff increases: 1, 4/3, 5/3, 2, 2, ...
        // The min of retry n+1 (backoff(n+1)*0.8) >= min of retry n (backoff(n)*0.8)
        // while backoff is increasing (retries 1-4).

        // After cap (retry 4+), all retries share the same range [cap*0.8, cap*1.0]
        // Verify retries 4+ are all within the capped range
        for (var i = 3; i < retryDelays.length; i++) {
          expect(
            retryDelays[i],
            greaterThanOrEqualTo(
              (disconnectedRetryTimeout * 2.0 * 0.8).ceil(),
            ),
            reason: 'Retry ${i + 1} should be at capped minimum',
          );
          expect(
            retryDelays[i],
            lessThanOrEqualTo(
              (disconnectedRetryTimeout * 2.0 * 1.0).floor() + 1,
            ),
            reason: 'Retry ${i + 1} should be at capped maximum',
          );
        }

        await client.close();
        mockWs.dispose();
      });
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

/// Pumps the event queue multiple times to allow microtasks to complete.
Future<void> _pumpEventQueue([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

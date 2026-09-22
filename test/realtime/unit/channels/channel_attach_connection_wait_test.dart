import 'dart:async';

import 'package:ably/ably.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

import '../../../helpers/fake_timer_manager.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RTL4b/RTL4i: attach() must not hang while waiting for the
/// connection to reach CONNECTED.
void main() {
  group('RTL4b, RTL4i - attach() rejects when the connection FAILS', () {
    test('attach() completes with an error instead of hanging', () async {
      final channelName = testChannelName('RTL4b-conn-failed');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40005,
              statusCode: 400,
              message: 'Invalid key',
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

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      await expectLater(
        channel.attach().timeout(const Duration(seconds: 3)),
        throwsA(isA<AblyException>()),
      );

      expect(client.connection.state, equals(ConnectionState.failed));
      expect(client.connection.errorReason!.code, equals(40005));

      mockWs.dispose();
    });
  });

  group('RTL4i, RTL4b - the connection wait has no request timeout', () {
    test(
        'attach() stays pending past realtimeRequestTimeout, then rejects '
        'once the connection CLOSES', () async {
      final testClock = TestClock();
      final fakeTimers = FakeTimerManager(testClock);

      await withClock(testClock, () async {
        final channelName = testChannelName('RTL4i-conn-wait');

        final mockWs = MockWebSocketClient(
          onConnectionAttempt: (conn) {
            conn.respondWithSilence();
          },
        );

        final client = RealtimeClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            autoConnect: false,
            realtimeRequestTimeout: 100,
          ),
          webSocketClient: mockWs,
          timerManager: fakeTimers,
        );

        final channel = client.channels.get(
          channelName,
          const RealtimeChannelOptions(attachOnSubscribe: false),
        );

        var settled = false;
        Object? attachError;
        final attachFuture = channel.attach().then<void>((_) {
          settled = true;
        }).catchError((Object e) {
          settled = true;
          attachError = e;
        });

        await _pumpEventQueue();
        fakeTimers.elapseTime(const Duration(milliseconds: 500));
        await _pumpEventQueue();

        expect(settled, isFalse, reason: 'RTL4i - no timeout on the wait');
        expect(channel.state, equals(ChannelState.attaching));

        await client.close();
        await _pumpEventQueue();
        await attachFuture.timeout(const Duration(seconds: 3));

        expect(settled, isTrue);
        expect(attachError, isA<AblyException>());

        mockWs.dispose();
      });
    });
  });
}

/// Pumps the event queue to allow async operations to complete.
Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

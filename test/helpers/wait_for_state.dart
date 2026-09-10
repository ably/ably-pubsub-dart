import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';

/// Waits for a connection to reach [target] state.
///
/// Checks the current state first — if already in [target], resolves
/// immediately. Otherwise listens for state change events.
/// Matches the UTS `AWAIT_STATE` semantics and the ably-js `waitForState`
/// helper.
Future<void> waitForConnectionState(
  Connection connection,
  ConnectionState target, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (connection.state == target) return;

  final completer = Completer<void>();
  final sub = connection.on().listen((stateChange) {
    if (stateChange.current == target && !completer.isCompleted) {
      completer.complete();
    }
  });

  try {
    await completer.future.timeout(timeout);
  } on TimeoutException {
    throw TimeoutException(
      'Timed out waiting for connection state $target '
      '(current: ${connection.state})',
      timeout,
    );
  } finally {
    await sub.cancel();
  }
}

/// Waits for a channel to reach [target] state.
///
/// Checks the current state first — if already in [target], resolves
/// immediately. Otherwise listens for state change events.
Future<void> waitForChannelState(
  RealtimeChannel channel,
  ChannelState target, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (channel.state == target) return;

  final completer = Completer<void>();
  final sub = channel.on().listen((stateChange) {
    if (stateChange.current == target && !completer.isCompleted) {
      completer.complete();
    }
  });

  try {
    await completer.future.timeout(timeout);
  } on TimeoutException {
    throw TimeoutException(
      'Timed out waiting for channel state $target '
      '(current: ${channel.state})',
      timeout,
    );
  } finally {
    await sub.cancel();
  }
}

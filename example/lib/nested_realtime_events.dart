// NOTE: this file is not being used anywhere, yet
// this could serve as a reference for writing nested listeners

import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart' as ably;

/// This method is a demonstration on how to use multiple listeners
/// with realtime connection state change listeners as an example
void listenRealtimeConnection(ably.RealtimeClient realtime) {
  //RETAINING LISTENER - α
  realtime.connection.on().listen((stateChange) {
    print('RETAINING LISTENER α :: Change event arrived!: ${stateChange.event}'
        '\nReason: ${stateChange.reason}');
  });

  //DISPOSE ON CONNECTED
  final stream = realtime.connection.on();
  late StreamSubscription<ably.ConnectionStateChange> omegaSubscription;
  omegaSubscription = stream.listen((stateChange) async {
    print('DISPOSABLE LISTENER ω :: Change event arrived!:'
        ' ${stateChange.event}');
    if (stateChange.event == ably.ConnectionEvent.connected) {
      await omegaSubscription.cancel();
    }
  });

  //RETAINING LISTENER - β
  realtime.connection.on().listen((stateChange) {
    print('RETAINING LISTENER β :: Change event arrived!:'
        ' ${stateChange.event}');
    // NESTED LISTENER - ξ
    realtime.connection.on().listen((stateChange) {
      print('NESTED LISTENER ξ: ${stateChange.event}');
    });
  });

  StreamSubscription<ably.ConnectionStateChange> preZetaSubscription;
  late StreamSubscription<ably.ConnectionStateChange> postZetaSubscription;
  preZetaSubscription = realtime.connection.on().listen((stateChange) {
    print('NESTED LISTENER "pre ζ": ${stateChange.event}');
  });

  //RETAINING LISTENER - γ
  realtime.connection.on().listen((stateChange) async {
    print(
      'RETAINING LISTENER γ :: Change event arrived!: ${stateChange.event}',
    );
    if (stateChange.event == ably.ConnectionEvent.connected) {
      await preZetaSubscription.cancel();
      await postZetaSubscription.cancel();
    }
  });

  postZetaSubscription = realtime.connection.on().listen((stateChange) {
    print('NESTED LISTENER "post ζ": ${stateChange.event}');
  });
}

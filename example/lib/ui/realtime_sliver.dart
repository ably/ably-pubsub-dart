import 'dart:async';

import 'package:ably_pubsub_device/ably_pubsub_device.dart' as ably;
import 'package:ably_example/constants.dart';
import 'package:ably_example/ui/ably_service.dart';
import 'package:ably_example/ui/paginated_result_viewer.dart';
import 'package:ably_example/ui/realtime_presence_sliver.dart';
import 'package:ably_example/ui/text_row.dart';
import 'package:ably_example/ui/utilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

// ignore: must_be_immutable
class RealtimeSliver extends HookWidget {
  final AblyService ablyService;
  final ably.RealtimeClient realtime;
  late ably.RealtimeChannel channel;
  List<StreamSubscription<dynamic>> _streamSubscriptions = [];

  RealtimeSliver(this.ablyService, {super.key})
      : realtime = ablyService.realtime {
    channel = realtime.channels.get(Constants.channelName);
  }

  void _cancelSubscriptions() {
    for (final sub in _streamSubscriptions) {
      sub.cancel();
    }
    _streamSubscriptions = [];
  }

  Widget buildConnectButton() => TextButton(
        onPressed: realtime.connect,
        child: const Text('Connect'),
      );

  Widget buildDisconnectButton(ably.ConnectionState state) => TextButton(
        onPressed:
            (state == ably.ConnectionState.connected) ? realtime.close : null,
        child: const Text('Disconnect'),
      );

  Widget buildChannelAttachButton(
    ably.ConnectionState connectionState,
    ably.ChannelState channelState,
  ) =>
      TextButton(
        onPressed: (connectionState == ably.ConnectionState.connected &&
                channelState != ably.ChannelState.attached)
            ? () async {
                try {
                  await channel.attach();
                } on ably.AblyException catch (e) {
                  print('Unable to attach to channel: ${e.errorInfo}');
                }
              }
            : null,
        child: const Text('Attach'),
      );

  Widget buildChannelDetachButton(ably.ChannelState channelState) => TextButton(
        onPressed: (channelState == ably.ChannelState.attached)
            ? channel.detach
            : null,
        child: const Text('Detach'),
      );

  // Stores the message listener so we can unsubscribe later
  void Function(ably.Message)? _messageListener;

  Widget buildChannelSubscribeButton(
    ably.ChannelState channelState,
    ValueNotifier<ably.Message?> latestMessage,
    ValueNotifier<bool> isSubscribed,
  ) =>
      TextButton(
        onPressed:
            (channelState == ably.ChannelState.attached && !isSubscribed.value)
                ? () {
                    _messageListener = (message) {
                      latestMessage.value = message;
                    };
                    channel.subscribe(_messageListener!);
                    isSubscribed.value = true;
                  }
                : null,
        child: const Text('Subscribe'),
      );

  Widget buildChannelUnsubscribeButton(ValueNotifier<bool> isSubscribed) =>
      TextButton(
        onPressed: isSubscribed.value
            ? () {
                channel.unsubscribe(listener: _messageListener);
                _messageListener = null;
                isSubscribed.value = false;
              }
            : null,
        child: const Text('Unsubscribe'),
      );

  int typeCounter = 0;
  int realtimePubCounter = 0;

  Widget buildChannelPublishButton(ably.ChannelState channelState) =>
      TextButton(
        onPressed: (channelState == ably.ChannelState.attached)
            ? () async {
                final data = _messagesToPublish[
                    (realtimePubCounter++ % _messagesToPublish.length)];
                final m = ably.Message(
                  name: 'Message $realtimePubCounter',
                  data: data,
                );
                try {
                  switch (typeCounter % 3) {
                    case 0:
                      await channel.publish(
                        name: 'Message $realtimePubCounter',
                        data: data,
                      );
                      break;
                    case 1:
                      await channel.publish(message: m);
                      break;
                    case 2:
                      await channel.publish(messages: [m, m]);
                  }
                  if (realtimePubCounter != 0 &&
                      realtimePubCounter % _messagesToPublish.length == 0) {
                    typeCounter++;
                  }
                } on ably.AblyException catch (e) {
                  print(e);
                }
              }
            : null,
        child: const Text('Publish'),
      );

  Widget buildReleaseRealtimeChannelButton(
    ValueNotifier<ably.ConnectionState> connectionState,
    ValueNotifier<ably.ChannelState> channelState,
    ValueNotifier<String?> connectionId,
    ValueNotifier<String?> recoveryKey,
  ) =>
      TextButton(
        onPressed: () async {
          await channel.detach();
          realtime.channels.release(Constants.channelName);
          channel = realtime.channels.get(Constants.channelName);
          setupListeners(
            connectionState,
            channelState,
            connectionId,
            recoveryKey,
          );
        },
        child: const Text('Release'),
      );

  Widget buildEncryptionSwitch(ValueNotifier<bool> isEnabled) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Enable encryption',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Switch(
            onChanged: (switchedOn) async {
              isEnabled.value = switchedOn;
              if (switchedOn) {
                await channel.setOptions(
                  ably.RealtimeChannelOptions.withCipherKey(
                    keyFromPassword(
                      Constants.examplePasswordForEncryptedChannel,
                    ),
                  ),
                );
              } else {
                await channel.setOptions(const ably.RealtimeChannelOptions());
              }
            },
            value: isEnabled.value,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final connectionState =
        useState<ably.ConnectionState>(realtime.connection.state);
    final connectionId = useState<String?>(realtime.connection.id);
    final recoveryKey = useState<String?>('');
    final channelState = useState<ably.ChannelState>(channel.state);
    final latestMessage = useState<ably.Message?>(null);
    final isSubscribed = useState<bool>(false);
    final realtimeTime = useState<DateTime?>(null);
    final useEncryption = useState(false);

    useEffect(
      () {
        realtime.time().then((value) => realtimeTime.value = value);
        setupListeners(
          connectionState,
          channelState,
          connectionId,
          recoveryKey,
        );
        return _cancelSubscriptions;
      },
      [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Realtime',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text('Realtime time: ${realtimeTime.value}'),
        Text('Connection State: ${connectionState.value.name}'),
        Text('Connection Id: ${connectionId.value ?? '-'}'),
        Text('Connection Recovery Key: ${recoveryKey.value ?? '-'}'),
        buildEncryptionSwitch(useEncryption),
        Row(
          children: <Widget>[
            Expanded(child: buildConnectButton()),
            Expanded(child: buildDisconnectButton(connectionState.value)),
          ],
        ),
        const Text(
          'Channel',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text('Channel State: ${channelState.value.name}'),
        Row(
          children: <Widget>[
            Expanded(
              child: buildChannelAttachButton(
                connectionState.value,
                channelState.value,
              ),
            ),
            Expanded(child: buildChannelDetachButton(channelState.value)),
            Expanded(
              child: buildReleaseRealtimeChannelButton(
                connectionState,
                channelState,
                connectionId,
                recoveryKey,
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: buildChannelSubscribeButton(
                channelState.value,
                latestMessage,
                isSubscribed,
              ),
            ),
            Expanded(child: buildChannelPublishButton(channelState.value)),
            Expanded(child: buildChannelUnsubscribeButton(isSubscribed)),
          ],
        ),
        TextRow(
          'Latest message received',
          latestMessage.value?.data.toString(),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TextRow('Next message to be published:', null),
            TextRow('  Name', 'Message $realtimePubCounter'),
            TextRow(
              '  Data',
              _messagesToPublish[realtimePubCounter % _messagesToPublish.length]
                  .toString(),
            ),
          ],
        ),
        RealtimePresenceSliver(
          realtime: realtime,
          channel: channel,
        ),
        PaginatedResultViewer<ably.Message>(
          title: 'History',
          subtitle: const Column(
            children: [
              TextRow(
                  'Hint',
                  'Use realtime history as a way to get messages that were'
                      ' published before you are attached to the channel.'),
              TextRow(
                  'Warning',
                  'untilAttach only returns messages published before the '
                      'current attachment. Omit untilAttach to query the '
                      'full channel history whilst attached.'),
            ],
          ),
          query: () => channel.history(
            const ably.RealtimeHistoryParams(
              limit: 10,
              untilAttach: true,
            ),
          ),
          builder: (context, message, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextRow('Name', message.name),
              TextRow('Data', message.data.toString()),
            ],
          ),
        ),
      ],
    );
  }

  void setupListeners(
    ValueNotifier<ably.ConnectionState> connectionState,
    ValueNotifier<ably.ChannelState> channelState,
    ValueNotifier<String?> connectionId,
    ValueNotifier<String?> recoveryKey,
  ) {
    _cancelSubscriptions();
    final connectionSub =
        realtime.connection.on().listen((connectionStateChange) {
      if (connectionStateChange.current == ably.ConnectionState.failed) {
        logAndDisplayError(connectionStateChange.reason);
      }
      connectionState.value = connectionStateChange.current;
      connectionId.value = realtime.connection.id;
      recoveryKey.value = realtime.connection.createRecoveryKey();
      print('${DateTime.now()}:'
          ' ConnectionStateChange event: ${connectionStateChange.event}'
          '\nReason: ${connectionStateChange.reason}');
    });
    _streamSubscriptions.add(connectionSub);

    final channelSub = channel.on().listen((stateChange) {
      channelState.value = channel.state;
    });
    _streamSubscriptions.add(channelSub);
  }
}

List<dynamic> _messagesToPublish = [
  null,
  'A simple panda...',
  {
    'I am': null,
    'and': {
      'also': 'nested',
      'too': {'deep': true},
    },
  },
  [
    42,
    {'are': 'you'},
    'ok?',
    false,
    {
      'I am': null,
      'and': {
        'also': 'nested',
        'too': {'deep': true},
      },
    }
  ]
];

import 'package:ably_pubsub_device/ably_pubsub_device.dart' as ably;
import 'package:ably_example/constants.dart';
import 'package:ably_example/ui/paginated_result_viewer.dart';
import 'package:ably_example/ui/text_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

// ignore: must_be_immutable
class RealtimePresenceSliver extends HookWidget {
  final ably.PubSubClient realtime;
  final ably.RealtimeChannel channel;

  // Stores the presence listener so we can unsubscribe later
  void Function(ably.PresenceMessage)? _presenceListener;

  RealtimePresenceSliver({
    required this.realtime,
    required this.channel,
    super.key,
  });

  Widget createChannelPresenceSubscribeButton(
    ValueNotifier<ably.PresenceMessage?> latestMessage,
    ably.ChannelState? channelState,
    ValueNotifier<bool> isSubscribed,
  ) =>
      TextButton(
        onPressed:
            (channelState == ably.ChannelState.attached && !isSubscribed.value)
                ? () {
                    _presenceListener = (presenceMessage) {
                      latestMessage.value = presenceMessage;
                    };
                    channel.presence.subscribe(_presenceListener!);
                    isSubscribed.value = true;
                  }
                : null,
        child: const Text('Subscribe'),
      );

  Widget createChannelPresenceUnsubscribeButton(
    ValueNotifier<bool> isSubscribed,
  ) =>
      TextButton(
        onPressed: isSubscribed.value
            ? () {
                channel.presence.unsubscribe(listener: _presenceListener);
                _presenceListener = null;
                isSubscribed.value = false;
              }
            : null,
        child: const Text('Unsubscribe'),
      );

  Widget getRealtimeChannelPresence(
    ValueNotifier<List<ably.PresenceMessage>> presenceMembers,
  ) =>
      TextButton(
        onPressed: () async {
          presenceMembers.value = await channel.presence.get();
        },
        child: const Text('Get Realtime presence members'),
      );

  final List<dynamic> _presenceData = [
    null,
    1,
    'hello',
    {'a': 'b'},
    [
      1,
      'ably',
      null,
      {'a': 'b'},
    ],
    {
      'c': ['a', 'b'],
    },
  ];

  int _presenceDataIncrementer = 0;

  Object get _nextPresenceData =>
      _presenceData[_presenceDataIncrementer++ % _presenceData.length]
          .toString();

  Widget enterRealtimePresence() => TextButton(
        onPressed: () async {
          await channel.presence.enter(_nextPresenceData);
        },
        child: const Text('Enter'),
      );

  Widget updateRealtimePresence() => TextButton(
        onPressed: () async {
          await channel.presence
              .updateClient(Constants.clientId, _nextPresenceData);
        },
        child: const Text('Update'),
      );

  Widget leaveRealtimePresence() => TextButton(
        onPressed: () async {
          await channel.presence.leave(_nextPresenceData);
        },
        child: const Text('Leave'),
      );

  @override
  Widget build(BuildContext context) {
    final latestMessage = useState<ably.PresenceMessage?>(null);
    final isSubscribed = useState(false);
    final presenceMembers = useState<List<ably.PresenceMessage>>([]);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Presence',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: createChannelPresenceSubscribeButton(
                  latestMessage,
                  channel.state,
                  isSubscribed,
                ),
              ),
              Expanded(
                child: createChannelPresenceUnsubscribeButton(isSubscribed),
              ),
            ],
          ),
          Text(
            'Presence Message from channel:'
            ' ${latestMessage.value?.data}',
          ),
          Row(
            children: [
              Expanded(child: enterRealtimePresence()),
              Expanded(child: updateRealtimePresence()),
              Expanded(child: leaveRealtimePresence()),
            ],
          ),
          getRealtimeChannelPresence(presenceMembers),
          ...presenceMembers.value
              .map((m) => Text('${m.id}:${m.clientId}:${m.data}')),
          PaginatedResultViewer<ably.PresenceMessage>(
            title: 'Presence history',
            query: () => channel.presence
                .history(const ably.RealtimeHistoryParams(limit: 10)),
            builder: (context, message, _) => TextRow(
              'clientId',
              '${message.id}:${message.clientId}:${message.data}',
            ),
          ),
        ],
      ),
    );
  }
}

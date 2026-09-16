import 'package:ably_pubsub_device/ably_pubsub_device.dart' as ably;
import 'package:ably_example/constants.dart';
import 'package:ably_example/ui/api_key_service.dart';

class AblyService {
  late final ably.RealtimeClient realtime;
  late final ApiKeyProvision apiKeyProvision;

  AblyService({required this.apiKeyProvision}) {
    realtime = ably.RealtimeClient(
      options: ably.ClientOptions(
        key: apiKeyProvision.key,
        clientId: Constants.clientId,
        logLevel: ably.LogLevel.verbose,
        endpoint: apiKeyProvision.source == ApiKeySource.env
            ? null
            : Constants.sandboxEndpoint,
        autoConnect: false,
      ),
    );
  }
}

class ExampleMessages {
  static ably.Message message = const ably.Message(
    data: {
      'I am': null,
      'and': {
        'also': 'nested',
        'too': {'deep': true},
      },
    },
  );

  static List<ably.Message> messages = [
    const ably.Message(data: 42),
    const ably.Message(data: {'are': 'you'}),
    const ably.Message(data: 'ok?'),
    const ably.Message(
      data: [
        false,
        {
          'I am': null,
          'and': {
            'also': 'nested',
            'too': {'deep': true},
          },
        }
      ],
    ),
  ];
}

import 'package:ably_example/ui/ably_service.dart';
import 'package:ably_example/ui/api_key_service.dart';
import 'package:ably_example/ui/push_notifications/push_notifications_sliver.dart';
import 'package:ably_example/ui/realtime_sliver.dart';
import 'package:ably_example/ui/system_details_sliver.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiKeyProvision = await ApiKeyService().getOrProvisionApiKey();
  final ablyService = AblyService(apiKeyProvision: apiKeyProvision);
  runApp(AblyDartExampleApp(ablyService: ablyService));
}

class AblyDartExampleApp extends StatelessWidget {
  final AblyService ablyService;

  const AblyDartExampleApp({
    required this.ablyService,
    super.key,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Ably Dart Example App'),
          ),
          body: Center(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 36),
              children: [
                SystemDetailsSliver(
                  apiKeyProvision: ablyService.apiKeyProvision,
                ),
                const Divider(),
                RealtimeSliver(ablyService),
                const Divider(),
                const PushNotificationsSliver(),
              ],
            ),
          ),
        ),
      );
}

import 'package:ably_example/constants.dart';
import 'package:ably_example/ui/api_key_service.dart';
import 'package:ably_example/ui/text_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

// ignore: must_be_immutable
class SystemDetailsSliver extends HookWidget {
  ApiKeyProvision apiKeyProvision;

  SystemDetailsSliver({
    required this.apiKeyProvision,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'System Details',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        TextRow('Running on', defaultTargetPlatform.name),
        const TextRow('Ably SDK version', '0.3.0'),
        TextRow('Ably Client ID', Constants.clientId),
        TextRow('Ably API key', hideApiKeySecret(apiKeyProvision.key)),
        if (apiKeyProvision.source != ApiKeySource.env)
          RichText(
            text: const TextSpan(
              style: TextStyle(color: Colors.black),
              children: [
                TextSpan(
                  text: 'Warning: ',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: 'Ably API key is not configured! Application uses '
                      'auto-provisioned sandbox key. Please follow '
                      'instructions in the repository Readme file to '
                      'setup the sample with your API key.',
                ),
              ],
            ),
          ),
      ],
    );
  }

  String hideApiKeySecret(String apiKey) {
    final keyComponents = apiKey.split(':');
    if (keyComponents.length != 2) {
      return apiKey;
    }
    final publicApiKey = keyComponents[0];
    final apiKeySecret = keyComponents[1];
    return '$publicApiKey:${'*' * apiKeySecret.length}';
  }
}

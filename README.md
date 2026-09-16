[![pub package](https://img.shields.io/pub/v/ably_pubsub_device.svg)](https://pub.dev/packages/ably_pubsub_device)
[![License](https://img.shields.io/github/license/ably/ably-pubsub-dart)](https://github.com/ably/ably-pubsub-dart/blob/main/LICENSE)

---

# Ably Pub/Sub Dart SDK

Build any realtime experience using Ably's Pub/Sub Dart SDK. A pure Dart implementation with no platform dependencies.

(Note: at this stage, this implementation does not support push messaging, so continue to use [ably-flutter](https://github.com/ably/ably-flutter) if you need that.)

Ably Pub/Sub provides flexible APIs that deliver features such as pub-sub messaging, message history, presence, and push notifications. Utilizing Ably's realtime messaging platform, applications benefit from its highly performant, reliable, and scalable infrastructure.

Find out more:

- [Ably Pub/Sub docs](https://ably.com/docs/basics)
- [Ably Pub/Sub Examples](https://ably.com/examples?product=pubsub)

---

## Getting started

Everything you need to get started with Ably:

- [Getting started with Pub/Sub](https://ably.com/docs/getting-started/setup)

---

## Supported platforms

This is a pure Dart package with no platform-specific dependencies. It runs anywhere Dart runs.

| Platform | Support |
|----------|---------|
| Dart     | >=3.0.0 |

---

## Installation

The Dart SDK is available as a [pub.dev package](https://pub.dev/packages/ably_pubsub_device). Add it to your `pubspec.yaml`:

```yaml
dependencies:
  ably_pubsub_device: ^0.2.0
```

Then run:

```sh
dart pub get
```

## Usage

Use the Pub/Sub client for persistent connections with live message delivery:

```dart
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

// Create a client
final client = PubSubClient(
  options: ClientOptions(key: 'your-ably-api-key', clientId: 'me'),
);

// Wait for connection
await client.connection.once(ConnectionEvent.connected);
print('Connected to Ably');

// Get a channel and subscribe
final channel = client.channels.get('test-channel');
await channel.subscribe(listener: (message) {
  print('Received: ${message.data}');
});

// Publish a message
await channel.publish(name: 'greeting', data: 'hello world');

// Retrieve message history
final history = await channel.history();
for (final message in history.items) {
  print('${message.name}: ${message.data}');
}
```

---

## Contribute

Read the [CONTRIBUTING.md](./CONTRIBUTING.md) guidelines to contribute to Ably.

---

## Releases

The [CHANGELOG.md](./CHANGELOG.md) contains details of the latest releases for this SDK. You can also view all Ably releases on [changelog.ably.com](https://changelog.ably.com).

---

## Support, feedback, and troubleshooting

For help or technical support, visit Ably's [support page](https://ably.com/support) or [GitHub Issues](https://github.com/ably/ably-pubsub-dart/issues) for community-reported bugs and discussions.

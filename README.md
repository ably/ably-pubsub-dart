[![pub.dev: ably_pubsub_device](https://img.shields.io/pub/v/ably_pubsub_device?label=ably_pubsub_device)](https://pub.dev/packages/ably_pubsub_device)
[![License](https://badgen.net/github/license/ably/ably-pubsub-dart)](https://github.com/ably/ably-pubsub-dart/blob/main/LICENSE)

# Ably Pub/Sub Dart SDK

The Dart SDK for [Ably Pub/Sub](https://ably.com/docs/basics): publish and subscribe to
channels, and use message history and presence, from Dart and Flutter apps.

> [!WARNING]
> This SDK is experimental. Its API can change between 0.x releases.

## Overview

This SDK provides the device package only, for end-user apps. There is no server package; for
backends, use a server SDK such as [JavaScript](https://github.com/ably/ably-pubsub-js),
[Java](https://github.com/ably/ably-pubsub-java), [Go](https://github.com/ably/ably-pubsub-go),
[.NET](https://github.com/ably/ably-pubsub-dotnet), [Python](https://github.com/ably/ably-pubsub-python),
[PHP](https://github.com/ably/ably-pubsub-php) or [Ruby](https://github.com/ably/ably-pubsub-ruby).

| Package | Use it for | Entry point |
|---------|-----------|-------------|
| `ably_pubsub_device` | Applications on end-user devices | `createClient` |

## Requirements

Dart 3.0 or later. The SDK runs on every platform that provides `dart:io` (the Dart VM, and Flutter
on Android, iOS, macOS, Linux and Windows).

## Installation

```bash
dart pub add ably_pubsub_device
```

In a Flutter app, run `flutter pub add ably_pubsub_device` instead.

## Quick start

Authenticate a device with tokens issued by your own server, through `authUrl` or `authCallback`.
Never embed an API key in an app that runs on an end-user device.

```dart
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

Future<void> main() async {
  final client = createClient(
    ClientOptions(
      authUrl: 'https://your-server.example.com/ably-auth',
      clientId: 'me',
    ),
  );

  // The client connects automatically. Subscribing attaches the channel.
  final channel = client.channels.get('test-channel');
  channel.subscribe((Message message) {
    print('Received: ${message.data}');
  });

  await channel.publish(name: 'test-event', data: 'hello world');
}
```

To get tokens from your own code instead of a URL, set `authCallback`. It can return a token
string, a `TokenDetails` or a `TokenRequest`.

## Migrating from 0.2.x

Version 0.3.0 renames the package and creates clients with `createClient`.

| | 0.2.x | 0.3.x |
|---|---|---|
| Package | `ably` | `ably_pubsub_device` |
| Import | `package:ably/ably.dart` | `package:ably_pubsub_device/ably_pubsub_device.dart` |
| Realtime client | `RealtimeClient(options: ...)` | `createClient(...)` |
| REST client | `RestClient(options: ...)` | Removed; use `createClient(...)` |

See [UPGRADING.md](https://github.com/ably/ably-pubsub-dart/blob/main/UPGRADING.md#02x-to-03x) for all other changes.

## Common configuration

Pass options to `createClient` in a `ClientOptions` object.

### Endpoint

`endpoint` selects the Ably host for HTTP requests and the realtime connection.

```dart
final client = createClient(
  ClientOptions(
    authUrl: 'https://your-server.example.com/ably-auth',
    clientId: 'me',
    endpoint: 'nonprod:sandbox',
  ),
);
```

- Never put a port in `endpoint`: `localhost:8080` is not a hostname and does not resolve.
- Set the port with `tlsPort`, or with `port` when TLS is off.
- With TLS off (`tls: false`), use token authentication.

### Logging

Set `logLevel` to a `LogLevel` value: `none`, `error`, `warn`, `info`, `debug` or `verbose`. The
default is `warn`. By default, the SDK prints log lines with `print`. To send them elsewhere, set
`logHandler`:

```dart
final client = createClient(
  ClientOptions(
    authUrl: 'https://your-server.example.com/ably-auth',
    clientId: 'me',
    logLevel: LogLevel.debug,
    logHandler: (LogLevel level, String message, Map<String, dynamic> context) {
      print('${level.name}: $message $context');
    },
  ),
);
```

## Known limitations

- Web is not supported. Browsers do not provide `dart:io`, which the SDK needs.
- The SDK cannot activate a device for push notifications. For push in a Flutter app, use the
  [Flutter SDK](https://github.com/ably/ably-pubsub-flutter).

## Further reading

- [Ably Pub/Sub documentation](https://ably.com/docs/basics) and [examples](https://ably.com/examples?product=pubsub)
- [Token authentication](https://ably.com/docs/auth/token)
- [UPGRADING.md](https://github.com/ably/ably-pubsub-dart/blob/main/UPGRADING.md): upgrading from 0.2.x
- [CHANGELOG.md](https://github.com/ably/ably-pubsub-dart/blob/main/CHANGELOG.md): release notes; all Ably releases are listed on [changelog.ably.com](https://changelog.ably.com)
- [example/](https://github.com/ably/ably-pubsub-dart/tree/main/example): a Flutter example app

## Contributing

Read [CONTRIBUTING.md](https://github.com/ably/ably-pubsub-dart/blob/main/CONTRIBUTING.md) before contributing; it also describes the release
process.

## Support, feedback and troubleshooting

For help, visit Ably's [support page](https://ably.com/support). Report bugs and compatibility
problems on [GitHub Issues](https://github.com/ably/ably-pubsub-dart/issues).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/ably/ably-pubsub-dart/blob/main/LICENSE).

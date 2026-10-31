# Changelog

## [0.3.0](https://github.com/ably/ably-pubsub-dart/tree/v0.3.0)

[Full Changelog](https://github.com/ably/ably-pubsub-dart/compare/v0.2.0...v0.3.0)

The 0.3.0 release makes this SDK the device side of Ably Pub/Sub for Dart. The package is renamed `ably_pubsub_device` and is meant for code that runs on an end user's device, such as a Flutter app. It offers a single client, `PubSubClient`, created with the top-level `createClient` function. The package name is also what coding assistants see in the install step and the import line, so they get the choice right too.

The REST client is removed. `PubSubClient` already provides the HTTP-backed operations a device needs, so there is one client to learn rather than two.

Every application needs changes. There are no deprecation shims.

Below is an overview of the major changes in this release. Please refer to the [upgrade guide](./UPGRADING.md) for the full details, including how to replace each removed API.

### Package rename

- The package is renamed from `ably` to `ably_pubsub_device`. Depend on `ably_pubsub_device: ^0.3.0` and import `package:ably_pubsub_device/ably_pubsub_device.dart` instead of `package:ably/ably.dart`.

### Client creation and naming

- `RealtimeClient` is renamed `PubSubClient`.
- Clients are created with `createClient(options)` instead of constructors. `PubSubClient` has no public constructor, so `RealtimeClient(options: ...)` and `RealtimeClient.fromKey(key)` are gone. Use `createClient(ClientOptions.fromKey(key))` for the key shorthand.
- `PubSubClient` can't be constructed or extended, but it can still be referenced, mocked and implemented.

### Removed REST client

- `RestClient`, `RestChannels`, `RestChannel`, `RestChannelOptions`, `RestPresence` and `RestPresenceParams` are removed. Use `PubSubClient` and its `RealtimeChannel`, `RealtimeChannelOptions` and `RealtimePresence` instead.
- `PubSubClient` channels provide `publish`, `history`, `status`, `getMessage`, message update, delete and append, and presence history over the same HTTP endpoints. The client keeps `time()`, `stats()`, `request()` and `push`.

## [0.2.0](https://github.com/ably/ably-pubsub-dart/tree/v0.2.0)

[Full Changelog](https://github.com/ably/ably-pubsub-dart/compare/v0.1.0...v0.2.0)

- Refine heartbeat handling logic and improve logging for protocol message sending [#10](https://github.com/ably/ably-pubsub-dart/pull/10)

## [0.1.0](https://github.com/ably/ably-pubsub-dart/tree/v0.1.0)

Initial release of the Ably Pub/Sub Dart SDK.

- REST client with full API support (publish, history, presence, stats)
- Authentication (API key, token auth, token callbacks, authUrl)
- Realtime client with connection state management
- Fallback host support
- Pagination support

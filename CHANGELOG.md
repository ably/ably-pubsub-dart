# Changelog

## Unreleased

**Breaking changes**

- Removed the REST client. `RestClient`, `RestChannels`, `RestChannel`,
  `RestPresence`, `RestPresenceParams`, `RestChannelOptions`, and the batch
  operation types (`BatchPublishSpec`, `BatchResult`, `BatchPresenceResponse`)
  are no longer part of the public API. Use `PubSubClient`, whose channels
  provide `publish`, `history`, `status`, `getMessage`, message
  update/delete/append and presence history over the same HTTP endpoints, and
  which retains `time()`, `stats()`, `request()` and `push`.
- Renamed `RealtimeClient` to `PubSubClient`. The channel, presence and
  annotation types keep their `Realtime*` names, which follow the Ably features
  specification.

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

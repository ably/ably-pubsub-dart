# Upgrading

## 0.2.x to 0.3.x

This release removes the REST client, renames `RealtimeClient` to `PubSubClient`,
and replaces the client constructors with a `createClient` function. Every
application needs changes; there are no deprecation shims.


### At a glance

| 0.2.x | 0.3.x |
|---|---|
| `RealtimeClient(options: o)` | `createClient(o)` |
| `RealtimeClient.fromKey(k)` | `createClient(ClientOptions.fromKey(k))` |
| `RestClient(options: o)` | `createClient(o)` |
| `RestClient.fromKey(k)` | `createClient(ClientOptions.fromKey(k))` |
| `RealtimeClient` | `PubSubClient` |
| `RestClient` | `PubSubClient` |
| `RestChannels` | `RealtimeChannels` |
| `RestChannel` | `RealtimeChannel` |
| `RestChannelOptions` | `RealtimeChannelOptions` |
| `RestPresence` | `RealtimePresence` |
| `RestPresenceParams` | named arguments on `presence.get` |
| `BatchPublishSpec`, `BatchResult` | removed — use `client.request` |
| `BatchPresenceResponse` | removed — use `client.request` |

`RestHistoryParams`, `RealtimeHistoryParams`, `RestAnnotations`, `Message`,
`PresenceMessage`, `PaginatedResult`, `ClientOptions`, `Stats`, the `Push`
types and the error types are unchanged.

### Creating a client

`PubSubClient` has no public constructor. Create clients with the top-level
`createClient` function, which takes `ClientOptions`:

```dart
// 0.2.x
final client = RealtimeClient(options: ClientOptions(key: 'app.key:secret'));
final client = RealtimeClient.fromKey('app.key:secret');
final rest = RestClient(options: ClientOptions(key: 'app.key:secret'));

// 0.3.x
final client = createClient(ClientOptions(key: 'app.key:secret'));
final client = createClient(ClientOptions.fromKey('app.key:secret'));
```

`RealtimeClient(options: ..., key: ...)`, where `key` overrode `options.key`, has
no direct replacement. Build the options you want instead:

```dart
// 0.2.x
RealtimeClient(options: baseOptions, key: 'app.key:secret');

// 0.3.x
createClient(baseOptions.copyWith(key: 'app.key:secret'));
```

`PubSubClient(...)` and `class MyClient extends PubSubClient` are both compile
errors in 0.3.x. The type is still yours to reference, mock and `implements`.

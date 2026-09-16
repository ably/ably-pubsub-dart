# Contributing to ably-pubsub-dart

## Contributing

1. Fork it
2. When pulling to local, make sure to also pull the submodules (`git submodule init && git submodule update`)
3. Create your feature branch (`git checkout -b my-new-feature`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Ensure you have added suitable tests and the test suite is passing (`dart test`)
6. Push the branch (`git push origin my-new-feature`)
7. Create a new Pull Request

## Development setup

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) >= 3.0.0

### Installing dependencies

```sh
dart pub get
```

## Test suite

### Running tests

```sh
# All tests
dart test

# Specific test file
dart test test/realtime/unit/channels/channel_publish_test.dart

# With stack traces (helpful for debugging)
dart test --chain-stack-traces
```

### Tests alignment with the Ably features specification

Each test should reference the [Ably features specification](https://sdk.ably.com/builds/ably/specification/main/features/) point it covers. Test names must include spec IDs:

```dart
group('RTN17 - Fallback host behavior', () {
  test('RTN17a - Falls back on DNS failure', () { ... });
  test('RTN17b - Falls back on connection refused', () { ... });
});
```

### Test architecture

Unit tests use mock clients for deterministic testing:

- **MockHttpClient** (`test/helpers/mock_http_client.dart`) - simulates HTTP responses, DNS errors, timeouts
- **MockWebSocketClient** (`test/helpers/mock_websocket_client.dart`) - simulates WebSocket connections, protocol messages

See `test/helpers/MOCK_HTTP_CLIENT.md` for detailed mock usage.

Integration tests run against the Ably sandbox environment and require network access.

## Release process

1. Ensure that all work intended for this release has landed to `main`
2. Create a release branch named like `release/0.2.0`
3. Update the version number in `pubspec.yaml`
4. Update the CHANGELOG.md with customer-affecting changes since the last release
5. Create a PR for the release branch
6. Once the release PR is merged to `main`, create a git tag (e.g. `git tag v0.2.0 && git push origin v0.2.0`)
7. Create a GitHub release based on the new tag
8. Publish to pub.dev: `dart pub publish`
9. Update the [Ably Changelog](https://changelog.ably.com/) with these changes

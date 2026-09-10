# MockPushStorage - In-Memory Push Storage Mock

The `MockPushStorage` provides an in-memory implementation of `PushKeyValueStorage` for push activation unit tests. It follows the portable helper spec at `specification/uts/rest/unit/helpers/mock_push_platform.md`.

## Overview

Push activation persists device and state-machine state via a `PushKeyValueStorage` supplied through `ClientOptions.pushPlatform`. The mock lets tests inspect exactly what was persisted, seed pre-existing state to simulate an app restart, and inject storage failures.

## Basic Usage

```dart
final storage = MockPushStorage();

final options = ClientOptions(
  key: 'appId.keyId:keySecret',
  pushPlatform: PushPlatformConfig(
    platform: 'android',
    formFactor: 'phone',
    storage: storage,
    requestToken: () async =>
        const PushDeviceToken(transportType: 'fcm', token: 'fcm-token-1'),
  ),
);
final client = RestClient.forTesting(options: options, httpClient: mockHttp);
```

## Inspection and Seeding

```dart
// Assert end state (what is persisted once an operation settles)
final persisted = storage.dump();  // Map<String, String> copy
expect(persisted['ably.push.deviceId'], isNotNull);

// Simulate state persisted by a previous app run
storage.seed({
  'ably.push.deviceId': 'device-1',
  'ably.push.activationState': 'WaitingForNewPushDeviceDetails',
});
```

The standard keys are `ably.push.deviceId`, `ably.push.deviceSecret`, `ably.push.deviceIdentityToken`, `ably.push.pushRecipient`, and `ably.push.activationState`.

## Operation Observation and Interception

The `onOperation` handler mirrors `MockHttpClient`'s `onRequest`: it is called synchronously **before** each operation is applied. Capture operations into a **local** list to assert sequence and timing:

```dart
final capturedOperations = <StorageOperation>[];
final storage = MockPushStorage(onOperation: capturedOperations.add);
```

If the handler throws, the operation fails (its future completes with the thrown error) and the contents are unmodified — use this for per-key fault injection:

```dart
final storage = MockPushStorage(onOperation: (op) {
  if (op.type == 'setItem' && op.key == 'ably.push.deviceIdentityToken') {
    throw StateError('storage unavailable');
  }
});
```

## Blanket Fault Injection

```dart
storage.failWrites = true;  // setItem / removeItem fail
storage.failReads = true;   // getItem fails
```

The `onOperation` handler runs first; the flags apply to operations the handler did not fail.

## API Reference

### Constructor

```dart
MockPushStorage({void Function(StorageOperation op)? onOperation})
```

### StorageOperation

- `type: String` - `'getItem'` | `'setItem'` | `'removeItem'`
- `key: String`
- `value: String?` - setItem only

### Methods and Fields

- `Future<String?> getItem(String key)`
- `Future<void> setItem(String key, String value)`
- `Future<void> removeItem(String key)`
- `Map<String, String> dump()` - synchronous copy of current contents
- `void seed(Map<String, String> entries)` - pre-populate contents
- `bool failWrites`, `bool failReads` - blanket fault injection

## Examples

See `mock_push_storage_test.dart` for working examples. Run the tests:

```bash
dart test test/helpers/mock_push_storage_test.dart
```

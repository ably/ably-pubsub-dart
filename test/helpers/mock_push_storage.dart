import 'package:ably/ably.dart';

/// Callback for observing or intercepting storage operations in
/// [MockPushStorage].
typedef StorageOperationHandler = void Function(StorageOperation op);

/// The record passed to [MockPushStorage.onOperation].
class StorageOperation {
  StorageOperation({
    required this.type,
    required this.key,
    this.value,
  });

  /// The operation type: 'getItem', 'setItem' or 'removeItem'.
  final String type;

  /// The key the operation applies to.
  final String key;

  /// The value being written (setItem only).
  final String? value;

  @override
  String toString() =>
      'StorageOperation($type, $key${value != null ? ', $value' : ''})';
}

/// An in-memory mock implementation of [PushKeyValueStorage] for push
/// activation unit tests.
///
/// Follows the portable helper spec
/// `specification/uts/rest/unit/helpers/mock_push_platform.md`:
///
/// - [dump] inspects the current contents synchronously
/// - [seed] pre-populates contents to simulate a previous app run
/// - [failWrites] / [failReads] inject blanket storage failures
/// - [onOperation] observes or intercepts each operation; it runs
///   synchronously before the operation is applied, and if it throws, the
///   operation's future completes with that error and the contents are
///   unmodified
///
/// Example:
/// ```dart
/// final capturedOperations = <StorageOperation>[];
/// final storage = MockPushStorage(
///   onOperation: capturedOperations.add,
/// );
/// ```
class MockPushStorage implements PushKeyValueStorage {
  MockPushStorage({this.onOperation});

  /// Optional observation/interception handler, mirroring MockHttpClient's
  /// onRequest: called synchronously before each operation is applied. If
  /// the handler throws, the operation fails (the returned future completes
  /// with the thrown error) and the contents are not modified.
  final StorageOperationHandler? onOperation;

  /// When true, setItem and removeItem fail. The [onOperation] handler runs
  /// first; this flag applies to operations the handler did not fail.
  bool failWrites = false;

  /// When true, getItem fails. The [onOperation] handler runs first; this
  /// flag applies to operations the handler did not fail.
  bool failReads = false;

  final Map<String, String> _contents = {};

  /// Returns a copy of the current contents.
  Map<String, String> dump() => Map.of(_contents);

  /// Pre-populates the contents, simulating state persisted by a previous
  /// app run. Existing entries with the same keys are overwritten.
  void seed(Map<String, String> entries) {
    _contents.addAll(entries);
  }

  @override
  Future<String?> getItem(String key) async {
    onOperation?.call(StorageOperation(type: 'getItem', key: key));
    if (failReads) {
      throw StateError('MockPushStorage: reads are failing (failReads)');
    }
    return _contents[key];
  }

  @override
  Future<void> setItem(String key, String value) async {
    onOperation
        ?.call(StorageOperation(type: 'setItem', key: key, value: value));
    if (failWrites) {
      throw StateError('MockPushStorage: writes are failing (failWrites)');
    }
    _contents[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    onOperation?.call(StorageOperation(type: 'removeItem', key: key));
    if (failWrites) {
      throw StateError('MockPushStorage: writes are failing (failWrites)');
    }
    _contents.remove(key);
  }
}

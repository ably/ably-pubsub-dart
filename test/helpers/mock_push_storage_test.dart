import 'package:test/test.dart';

import 'mock_push_storage.dart';

void main() {
  group('MockPushStorage', () {
    test('getItem/setItem/removeItem round-trip', () async {
      final storage = MockPushStorage();

      expect(await storage.getItem('ably.push.deviceId'), isNull);

      await storage.setItem('ably.push.deviceId', 'device-1');
      expect(await storage.getItem('ably.push.deviceId'), 'device-1');

      await storage.setItem('ably.push.deviceId', 'device-2');
      expect(await storage.getItem('ably.push.deviceId'), 'device-2');

      await storage.removeItem('ably.push.deviceId');
      expect(await storage.getItem('ably.push.deviceId'), isNull);

      // Removing an absent key is a no-op
      await storage.removeItem('ably.push.deviceId');
    });

    test('dump returns a copy of the current contents', () async {
      final storage = MockPushStorage();
      await storage.setItem('a', '1');
      await storage.setItem('b', '2');

      final dumped = storage.dump();
      expect(dumped, {'a': '1', 'b': '2'});

      // Mutating the dump does not affect the storage
      dumped['a'] = 'mutated';
      expect(await storage.getItem('a'), '1');
    });

    test('seed pre-populates contents', () async {
      final storage = MockPushStorage();
      storage.seed({
        'ably.push.deviceId': 'device-1',
        'ably.push.activationState': 'WaitingForNewPushDeviceDetails',
      });

      expect(await storage.getItem('ably.push.deviceId'), 'device-1');
      expect(
        await storage.getItem('ably.push.activationState'),
        'WaitingForNewPushDeviceDetails',
      );
      expect(storage.dump(), hasLength(2));
    });

    test('failWrites rejects setItem and removeItem, not getItem', () async {
      final storage = MockPushStorage();
      await storage.setItem('a', '1');

      storage.failWrites = true;
      await expectLater(storage.setItem('a', '2'), throwsStateError);
      await expectLater(storage.removeItem('a'), throwsStateError);

      // Contents unmodified, reads unaffected
      expect(await storage.getItem('a'), '1');

      storage.failWrites = false;
      await storage.setItem('a', '2');
      expect(await storage.getItem('a'), '2');
    });

    test('failReads rejects getItem, not writes', () async {
      final storage = MockPushStorage();
      await storage.setItem('a', '1');

      storage.failReads = true;
      await expectLater(storage.getItem('a'), throwsStateError);

      // Writes unaffected
      await storage.setItem('b', '2');
      await storage.removeItem('a');

      storage.failReads = false;
      expect(await storage.getItem('a'), isNull);
      expect(await storage.getItem('b'), '2');
    });

    test('onOperation captures operations in order with details', () async {
      final capturedOperations = <StorageOperation>[];
      final storage = MockPushStorage(onOperation: capturedOperations.add);

      await storage.setItem('a', '1');
      await storage.getItem('a');
      await storage.removeItem('a');

      expect(capturedOperations, hasLength(3));

      expect(capturedOperations[0].type, 'setItem');
      expect(capturedOperations[0].key, 'a');
      expect(capturedOperations[0].value, '1');

      expect(capturedOperations[1].type, 'getItem');
      expect(capturedOperations[1].key, 'a');
      expect(capturedOperations[1].value, isNull);

      expect(capturedOperations[2].type, 'removeItem');
      expect(capturedOperations[2].key, 'a');
      expect(capturedOperations[2].value, isNull);
    });

    test('onOperation runs synchronously before the operation is applied',
        () async {
      late MockPushStorage storage;
      Map<String, String>? contentsDuringHandler;
      storage = MockPushStorage(
        onOperation: (op) {
          contentsDuringHandler = storage.dump();
        },
      );

      final future = storage.setItem('a', '1');
      // Handler ran synchronously at call time, before the op was applied
      expect(contentsDuringHandler, isEmpty);
      await future;
      expect(storage.dump(), {'a': '1'});
    });

    test('onOperation throw fails the op without modifying contents', () async {
      final storage = MockPushStorage(
        onOperation: (op) {
          if (op.type == 'setItem' &&
              op.key == 'ably.push.deviceIdentityToken') {
            throw StateError('storage unavailable');
          }
        },
      );

      await storage.setItem('a', '1');

      await expectLater(
        storage.setItem('ably.push.deviceIdentityToken', 'token'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'storage unavailable',
          ),
        ),
      );

      // Contents unmodified by the failed op
      expect(storage.dump(), {'a': '1'});
    });

    test('onOperation throw on getItem rejects the read', () async {
      final storage = MockPushStorage(
        onOperation: (op) {
          if (op.type == 'getItem') {
            throw StateError('read intercepted');
          }
        },
      );
      await storage.setItem('a', '1');
      await expectLater(storage.getItem('a'), throwsStateError);
    });
  });
}

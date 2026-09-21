@Tags(['integration'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/poll_until.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Rest Mutable Messages', (protocol) {
    // Helper to build a key-authenticated REST client pointed at sandbox.
    RestClient buildClient() => RestClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );

    // ---------------------------------------------------------------------------
    // RSL1n — Publish returns serials
    // ---------------------------------------------------------------------------
    group('RSL1n - Publish returns serials', () {
      // UTS: rest/integration/RSL11/get-message-by-serial-0
      test('RSL1n - single publish returns non-empty serials list', () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl1n-single-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final result = await channel.publish(name: 'event', data: 'hello');
        expect(result.serials, isNotEmpty);
        expect(result.serials.first, isNotNull);
        expect(result.serials.first, isNotEmpty);
      });

      // UTS: rest/integration/RSL1n/publish-returns-serials-0
      test(
          'RSL1n - batch publish (multiple messages) returns serials per message',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl1n-batch-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final result = await channel.publish(
          messages: [
            const Message(name: 'event1', data: 'data1'),
            const Message(name: 'event2', data: 'data2'),
          ],
        );
        expect(result.serials.length, equals(2));
        expect(result.serials[0], isNotNull);
        expect(result.serials[1], isNotNull);
      });
    });

    // ---------------------------------------------------------------------------
    // RSL11 — getMessage retrieves published message
    // ---------------------------------------------------------------------------
    group('RSL11 - getMessage', () {
      test(
          'RSL11 - publish message, retrieve via getMessage, verify fields and action',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl11-get-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final publishResult =
            await channel.publish(name: 'my-event', data: 'my-data');
        expect(publishResult.serials, isNotEmpty);
        final serial = publishResult.serials.first!;

        final message = await channel.getMessage(serial);
        expect(message.name, equals('my-event'));
        expect(message.data, equals('my-data'));
        expect(message.serial, equals(serial));
        expect(message.action, equals(MessageAction.messageCreate));
      });
    });

    // ---------------------------------------------------------------------------
    // RSL15 update — update message and poll until action==messageUpdate
    // ---------------------------------------------------------------------------
    group('RSL15 - updateMessage', () {
      // UTS: rest/integration/RSL15/update-message-0
      test(
          'RSL15 update - publish then update, poll until action==messageUpdate',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl15-update-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        // Publish original message
        final publishResult =
            await channel.publish(name: 'original', data: 'original-data');
        final serial = publishResult.serials.first!;

        // Retrieve the message to get a Message object with the serial
        final originalMessage = await channel.getMessage(serial);
        expect(originalMessage.serial, equals(serial));

        // Update the message
        final updateResult = await channel.updateMessage(
          originalMessage.copyWith(name: 'updated', data: 'updated-data'),
          operation: const MessageOperation(description: 'edited'),
        );
        expect(updateResult.versionSerial, isNotNull);

        // Poll until the retrieved message shows the update
        final updated = await pollUntil(
          () async {
            final msg = await channel.getMessage(serial);
            return msg.action == MessageAction.messageUpdate ? msg : null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(updated.name, equals('updated'));
        expect(updated.data, equals('updated-data'));
        expect(updated.action, equals(MessageAction.messageUpdate));
      });
    });

    // ---------------------------------------------------------------------------
    // RSL15 delete — delete message and poll until action==messageDelete
    // ---------------------------------------------------------------------------
    group('RSL15 - deleteMessage', () {
      // UTS: rest/integration/RSL15/delete-message-1
      test(
          'RSL15 delete - publish then delete, poll until action==messageDelete',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl15-delete-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final publishResult =
            await channel.publish(name: 'to-delete', data: 'will-be-deleted');
        final serial = publishResult.serials.first!;

        final originalMessage = await channel.getMessage(serial);

        final deleteResult = await channel.deleteMessage(originalMessage);
        expect(deleteResult.versionSerial, isNotNull);

        // Poll until action reflects deletion
        final deleted = await pollUntil(
          () async {
            final msg = await channel.getMessage(serial);
            return msg.action == MessageAction.messageDelete ? msg : null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(deleted.action, equals(MessageAction.messageDelete));
      });
    });

    // ---------------------------------------------------------------------------
    // RSL14 — getMessageVersions returns history of versions
    // ---------------------------------------------------------------------------
    group('RSL14 - getMessageVersions', () {
      // UTS: rest/integration/RSL14/get-message-versions-0
      test('RSL14 - publish and update twice, getMessageVersions returns >= 3',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl14-versions-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        // Publish original
        final publishResult =
            await channel.publish(name: 'v1', data: 'version-1');
        final serial = publishResult.serials.first!;

        final msg1 = await channel.getMessage(serial);

        // First update
        await channel.updateMessage(
          msg1.copyWith(name: 'v2', data: 'version-2'),
          operation: const MessageOperation(description: 'first update'),
        );

        // Second update — need to get the current message first
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final msg2 = await channel.getMessage(serial);

        await channel.updateMessage(
          msg2.copyWith(name: 'v3', data: 'version-3'),
          operation: const MessageOperation(description: 'second update'),
        );

        // Poll until versions list has at least 3 entries (create + 2 updates)
        final versions = await pollUntil(
          () async {
            final result = await channel.getMessageVersions(serial);
            return result.items.length >= 3 ? result : null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(versions.items.length, greaterThanOrEqualTo(3));
      });
    });

    // ---------------------------------------------------------------------------
    // RSL15 append — appendMessage with operation, returns versionSerial
    // ---------------------------------------------------------------------------
    group('RSL15 - appendMessage', () {
      // UTS: rest/integration/RSL15/append-message-2
      test(
          'RSL15 append - publish then append, returns UpdateDeleteResult with versionSerial',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsl15-append-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        final publishResult =
            await channel.publish(name: 'base', data: 'base-data');
        final serial = publishResult.serials.first!;

        final originalMessage = await channel.getMessage(serial);

        final appendResult = await channel.appendMessage(
          originalMessage.copyWith(data: 'appended-data'),
          operation: const MessageOperation(description: 'appended'),
        );

        expect(appendResult.versionSerial, isNotNull);
        expect(appendResult.versionSerial, isNotEmpty);
      });
    });

    // ---------------------------------------------------------------------------
    // RSAN1/RSAN2/RSAN3 — Full annotation lifecycle
    // ---------------------------------------------------------------------------
    group('RSAN1/RSAN2/RSAN3 - Annotation lifecycle', () {
      test(
          'RSAN1+RSAN2+RSAN3 - publish, annotate, poll get, then delete annotation',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsan-lifecycle-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        // Publish a message
        final publishResult =
            await channel.publish(name: 'annotatable', data: 'data');
        final serial = publishResult.serials.first!;

        // RSAN1: Publish annotation
        await channel.annotations.publish(
          serial,
          const Annotation(type: 'com.ably.reactions', name: 'like'),
        );

        // RSAN3: Poll until annotation appears
        final annotationsResult = await pollUntil(
          () async {
            final result = await channel.annotations.get(serial);
            return result.items.isNotEmpty ? result : null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(annotationsResult.items, isNotEmpty);
        final annotation = annotationsResult.items.first;
        expect(annotation.type, equals('com.ably.reactions'));

        // RSAN2: Delete annotation
        await channel.annotations.delete(
          serial,
          const Annotation(type: 'com.ably.reactions', name: 'like'),
        );
      });

      // UTS: rest/integration/RSAN3/get-annotations-paginated-0
      test(
          'RSAN3 paginated - publish 2 annotations, poll get until >= 2, verify PaginatedResult',
          () async {
        final client = buildClient();
        addTearDown(client.close);

        final channelName =
            'mutable:rsan-paginated-${DateTime.now().millisecondsSinceEpoch}';
        final channel = client.channels.get(channelName);

        // Publish a message
        final publishResult =
            await channel.publish(name: 'multi-annotate', data: 'data');
        final serial = publishResult.serials.first!;

        // Publish two annotations
        await channel.annotations.publish(
          serial,
          const Annotation(type: 'com.ably.reactions', name: 'like'),
        );
        await channel.annotations.publish(
          serial,
          const Annotation(type: 'com.ably.reactions', name: 'heart'),
        );

        // RSAN3: Poll until 2 annotations visible
        final result = await pollUntil(
          () async {
            final r = await channel.annotations.get(serial);
            return r.items.length >= 2 ? r : null;
          },
          timeout: const Duration(seconds: 15),
        );

        // Verify PaginatedResult type and annotation fields
        expect(result, isA<PaginatedResult<Annotation>>());
        expect(result.items.length, greaterThanOrEqualTo(2));
        for (final ann in result.items) {
          expect(ann.type, equals('com.ably.reactions'));
          expect(ann.name, isNotNull);
        }
      });
    });
  });
}

@Tags(['integration'])
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/wait_for_state.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Realtime Mutable Messages Integration Tests', (protocol) {
    /// Helper to create a Realtime client.
    PubSubClient buildClient({bool autoConnect = false}) => createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: autoConnect,
          ),
        );

    /// Unique mutable channel name.
    String uniqueChannel(String prefix) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rand = Random().nextInt(100000);
      return 'mutable:$prefix-$ts-$rand';
    }

    /// Connects a client and waits until CONNECTED.
    Future<void> connectAndWait(PubSubClient client) async {
      client.connect();
      await waitForConnectionState(
        client.connection,
        ConnectionState.connected,
      );
    }

    group('Mutable messages', () {
      // -------------------------------------------------------------------------
      // RTL32 - Update message via realtime observed on subscriber
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTL32/update-message-observed-0
      test(
        'RTL32 - Update message via realtime observed on subscriber',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtl32-update');
          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          await channelA.attach();
          await channelB.attach();

          // Subscribe on channel B and collect messages
          final messages = <Message>[];
          channelB.subscribe((msg) {
            messages.add(msg);
          });

          // Publish original message
          await channelA.publish(name: 'original', data: 'v1');

          // Wait for the create message
          await pollUntil(() async => messages.isNotEmpty ? true : null);
          expect(messages.length, equals(1));
          final serial = messages.first.serial;
          expect(serial, isNotNull);
          expect(serial, isNotEmpty);

          // Update the message
          final updateResult = await channelA.updateMessage(
            Message(serial: serial, name: 'updated', data: 'v2'),
            operation: const MessageOperation(description: 'edited'),
          );
          expect(updateResult.versionSerial, isNotNull);

          // Wait for the update message
          await pollUntil(
            () async => messages.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // Assert: first is MESSAGE_CREATE, second is MESSAGE_UPDATE
          expect(messages[0].action, equals(MessageAction.messageCreate));
          expect(messages[1].action, equals(MessageAction.messageUpdate));
          expect(messages[1].serial, equals(serial));
          expect(messages[1].name, equals('updated'));
          expect(messages[1].data, equals('v2'));
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      // -------------------------------------------------------------------------
      // RTL32 - Delete message via realtime observed on subscriber
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTL32/delete-message-observed-1
      test(
        'RTL32 - Delete message via realtime observed on subscriber',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtl32-delete');
          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          await channelA.attach();
          await channelB.attach();

          final messages = <Message>[];
          channelB.subscribe((msg) {
            messages.add(msg);
          });

          // Publish, capture serial
          await channelA.publish(name: 'to-delete', data: 'will-be-deleted');
          await pollUntil(() async => messages.isNotEmpty ? true : null);
          final serial = messages.first.serial!;

          // Delete the message
          await channelA.deleteMessage(Message(serial: serial));

          // Wait for the delete event
          await pollUntil(
            () async => messages.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          expect(messages[1].action, equals(MessageAction.messageDelete));
          expect(messages[1].serial, equals(serial));
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      // -------------------------------------------------------------------------
      // RTL32 - Append message via realtime observed on subscriber
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTL32/append-message-observed-2
      test(
        'RTL32 - Append message via realtime observed on subscriber',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtl32-append');
          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          await channelA.attach();
          await channelB.attach();

          final messages = <Message>[];
          channelB.subscribe((msg) {
            messages.add(msg);
          });

          // Publish, capture serial
          await channelA.publish(name: 'base', data: 'base-data');
          await pollUntil(() async => messages.isNotEmpty ? true : null);
          final serial = messages.first.serial!;

          // Append to the message
          await channelA.appendMessage(
            Message(serial: serial, data: 'appended'),
            operation: const MessageOperation(description: 'reply'),
          );

          // Wait for the append event
          await pollUntil(
            () async => messages.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          expect(messages[1].action, equals(MessageAction.messageAppend));
          expect(messages[1].serial, equals(serial));
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      // -------------------------------------------------------------------------
      // RTL32 - Full mutation lifecycle: create, update, append, delete
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTL32/full-mutation-lifecycle-3
      test(
        'RTL32 - Full mutation lifecycle: create, update, append, delete',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtl32-lifecycle');
          final channelA = clientA.channels.get(channelName);
          final channelB = clientB.channels.get(channelName);

          await channelA.attach();
          await channelB.attach();

          final messages = <Message>[];
          channelB.subscribe((msg) {
            messages.add(msg);
          });

          // 1. Publish (create)
          await channelA.publish(name: 'lifecycle', data: 'v1');
          await pollUntil(() async => messages.isNotEmpty ? true : null);
          final serial = messages.first.serial!;

          // 2. Update
          await channelA.updateMessage(
            Message(serial: serial, name: 'lifecycle', data: 'v2'),
            operation: const MessageOperation(description: 'update'),
          );
          await pollUntil(
            () async => messages.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // 3. Append
          await channelA.appendMessage(
            Message(serial: serial, data: 'appended'),
            operation: const MessageOperation(description: 'append'),
          );
          await pollUntil(
            () async => messages.length >= 3 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // 4. Delete
          await channelA.deleteMessage(
            Message(serial: serial),
            operation: const MessageOperation(description: 'delete'),
          );
          await pollUntil(
            () async => messages.length >= 4 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // Assert all 4 messages in order
          expect(messages[0].action, equals(MessageAction.messageCreate));
          expect(messages[1].action, equals(MessageAction.messageUpdate));
          expect(messages[2].action, equals(MessageAction.messageAppend));
          expect(messages[3].action, equals(MessageAction.messageDelete));
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      // -------------------------------------------------------------------------
      // RTL28, RTL31 - getMessage and getMessageVersions from realtime channel
      // -------------------------------------------------------------------------
      test(
        'RTL28, RTL31 - getMessage and getMessageVersions from realtime channel',
        () async {
          final client = buildClient();
          addTearDown(() async {
            await client.close();
          });

          await connectAndWait(client);

          final channelName = uniqueChannel('rtl28-rtl31');
          final channel = client.channels.get(channelName);
          await channel.attach();

          // Subscribe and collect messages to capture serials
          final messages = <Message>[];
          channel.subscribe((msg) {
            messages.add(msg);
          });

          // Publish original
          await channel.publish(name: 'v1', data: 'version-1');
          await pollUntil(() async => messages.isNotEmpty ? true : null);
          final serial = messages.first.serial!;

          // Update twice
          await channel.updateMessage(
            Message(serial: serial, name: 'v2', data: 'version-2'),
            operation: const MessageOperation(description: 'first update'),
          );
          await pollUntil(
            () async => messages.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          await channel.updateMessage(
            Message(serial: serial, name: 'v3', data: 'version-3'),
            operation: const MessageOperation(description: 'second update'),
          );
          await pollUntil(
            () async => messages.length >= 3 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // Wait for propagation
          await Future<void>.delayed(const Duration(seconds: 2));

          // RTL28: getMessage returns the latest version
          final latest = await channel.getMessage(serial);
          expect(latest.data, equals('version-3'));
          expect(latest.action, equals(MessageAction.messageUpdate));
          expect(latest.serial, equals(serial));

          // RTL31: getMessageVersions returns at least 3 versions
          final versionsResult = await pollUntil(
            () async {
              final result = await channel.getMessageVersions(serial);
              return result.items.length >= 3 ? result : null;
            },
            timeout: const Duration(seconds: 15),
          );
          expect(versionsResult.items.length, greaterThanOrEqualTo(3));
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      // -------------------------------------------------------------------------
      // RTAN1, RTAN2, RTAN4 - Annotation publish and delete via realtime
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTAN1/annotation-publish-delete-0
      test(
        'RTAN1, RTAN2, RTAN4 - Annotation publish and delete via realtime',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtan1-rtan2');
          const annotationModes = RealtimeChannelOptions(
            modes: [
              ChannelMode.publish,
              ChannelMode.subscribe,
              ChannelMode.annotationPublish,
              ChannelMode.annotationSubscribe,
            ],
          );
          final channelA = clientA.channels.get(channelName, annotationModes);
          final channelB = clientB.channels.get(channelName, annotationModes);

          await channelA.attach();
          await channelB.attach();

          // Publish a message first to get its serial
          final msgEvents = <Message>[];
          channelA.subscribe((msg) {
            msgEvents.add(msg);
          });

          await channelA.publish(name: 'annotatable', data: 'some-data');
          await pollUntil(() async => msgEvents.isNotEmpty ? true : null);
          final messageSerial = msgEvents.first.serial!;

          // Subscribe to annotations on channel B
          final annotationEvents = <Annotation>[];
          channelB.annotations.subscribe((annotation) {
            annotationEvents.add(annotation);
          });

          // RTAN1: Publish annotation
          await channelA.annotations.publish(
            messageSerial,
            const Annotation(type: 'com.ably.reactions', name: 'like'),
          );

          // Wait for annotation create event
          await pollUntil(
            () async => annotationEvents.isNotEmpty ? true : null,
            timeout: const Duration(seconds: 15),
          );

          expect(
            annotationEvents.first.action,
            equals(AnnotationAction.annotationCreate),
          );
          expect(annotationEvents.first.type, equals('com.ably.reactions'));
          expect(annotationEvents.first.name, equals('like'));
          expect(
            annotationEvents.first.messageSerial,
            equals(messageSerial),
          );

          // RTAN2: Delete annotation
          await channelA.annotations.delete(
            messageSerial,
            const Annotation(type: 'com.ably.reactions', name: 'like'),
          );

          // Wait for annotation delete event
          await pollUntil(
            () async => annotationEvents.length >= 2 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          expect(
            annotationEvents[0].action,
            equals(AnnotationAction.annotationCreate),
          );
          expect(
            annotationEvents[1].action,
            equals(AnnotationAction.annotationDelete),
          );
          expect(annotationEvents[1].type, equals('com.ably.reactions'));
          expect(annotationEvents[1].name, equals('like'));
          expect(
            annotationEvents[1].messageSerial,
            equals(messageSerial),
          );
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      // -------------------------------------------------------------------------
      // RTAN4c - Annotation subscribe with type filtering
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTAN4c/annotation-type-filtering-0
      test(
        'RTAN4c - Annotation subscribe with type filtering',
        () async {
          final clientA = buildClient();
          final clientB = buildClient();
          addTearDown(() async {
            await clientA.close();
            await clientB.close();
          });

          await connectAndWait(clientA);
          await connectAndWait(clientB);

          final channelName = uniqueChannel('rtan4c-filter');
          const annotationModes = RealtimeChannelOptions(
            modes: [
              ChannelMode.publish,
              ChannelMode.subscribe,
              ChannelMode.annotationPublish,
              ChannelMode.annotationSubscribe,
            ],
          );
          final channelA = clientA.channels.get(channelName, annotationModes);
          final channelB = clientB.channels.get(channelName, annotationModes);

          await channelA.attach();
          await channelB.attach();

          // Publish a message to annotate
          final msgEvents = <Message>[];
          channelA.subscribe((msg) {
            msgEvents.add(msg);
          });

          await channelA.publish(name: 'filterable', data: 'data');
          await pollUntil(() async => msgEvents.isNotEmpty ? true : null);
          final messageSerial = msgEvents.first.serial!;

          // Subscribe with type filter (reactions only) and unfiltered
          final filteredEvents = <Annotation>[];
          final unfilteredEvents = <Annotation>[];

          channelB.annotations.subscribe(
            (annotation) {
              filteredEvents.add(annotation);
            },
            type: 'com.ably.reactions',
          );

          channelB.annotations.subscribe((annotation) {
            unfilteredEvents.add(annotation);
          });

          // Publish 3 annotations: reactions/like, comments/comment, reactions/heart
          await channelA.annotations.publish(
            messageSerial,
            const Annotation(type: 'com.ably.reactions', name: 'like'),
          );
          await channelA.annotations.publish(
            messageSerial,
            const Annotation(type: 'com.ably.comments', name: 'comment'),
          );
          await channelA.annotations.publish(
            messageSerial,
            const Annotation(type: 'com.ably.reactions', name: 'heart'),
          );

          // Wait until unfiltered has all 3
          await pollUntil(
            () async => unfilteredEvents.length >= 3 ? true : null,
            timeout: const Duration(seconds: 15),
          );

          // Filtered should have exactly 2 (reactions only)
          expect(filteredEvents.length, equals(2));
          expect(filteredEvents[0].type, equals('com.ably.reactions'));
          expect(filteredEvents[0].name, equals('like'));
          expect(filteredEvents[1].type, equals('com.ably.reactions'));
          expect(filteredEvents[1].name, equals('heart'));

          // Unfiltered should have all 3
          expect(unfilteredEvents.length, equals(3));
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      // -------------------------------------------------------------------------
      // RTAN4d - Annotation subscribe implicitly attaches channel
      // -------------------------------------------------------------------------
      // UTS: realtime/integration/RTAN4d/annotation-implicit-attach-0
      test(
        'RTAN4d - Annotation subscribe implicitly attaches channel',
        () async {
          final client = buildClient();
          addTearDown(() async {
            await client.close();
          });

          await connectAndWait(client);

          final channelName = uniqueChannel('rtan4d-implicit');
          final channel = client.channels.get(channelName);

          // Assert channel starts as initialized
          expect(channel.state, equals(ChannelState.initialized));

          // Subscribe to annotations without explicitly attaching
          channel.annotations.subscribe((annotation) {
            // no-op listener
          });

          // Wait until the channel becomes attached
          await pollUntil(
            () async => channel.state == ChannelState.attached ? true : null,
            timeout: const Duration(seconds: 15),
          );

          expect(channel.state, equals(ChannelState.attached));
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });
  });
}

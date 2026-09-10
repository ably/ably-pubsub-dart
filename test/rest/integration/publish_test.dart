@Tags(['integration'])
library;

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';

import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/test_channel_name.dart';
import '../../helpers/poll_until.dart';

void main() {
  late TestApp testApp;

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Rest Publish', (protocol) {
    // ---------------------------------------------------------------------------
    // RSL1d — Publish with restricted key fails
    // ---------------------------------------------------------------------------
    group('RSL1d - Publish with restricted key', () {
      test(
          'RSL1d - publish to random channel with channel-restricted key '
          'fails with 40160', () async {
        // keys[2] has capabilities restricted to specific channels
        // (channel0-channel6 only). A random channel name will not match.
        final client = RestClient(
          options: ClientOptions(
            key: testApp.keys[2].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
        addTearDown(client.close);

        final channelName = testChannelName('rsl1d-restricted');

        try {
          await client.channels
              .get(channelName)
              .publish(name: 'test', data: 'hello');
          fail('Expected AblyException for capability violation');
        } on AblyException catch (e) {
          expect(
            e.code,
            equals(40160),
            reason: 'Expected Ably capability error 40160, got ${e.code}',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // RSL1n — Publish returns serials
    // ---------------------------------------------------------------------------
    group('RSL1n - Publish returns serials', () {
      late RestClient client;

      setUp(() {
        client = RestClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
      });

      tearDown(() async {
        await client.close();
      });

      // UTS: rest/integration/RSL1n/publish-result-serials-0
      test('RSL1n - single message publish returns non-empty serials list',
          () async {
        final channelName = testChannelName('rsl1n-single');
        final result = await client.channels
            .get(channelName)
            .publish(name: 'event', data: 'payload');

        expect(result, isA<PublishResult>());
        expect(
          result.serials,
          isNotEmpty,
          reason: 'Single publish should return at least one serial',
        );
      });

      // UTS: rest/integration/RSL1d/publish-failure-error-0
      test('RSL1n - batch publish returns serials for each message', () async {
        final channelName = testChannelName('rsl1n-batch');
        final messages = [
          const Message(name: 'evt1', data: 'a'),
          const Message(name: 'evt2', data: 'b'),
          const Message(name: 'evt3', data: 'c'),
        ];

        final result =
            await client.channels.get(channelName).publish(messages: messages);

        expect(result, isA<PublishResult>());
        expect(
          result.serials.length,
          equals(messages.length),
          reason: 'Serials list length should match the number of messages',
        );
      });
    });

    // ---------------------------------------------------------------------------
    // RSL1k5 — Idempotent publish (same message ID published 3 times)
    // ---------------------------------------------------------------------------
    group('RSL1k5 - Idempotent publish', () {
      test(
          'RSL1k5 - publishing the same Message.id 3 times results in exactly '
          '1 message in history', () async {
        // Use a key client with idempotentRestPublishing disabled so we can
        // control the message ID explicitly.
        final client = RestClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            idempotentRestPublishing: false,
          ),
        );
        addTearDown(client.close);

        final channelName = testChannelName('rsl1k5-idempotent');
        const fixedId = 'idempotent-test-message-id-001';

        // Publish the same message ID three times.
        for (var i = 0; i < 3; i++) {
          await client.channels.get(channelName).publish(
                message:
                    const Message(id: fixedId, name: 'event', data: 'data'),
              );
        }

        // Poll history until we get results, then assert exactly 1 message.
        final history = await pollUntil(
          () async {
            final page = await client.channels.get(channelName).history();
            if (page.items.isNotEmpty) return page;
            return null;
          },
          timeout: const Duration(seconds: 15),
        );

        expect(
          history.items.length,
          equals(1),
          reason: 'Idempotent publish of the same message ID 3 times should '
              'result in exactly 1 message in history',
        );
      });
    });

    // ---------------------------------------------------------------------------
    // RSL1l1 — Publish params _forceNack
    // ---------------------------------------------------------------------------
    group('RSL1l1 - Publish params _forceNack', () {
      test('RSL1l1 - publish with _forceNack=true fails with error code 40099',
          () async {
        final client = RestClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
        addTearDown(client.close);

        final channelName = testChannelName('rsl1l1-forcenack');

        try {
          await client.channels.get(channelName).publish(
            name: 'event',
            data: 'data',
            params: {'_forceNack': 'true'},
          );
          fail('Expected AblyException for _forceNack');
        } on AblyException catch (e) {
          expect(
            e.code,
            equals(40099),
            reason: 'Expected error code 40099 for _forceNack, got ${e.code}',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // RSL1m4 — ClientId mismatch
    // ---------------------------------------------------------------------------
    group('RSL1m4 - ClientId mismatch', () {
      test(
          'RSL1m4 - publish with different clientId than token clientId '
          'fails with 40012', () async {
        // Obtain a token bound to clientId "alice"
        final keyClient = RestClient(
          options: ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
        addTearDown(keyClient.close);

        final tokenDetails = await keyClient.auth.requestToken(
          tokenParams: const TokenParams(clientId: 'alice'),
        );

        // Create a client using that token
        final tokenClient = RestClient(
          options: ClientOptions(
            token: tokenDetails.token,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
          ),
        );
        addTearDown(tokenClient.close);

        final channelName = testChannelName('rsl1m4-clientid');

        // Publishing a Message with a *different* clientId should be rejected
        try {
          await tokenClient.channels.get(channelName).publish(
                message: const Message(
                  name: 'event',
                  data: 'data',
                  clientId: 'bob', // mismatch: token is bound to "alice"
                ),
              );
          fail('Expected AblyException for clientId mismatch');
        } on AblyException catch (e) {
          expect(
            e.code,
            equals(40012),
            reason: 'Expected clientId mismatch error 40012, got ${e.code}',
          );
        }
      });
    });
  });
}

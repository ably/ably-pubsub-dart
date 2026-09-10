import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import '../../../helpers/mock_http_client.dart';
import '../../../helpers/mock_websocket_client.dart';
import '../../../helpers/protocol_message_helpers.dart';
import '../../../helpers/test_channel_name.dart';

/// Unit tests for RealtimeChannel annotations (RTL26, RTAN1–RTAN5).
///
/// These tests use mocked WebSocket to verify annotation publish, delete,
/// subscribe, unsubscribe, and mode checking.
///
/// Spec: uts/test/realtime/unit/channels/channel_annotations.md
void main() {
  // Flag bits
  const publishFlag = 1 << 17; // 131072 - PUBLISH
  const annotationPublishFlag = 1 << 21; // 2097152 - ANNOTATION_PUBLISH
  const annotationSubscribeFlag = 1 << 22; // 4194304 - ANNOTATION_SUBSCRIBE
  const publishAndAnnotationPublish = publishFlag | annotationPublishFlag;
  const allAnnotationFlags =
      publishFlag | annotationPublishFlag | annotationSubscribeFlag;

  // ---------------------------------------------------------------------------
  // RTL26 — channel.annotations returns RealtimeAnnotations
  // ---------------------------------------------------------------------------

  group('RTL26 - channel.annotations returns RealtimeAnnotations', () {
    // UTS: realtime/unit/RTL26/annotations-attribute-type-0
    test('exposes annotations attribute of correct type', () {
      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get('test-RTL26');
      expect(channel.annotations, isA<RealtimeAnnotations>());

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN1a, RTAN1c — publish sends ANNOTATION ProtocolMessage
  // ---------------------------------------------------------------------------

  group('RTAN1a, RTAN1c - publish sends ANNOTATION ProtocolMessage', () {
    // UTS: realtime/unit/RTAN1a/publish-sends-annotation-0
    test('sends ANNOTATION PM with ANNOTATION_CREATE action', () async {
      final channelName = testChannelName('RTAN1-publish');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          } else if (msg.action == ProtocolAction.annotation) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction', name: 'like'),
      );

      final annotationPms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.annotation)
          .toList();
      expect(annotationPms, hasLength(1));

      final pm = annotationPms[0];
      expect(pm.channel, equals(channelName));
      expect(pm.annotations, hasLength(1));

      final ann = pm.annotations![0] as Map<String, dynamic>;
      expect(ann['action'], equals(0)); // ANNOTATION_CREATE
      expect(ann['messageSerial'], equals('msg-serial-1'));
      expect(ann['type'], equals('com.example.reaction'));
      expect(ann['name'], equals('like'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN1a — publish validates type is required
  // ---------------------------------------------------------------------------

  group('RTAN1a - publish validates type is required', () {
    // UTS: realtime/unit/RTAN1a/validates-type-required-1
    test('throws error code 40003 when type is missing', () async {
      final channelName = testChannelName('RTAN1a-validate');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      try {
        await channel.annotations.publish(
          'msg-serial-1',
          const Annotation(name: 'like'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN1a — publish encodes data per RSL4
  // ---------------------------------------------------------------------------

  group('RTAN1a - publish encodes data per RSL4', () {
    // UTS: realtime/unit/RTAN1a/encodes-data-json-2
    test('JSON data encoded as string with encoding field', () async {
      final channelName = testChannelName('RTAN1a-encode');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          } else if (msg.action == ProtocolAction.annotation) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(
          type: 'com.example.data',
          data: {
            'key': 'value',
            'nested': {'a': 1},
          },
        ),
      );

      final annotationPms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.annotation)
          .toList();
      expect(annotationPms, hasLength(1));

      final ann = annotationPms[0].annotations![0] as Map<String, dynamic>;
      expect(ann['data'], isA<String>());
      expect(ann['encoding'], equals('json'));
      expect(
        json.decode(ann['data'] as String),
        equals({
          'key': 'value',
          'nested': {'a': 1},
        }),
      );

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN1b — publish fails in FAILED channel state
  // ---------------------------------------------------------------------------

  group('RTAN1b - publish fails in FAILED channel state', () {
    // UTS: realtime/unit/RTAN1b/publish-channel-state-0
    test('annotation publish rejected when channel is FAILED', () async {
      final channelName = testChannelName('RTAN1b');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Send ERROR to put channel in FAILED state
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.error,
                channel: channelName,
                error: const ErrorInfo(code: 40160, message: 'Not permitted'),
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Attempt attach — will fail, putting channel in FAILED
      try {
        await channel.attach();
      } catch (_) {
        // Expected
      }

      expect(channel.state, equals(ChannelState.failed));

      try {
        await channel.annotations.publish(
          'msg-serial-1',
          const Annotation(type: 'com.example.reaction', name: 'like'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN1d — publish indicates success/failure via ACK/NACK
  // ---------------------------------------------------------------------------

  group('RTAN1d - publish success via ACK', () {
    // UTS: realtime/unit/RTL6c2/queued-when-disconnected-1
    test('publish resolves on ACK', () async {
      final channelName = testChannelName('RTAN1d-ack');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          } else if (msg.action == ProtocolAction.annotation) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      // Should resolve without error
      await channel.annotations.publish(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction', name: 'like'),
      );
      // If we get here, publish succeeded
    });
  });

  group('RTAN1d - publish failure via NACK', () {
    // UTS: realtime/unit/RTAN1d/publish-ack-nack-0
    test('publish rejects on NACK with error code', () async {
      final channelName = testChannelName('RTAN1d-nack');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          } else if (msg.action == ProtocolAction.annotation) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessage(
                action: ProtocolAction.nack,
                msgSerial: msg.msgSerial,
                count: 1,
                error: const ErrorInfo(
                  code: 40160,
                  message: 'Not permitted',
                ),
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      try {
        await channel.annotations.publish(
          'msg-serial-1',
          const Annotation(type: 'com.example.reaction', name: 'like'),
        );
        fail('Expected AblyException');
      } catch (e) {
        expect(e, isA<AblyException>());
        expect((e as AblyException).errorInfo?.code, equals(40160));
      }

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN2a — delete sends ANNOTATION_DELETE
  // ---------------------------------------------------------------------------

  group('RTAN2a - delete sends ANNOTATION_DELETE', () {
    // UTS: realtime/unit/RTAN2a/delete-sends-annotation-0
    test('sends ANNOTATION PM with ANNOTATION_DELETE action', () async {
      final channelName = testChannelName('RTAN2-delete');
      final capturedMessages = <ProtocolMessage>[];

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          capturedMessages.add(msg);
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishAndAnnotationPublish,
              ),
            );
          } else if (msg.action == ProtocolAction.annotation) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.ack(
                msgSerial: msg.msgSerial!,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      await channel.annotations.delete(
        'msg-serial-1',
        const Annotation(type: 'com.example.reaction', name: 'like'),
      );

      final annotationPms = capturedMessages
          .where((pm) => pm.action == ProtocolAction.annotation)
          .toList();
      expect(annotationPms, hasLength(1));

      final ann = annotationPms[0].annotations![0] as Map<String, dynamic>;
      expect(ann['action'], equals(1)); // ANNOTATION_DELETE
      expect(ann['messageSerial'], equals('msg-serial-1'));
      expect(ann['type'], equals('com.example.reaction'));
      expect(ann['name'], equals('like'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN3a — get is identical to RestAnnotations#get
  // ---------------------------------------------------------------------------

  group('RTAN3a - get delegates to REST API', () {
    // UTS: realtime/unit/RTAN1a/publish-sends-annotation-0.1
    test('sends GET to annotations endpoint via HTTP', () async {
      final channelName = testChannelName('RTAN3a');

      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(200, [
            {
              'id': 'ann-1',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'clientId': 'user-1',
              'serial': 'ann-serial-1',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000000000,
            },
          ]);
        },
      );

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
        httpClient: mockHttp,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final result = await channel.annotations.get('msg-serial-1');

      expect(result, isA<PaginatedResult<Annotation>>());
      expect(result.items, hasLength(1));
      expect(result.items[0].type, equals('com.example.reaction'));
      expect(result.items[0].name, equals('like'));

      // Verify it used HTTP, not WebSocket
      expect(mockHttp.capturedRequests, hasLength(1));
      expect(mockHttp.capturedRequests[0].method, equals('GET'));

      mockHttp.dispose();
      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN4a, RTAN4b — subscribe delivers annotations from ANNOTATION PM
  // ---------------------------------------------------------------------------

  group('RTAN4a, RTAN4b - subscribe delivers annotations', () {
    // UTS: realtime/unit/RTAN4a/subscribe-delivers-annotations-0
    test('decoded Annotation objects delivered to listeners', () async {
      final channelName = testChannelName('RTAN4-subscribe');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final receivedAnnotations = <Annotation>[];
      channel.annotations.subscribe((annotation) {
        receivedAnnotations.add(annotation);
      });

      // Server sends ANNOTATION ProtocolMessage with two annotations
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          annotations: [
            {
              'id': 'ann-1',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'clientId': 'user-1',
              'serial': 'ann-serial-1',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000000000,
            },
            {
              'id': 'ann-2',
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'heart',
              'clientId': 'user-2',
              'serial': 'ann-serial-2',
              'messageSerial': 'msg-serial-1',
              'timestamp': 1700000001000,
            },
          ],
        ),
      );

      await _pumpEventQueue();

      expect(receivedAnnotations, hasLength(2));

      final ann1 = receivedAnnotations[0];
      expect(ann1, isA<Annotation>());
      expect(ann1.id, equals('ann-1'));
      expect(ann1.action, equals(AnnotationAction.annotationCreate));
      expect(ann1.type, equals('com.example.reaction'));
      expect(ann1.name, equals('like'));
      expect(ann1.clientId, equals('user-1'));
      expect(ann1.serial, equals('ann-serial-1'));
      expect(ann1.messageSerial, equals('msg-serial-1'));
      expect(ann1.timestamp, equals(1700000000000));

      final ann2 = receivedAnnotations[1];
      expect(ann2.name, equals('heart'));
      expect(ann2.clientId, equals('user-2'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN4c — subscribe with type filter
  // ---------------------------------------------------------------------------

  group('RTAN4c - subscribe with type filter', () {
    // UTS: realtime/unit/RTAN4c/subscribe-type-filter-0
    test('only delivers matching annotation types', () async {
      final channelName = testChannelName('RTAN4c-filter');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final reactionAnnotations = <Annotation>[];
      channel.annotations.subscribe(
        (annotation) {
          reactionAnnotations.add(annotation);
        },
        type: 'com.example.reaction',
      );

      // Server sends mixed annotation types
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          annotations: [
            {
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-1',
              'timestamp': 1700000000000,
            },
            {
              'action': 0,
              'type': 'com.example.comment',
              'name': 'text',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-2',
              'timestamp': 1700000001000,
            },
            {
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'heart',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-3',
              'timestamp': 1700000002000,
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // Only reaction annotations delivered
      expect(reactionAnnotations, hasLength(2));
      expect(reactionAnnotations[0].name, equals('like'));
      expect(reactionAnnotations[1].name, equals('heart'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN4d — subscribe implicitly attaches channel
  // ---------------------------------------------------------------------------

  group('RTAN4d - subscribe implicitly attaches channel', () {
    // UTS: realtime/unit/RTAN4d/subscribe-implicit-attach-0
    test('subscribe triggers implicit attach from INITIALIZED', () async {
      final channelName = testChannelName('RTAN4d-attach');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      // Default attachOnSubscribe is true
      final channel = client.channels.get(channelName);

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      expect(channel.state, equals(ChannelState.initialized));

      channel.annotations.subscribe((annotation) {});

      // Wait for implicit attach to complete
      await _awaitChannelState(channel, ChannelState.attached);

      expect(channel.state, equals(ChannelState.attached));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN4e — warns when ANNOTATION_SUBSCRIBE mode not granted
  // ---------------------------------------------------------------------------

  group('RTAN4e - warns when ANNOTATION_SUBSCRIBE mode not granted', () {
    // UTS: realtime/unit/RTAN4e/subscribe-warns-no-mode-0
    test('logs warning when attached without ANNOTATION_SUBSCRIBE', () async {
      final channelName = testChannelName('RTAN4e-warn');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            // Respond with ATTACHED but WITHOUT ANNOTATION_SUBSCRIBE flag
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: publishFlag, // Only PUBLISH, no ANNOTATION_SUBSCRIBE
              ),
            );
          }
        },
      );

      // Capture log messages to verify warning
      final logMessages = <String>[];
      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          logHandler:
              (LogLevel level, String message, Map<String, dynamic> context) {
            if (level == LogLevel.warn) {
              logMessages.add(message);
            }
          },
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      channel.annotations.subscribe((annotation) {});

      // A warning should have been logged about ANNOTATION_SUBSCRIBE mode
      final found =
          logMessages.any((msg) => msg.contains('ANNOTATION_SUBSCRIBE'));
      expect(
        found,
        isTrue,
        reason: 'Expected a warning about ANNOTATION_SUBSCRIBE mode',
      );

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN4e1 — no warning when not attached and attachOnSubscribe is false
  // ---------------------------------------------------------------------------

  group('RTAN4e1 - no warning when not attached with attachOnSubscribe false',
      () {
    // UTS: realtime/unit/RTAN4e1/no-warn-unattached-0
    test('no ANNOTATION_SUBSCRIBE warning when channel is INITIALIZED',
        () async {
      final channelName = testChannelName('RTAN4e1');

      final mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final logMessages = <String>[];
      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
          logHandler:
              (LogLevel level, String message, Map<String, dynamic> context) {
            if (level == LogLevel.warn) {
              logMessages.add(message);
            }
          },
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );

      // Channel is INITIALIZED, not attached
      expect(channel.state, equals(ChannelState.initialized));

      channel.annotations.subscribe((annotation) {});

      // No warning about ANNOTATION_SUBSCRIBE should be logged
      final found =
          logMessages.any((msg) => msg.contains('ANNOTATION_SUBSCRIBE'));
      expect(
        found,
        isFalse,
        reason: 'No ANNOTATION_SUBSCRIBE warning expected',
      );

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN5a — unsubscribe removes listeners
  // ---------------------------------------------------------------------------

  group('RTAN5a - unsubscribe removes listeners', () {
    // UTS: realtime/unit/RTAN5a/unsubscribe-type-filter-1
    test('unsubscribed listener does not receive further annotations',
        () async {
      final channelName = testChannelName('RTAN5-unsub');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final receivedAnnotations = <Annotation>[];
      void listener(Annotation annotation) {
        receivedAnnotations.add(annotation);
      }

      channel.annotations.subscribe(listener);

      // Send first annotation — should be received
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          annotations: [
            {
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-1',
              'timestamp': 1700000000000,
            },
          ],
        ),
      );

      await _pumpEventQueue();
      expect(receivedAnnotations, hasLength(1));

      // Unsubscribe
      channel.annotations.unsubscribe(listener: listener);

      // Send second annotation — should NOT be received
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          annotations: [
            {
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'heart',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-2',
              'timestamp': 1700000001000,
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // Only the first annotation was received
      expect(receivedAnnotations, hasLength(1));
      expect(receivedAnnotations[0].name, equals('like'));

      mockWs.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // RTAN5a — unsubscribe with type removes only type-filtered listener
  // ---------------------------------------------------------------------------

  group('RTAN5a - unsubscribe with type removes only typed listener', () {
    // UTS: realtime/unit/RTAN5a/unsubscribe-removes-listeners-0
    test('unsubscribing typed listener leaves other typed listeners active',
        () async {
      final channelName = testChannelName('RTAN5a-typed');

      late final MockWebSocketClient mockWs;
      mockWs = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (msg) {
          if (msg.action == ProtocolAction.attach) {
            mockWs.activeConnection!.sendToClient(
              ProtocolMessageHelpers.attached(
                channel: channelName,
                flags: allAnnotationFlags,
              ),
            );
          }
        },
      );

      final client = RealtimeClient.forTesting(
        options: ClientOptions(
          key: 'appId.keyId:keySecret',
          autoConnect: false,
        ),
        webSocketClient: mockWs,
      );

      final channel = client.channels.get(
        channelName,
        const RealtimeChannelOptions(attachOnSubscribe: false),
      );

      client.connect();
      await _awaitConnectionState(
        client.connection,
        ConnectionState.connected,
      );
      await channel.attach();

      final reactionReceived = <Annotation>[];
      final commentReceived = <Annotation>[];

      void reactionListener(Annotation ann) {
        reactionReceived.add(ann);
      }

      void commentListener(Annotation ann) {
        commentReceived.add(ann);
      }

      channel.annotations.subscribe(
        reactionListener,
        type: 'com.example.reaction',
      );
      channel.annotations.subscribe(
        commentListener,
        type: 'com.example.comment',
      );

      // Unsubscribe only reactions
      channel.annotations.unsubscribe(
        listener: reactionListener,
        type: 'com.example.reaction',
      );

      // Send both types
      mockWs.activeConnection!.sendToClient(
        ProtocolMessage(
          action: ProtocolAction.annotation,
          channel: channelName,
          annotations: [
            {
              'action': 0,
              'type': 'com.example.reaction',
              'name': 'like',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-1',
              'timestamp': 1700000000000,
            },
            {
              'action': 0,
              'type': 'com.example.comment',
              'name': 'text',
              'messageSerial': 'msg-serial-1',
              'serial': 'ann-serial-2',
              'timestamp': 1700000001000,
            },
          ],
        ),
      );

      await _pumpEventQueue();

      // Reactions unsubscribed, comments still active
      expect(reactionReceived, isEmpty);
      expect(commentReceived, hasLength(1));
      expect(commentReceived[0].type, equals('com.example.comment'));

      mockWs.dispose();
    });
  });
}

Future<void> _awaitConnectionState(
  Connection connection,
  ConnectionState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (connection.state == targetState) {
    return;
  }
  await connection
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

Future<void> _awaitChannelState(
  RealtimeChannel channel,
  ChannelState targetState, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (channel.state == targetState) {
    return;
  }
  await channel
      .on()
      .firstWhere((change) => change.current == targetState)
      .timeout(timeout);
}

Future<void> _pumpEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

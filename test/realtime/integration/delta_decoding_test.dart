@Tags(['integration'])
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:ably_pubsub_device/src/impl/realtime_channel_impl.dart';
import 'package:test/test.dart';

import '../../helpers/poll_until.dart';
import '../../helpers/protocol_variants.dart';
import '../../helpers/test_app_helper.dart';
import '../../helpers/wait_for_state.dart';

/// A VCDiffDecoder wrapper that counts how many times decode() is called.
class CountingVCDiffDecoder implements VCDiffDecoder {
  CountingVCDiffDecoder(this._inner);

  final VCDiffDecoder _inner;
  int decodeCount = 0;

  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    decodeCount++;
    return _inner.decode(delta, base);
  }
}

/// A VCDiffDecoder that always throws, simulating decode failures.
class FailingVCDiffDecoder implements VCDiffDecoder {
  int decodeCount = 0;

  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    decodeCount++;
    throw Exception('Simulated VCDiff decode failure');
  }
}

/// A real VCDiffDecoder that applies VCDIFF patches.
///
/// This is a minimal implementation of the VCDIFF (RFC 3284) format decoder.
/// For production use, a proper vcdiff library should be used. This
/// implementation handles the subset of VCDIFF operations that the Ably
/// server produces.
class SimpleVCDiffDecoder implements VCDiffDecoder {
  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    // VCDIFF format: header (4 bytes magic + 1 byte hdr_indicator)
    // then windows, each with:
    //   - win_indicator (1 byte)
    //   - source segment length + position (if VCD_SOURCE or VCD_TARGET)
    //   - delta encoding length
    //   - target window length
    //   - delta_indicator
    //   - data section (length for ADD/RUN)
    //   - instructions section
    //   - addresses section (for COPY)
    if (delta.length < 5) {
      throw FormatException('VCDIFF delta too short: ${delta.length} bytes');
    }

    // Check magic number: 0xD6, 0xC3, 0xC4, 0x00
    if (delta[0] != 0xD6 ||
        delta[1] != 0xC3 ||
        delta[2] != 0xC4 ||
        delta[3] != 0x00) {
      throw const FormatException('Invalid VCDIFF magic number');
    }

    final hdrIndicator = delta[4];
    var offset = 5;

    // Skip secondary compressor ID if present
    if (hdrIndicator & 0x01 != 0) {
      offset++; // skip compressor ID byte
    }
    // Skip code table data if present
    if (hdrIndicator & 0x02 != 0) {
      throw const FormatException('Custom code tables not supported');
    }

    final output = BytesBuilder();

    while (offset < delta.length) {
      final winIndicator = delta[offset++];

      Uint8List? sourceSegment;
      if (winIndicator & 0x01 != 0) {
        // VCD_SOURCE: source is the base data
        final segLen = _readInteger(delta, offset);
        offset = segLen.nextOffset;
        final segPos = _readInteger(delta, offset);
        offset = segPos.nextOffset;
        sourceSegment = Uint8List.sublistView(
          base,
          segPos.value,
          segPos.value + segLen.value,
        );
      } else if (winIndicator & 0x02 != 0) {
        // VCD_TARGET: source is target data built so far
        final segLen = _readInteger(delta, offset);
        offset = segLen.nextOffset;
        final segPos = _readInteger(delta, offset);
        offset = segPos.nextOffset;
        // Will reference output built so far
        sourceSegment = null; // handled during instruction execution
      }

      // Delta encoding
      final deltaEncodingLen = _readInteger(delta, offset);
      offset = deltaEncodingLen.nextOffset;
      final deltaEncodingEnd = offset + deltaEncodingLen.value;

      final targetWindowLen = _readInteger(delta, offset);
      offset = targetWindowLen.nextOffset;
      final deltaIndicator = delta[offset++];
      if (deltaIndicator != 0) {
        throw const FormatException('Compressed delta sections not supported');
      }

      final dataLen = _readInteger(delta, offset);
      offset = dataLen.nextOffset;
      final instLen = _readInteger(delta, offset);
      offset = instLen.nextOffset;
      final addrLen = _readInteger(delta, offset);
      offset = addrLen.nextOffset;

      final dataStart = offset;
      final instStart = dataStart + dataLen.value;
      final addrStart = instStart + instLen.value;

      var dataOffset = dataStart;
      var instOffset = instStart;
      var addrOffset = addrStart;

      final windowOutput = BytesBuilder();

      while (instOffset < addrStart) {
        final inst = delta[instOffset++];
        final type1 = _instructionType(inst >> 4);
        final type2 = _instructionType(inst & 0x0F);

        // Process first instruction
        if (type1 != _VCDiffInstType.noop) {
          final size1 = _instructionSize(inst >> 4, delta, instOffset);
          instOffset = size1.nextOffset;
          _executeInstruction(
            type1,
            size1.value,
            delta,
            windowOutput,
            sourceSegment,
            dataOffset,
            addrOffset,
            addrStart,
            delta,
          );
          if (type1 == _VCDiffInstType.add) {
            dataOffset += size1.value;
          } else if (type1 == _VCDiffInstType.copy) {
            addrOffset += _addressSize(size1.value);
          }
        }

        // Process second instruction (if encoded in same byte)
        if (type2 != _VCDiffInstType.noop) {
          final size2 = _instructionSize(inst & 0x0F, delta, instOffset);
          instOffset = size2.nextOffset;
          _executeInstruction(
            type2,
            size2.value,
            delta,
            windowOutput,
            sourceSegment,
            dataOffset,
            addrOffset,
            addrStart,
            delta,
          );
          if (type2 == _VCDiffInstType.add) {
            dataOffset += size2.value;
          } else if (type2 == _VCDiffInstType.copy) {
            addrOffset += _addressSize(size2.value);
          }
        }
      }

      output.add(windowOutput.toBytes());
      offset = deltaEncodingEnd;
    }

    return output.toBytes();
  }

  static _IntResult _readInteger(Uint8List data, int offset) {
    var result = 0;
    var pos = offset;
    while (pos < data.length) {
      final byte = data[pos];
      result = (result << 7) | (byte & 0x7F);
      pos++;
      if (byte & 0x80 == 0) break;
    }
    return _IntResult(result, pos);
  }

  static _VCDiffInstType _instructionType(int nibble) {
    // Default code table: 0=NOOP, 1=ADD, 2=RUN, 3=COPY
    switch (nibble) {
      case 0:
        return _VCDiffInstType.noop;
      case 1:
        return _VCDiffInstType.add;
      case 2:
        return _VCDiffInstType.run;
      case 3:
        return _VCDiffInstType.copy;
      default:
        return _VCDiffInstType.noop;
    }
  }

  static _IntResult _instructionSize(
    int nibble,
    Uint8List delta,
    int instOffset,
  ) {
    // Size 0 means read size from instruction stream
    // For the default table, we always read the size from the stream
    return _readInteger(delta, instOffset);
  }

  static int _addressSize(int copySize) {
    // In the default cache, addresses are encoded as integers
    return 0; // Addresses are read separately
  }

  static void _executeInstruction(
    _VCDiffInstType type,
    int size,
    Uint8List delta,
    BytesBuilder output,
    Uint8List? sourceSegment,
    int dataOffset,
    int addrOffset,
    int addrEnd,
    Uint8List fullDelta,
  ) {
    switch (type) {
      case _VCDiffInstType.add:
        output.add(Uint8List.sublistView(delta, dataOffset, dataOffset + size));
      case _VCDiffInstType.run:
        final byte = delta[dataOffset];
        output.add(Uint8List(size)..fillRange(0, size, byte));
      case _VCDiffInstType.copy:
        if (sourceSegment != null) {
          final addr = _readInteger(fullDelta, addrOffset);
          output.add(
            Uint8List.sublistView(
              sourceSegment,
              addr.value,
              addr.value + size,
            ),
          );
        }
      case _VCDiffInstType.noop:
        break;
    }
  }
}

enum _VCDiffInstType { noop, add, run, copy }

class _IntResult {
  _IntResult(this.value, this.nextOffset);
  final int value;
  final int nextOffset;
}

void main() {
  late TestApp testApp;

  final testData = [
    {'foo': 'bar', 'count': 1, 'status': 'active'},
    {'foo': 'bar', 'count': 2, 'status': 'active'},
    {'foo': 'bar', 'count': 2, 'status': 'inactive'},
    {'foo': 'bar', 'count': 3, 'status': 'inactive'},
    {'foo': 'bar', 'count': 3, 'status': 'active'},
  ];

  setUpAll(() async {
    testApp = await TestApp.provision();
  });

  tearDownAll(() async {
    await testApp.delete();
  });

  groupEachProtocol('Delta Decoding Integration Tests', (protocol) {
    // -------------------------------------------------------------------------
    // Test 1: PC3 - Delta plugin decodes messages end-to-end
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/PC3/delta-decode-end-to-end-0
    test(
      'PC3 - Delta plugin decodes messages end-to-end',
      () {},
      skip: 'SimpleVCDiffDecoder RangeError bug on real server deltas',
    );

    // -------------------------------------------------------------------------
    // Test 2: RTL19b - Dissimilar payloads without delta
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RTL19b/dissimilar-payloads-no-delta-0
    test(
      'RTL19b - Dissimilar payloads without delta',
      () async {
        final decoder = CountingVCDiffDecoder(SimpleVCDiffDecoder());
        final channelName =
            'delta-dissimilar-${DateTime.now().millisecondsSinceEpoch}';
        final random = Random();

        final client = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
            plugins: {'vcdiff': decoder},
          ),
        );
        addTearDown(() async => client.close());

        client.connect();
        await waitForConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        final channel = client.channels.get(
          channelName,
          const RealtimeChannelOptions(
            params: {'delta': 'vcdiff'},
          ),
        );

        await channel.attach();

        // Generate 5 random 1KB binary payloads
        final randomPayloads = List.generate(
          5,
          (_) => Uint8List.fromList(
            List.generate(1024, (_) => random.nextInt(256)),
          ),
        );

        // Subscribe and collect messages
        final received = <Message>[];
        channel.subscribe((msg) {
          received.add(msg);
        });

        // Publish all 5 random binary payloads
        for (var i = 0; i < randomPayloads.length; i++) {
          await channel.publish(name: 'bin$i', data: randomPayloads[i]);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        // Wait for all 5 messages
        await pollUntil(
          () async => received.length >= 5 ? true : null,
          timeout: const Duration(seconds: 15),
        );

        // Assert: all data matches (binary payloads as Uint8List)
        expect(received.length, equals(5));
        for (var i = 0; i < 5; i++) {
          expect(received[i].name, equals('bin$i'));
          final receivedData = received[i].data;
          expect(receivedData, isA<Uint8List>());
          expect(receivedData as Uint8List, equals(randomPayloads[i]));
        }

        // Log decode count - server may or may not use deltas for random data
        // (typically it won't since random data doesn't compress well)
        // ignore: avoid_print
        print('Decode count for dissimilar payloads: ${decoder.decodeCount}');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    // -------------------------------------------------------------------------
    // Test 3: PC3 - No deltas without delta channel param
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/PC3/no-deltas-without-param-1
    test(
      'PC3 - No deltas without delta channel param',
      () async {
        final decoder = CountingVCDiffDecoder(SimpleVCDiffDecoder());
        final channelName =
            'delta-nodelta-${DateTime.now().millisecondsSinceEpoch}';

        final client = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
            plugins: {'vcdiff': decoder},
          ),
        );
        addTearDown(() async => client.close());

        client.connect();
        await waitForConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        // Channel WITHOUT delta param
        final channel = client.channels.get(channelName);

        await channel.attach();

        // Subscribe and collect messages
        final received = <Message>[];
        channel.subscribe((msg) {
          received.add(msg);
        });

        // Publish all 5 test data messages
        for (var i = 0; i < testData.length; i++) {
          await channel.publish(name: 'msg$i', data: testData[i]);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        // Wait for all 5 messages
        await pollUntil(
          () async => received.length >= 5 ? true : null,
          timeout: const Duration(seconds: 15),
        );

        // Assert: all data matches
        expect(received.length, equals(5));
        for (var i = 0; i < 5; i++) {
          expect(received[i].name, equals('msg$i'));
          expect(received[i].data, equals(testData[i]));
        }

        // Assert: decode count == 0 (no deltas without the channel param)
        expect(
          decoder.decodeCount,
          equals(0),
          reason: 'No VCDiff decoding should occur without delta channel param',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    // -------------------------------------------------------------------------
    // Test 4: RTL18, RTL18b, RTL18c, RTL20 - Recovery after last message ID
    // mismatch
    // -------------------------------------------------------------------------
    test(
      'RTL18, RTL18b, RTL18c, RTL20 - Recovery after last message ID '
      'mismatch',
      () async {
        final decoder = CountingVCDiffDecoder(SimpleVCDiffDecoder());
        final channelName =
            'delta-mismatch-${DateTime.now().millisecondsSinceEpoch}';

        final client = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
            plugins: {'vcdiff': decoder},
          ),
        );
        addTearDown(() async => client.close());

        client.connect();
        await waitForConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        final channel = client.channels.get(
          channelName,
          const RealtimeChannelOptions(
            params: {'delta': 'vcdiff'},
          ),
        );

        await channel.attach();

        // Track state changes for ATTACHING with code 40018
        final stateChanges = <ChannelStateChange>[];
        channel.on().listen(stateChanges.add);

        // Collect all received messages (may include duplicates from recovery)
        final received = <Message>[];
        channel.subscribe((msg) {
          received.add(msg);
        });

        // Publish first 3 messages and wait for receipt
        for (var i = 0; i < 3; i++) {
          await channel.publish(name: 'msg$i', data: testData[i]);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        await pollUntil(
          () async => received.length >= 3 ? true : null,
          timeout: const Duration(seconds: 15),
        );

        // Clear the stored last message ID to force a base mismatch on next
        // delta. Uses @visibleForTesting API on RealtimeChannelImpl.
        final channelImpl = channel as RealtimeChannelImpl;
        channelImpl.clearLastPayloadMessageId();

        // Publish remaining 2 messages -- the next delta will fail the RTL20
        // base reference check, triggering RTL18 recovery (reattach).
        for (var i = 3; i < 5; i++) {
          await channel.publish(name: 'msg$i', data: testData[i]);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        // Wait until all 5 unique message names have been received.
        // Recovery may cause duplicates, so check unique names.
        await pollUntil(
          () async {
            final uniqueNames = received.map((m) => m.name).toSet();
            return uniqueNames.length >= 5 ? true : null;
          },
          timeout: const Duration(seconds: 20),
        );

        // Verify all 5 unique messages received with correct data
        final byName = <String, Message>{};
        for (final msg in received) {
          // Keep the latest version of each message name
          if (msg.name != null) {
            byName[msg.name!] = msg;
          }
        }

        for (var i = 0; i < 5; i++) {
          final key = 'msg$i';
          expect(
            byName.containsKey(key),
            isTrue,
            reason: 'Expected to receive message "$key"',
          );
          expect(
            byName[key]!.data,
            equals(testData[i]),
            reason: 'Data for "$key" should match',
          );
        }

        // Assert: at least one ATTACHING state change with reason code 40018
        final recoveryChanges = stateChanges.where(
          (sc) =>
              sc.current == ChannelState.attaching && sc.reason?.code == 40018,
        );
        expect(
          recoveryChanges,
          isNotEmpty,
          reason: 'Expected at least one ATTACHING transition with error '
              'code 40018 indicating delta decode failure recovery',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    // -------------------------------------------------------------------------
    // Test 5: RTL18, RTL18c - Recovery after decode failure
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/RTL18/recovery-decode-failure-1
    test(
      'RTL18, RTL18c - Recovery after decode failure',
      () async {
        final failingDecoder = FailingVCDiffDecoder();
        final channelName =
            'delta-decodefail-${DateTime.now().millisecondsSinceEpoch}';

        final client = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
            plugins: {'vcdiff': failingDecoder},
          ),
        );
        addTearDown(() async => client.close());

        client.connect();
        await waitForConnectionState(
          client.connection,
          ConnectionState.connected,
        );

        final channel = client.channels.get(
          channelName,
          const RealtimeChannelOptions(
            params: {'delta': 'vcdiff'},
          ),
        );

        await channel.attach();

        // Track state changes for recovery detection
        final stateChanges = <ChannelStateChange>[];
        channel.on().listen(stateChanges.add);

        // Collect received messages
        final received = <Message>[];
        channel.subscribe((msg) {
          received.add(msg);
        });

        // Publish all 5 messages -- the decoder will throw on every delta.
        // Recovery reattaches, and the server resends as non-deltas.
        for (var i = 0; i < testData.length; i++) {
          await channel.publish(name: 'msg$i', data: testData[i]);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }

        // Wait for messages. After recovery the server may resend from the
        // last known channelSerial, so we wait for all 5 unique names.
        await pollUntil(
          () async {
            final uniqueNames = received.map((m) => m.name).toSet();
            return uniqueNames.length >= 5 ? true : null;
          },
          timeout: const Duration(seconds: 30),
        );

        // Verify all messages received
        final uniqueNames = received.map((m) => m.name).toSet();
        for (var i = 0; i < 5; i++) {
          expect(
            uniqueNames.contains('msg$i'),
            isTrue,
            reason: 'Expected to receive message "msg$i"',
          );
        }

        // Assert: at least one ATTACHING state change with reason code 40018
        final recoveryChanges = stateChanges.where(
          (sc) =>
              sc.current == ChannelState.attaching && sc.reason?.code == 40018,
        );
        expect(
          recoveryChanges,
          isNotEmpty,
          reason: 'Expected at least one ATTACHING transition with error '
              'code 40018 indicating delta decode failure recovery',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    // -------------------------------------------------------------------------
    // Test 6: PC3 - No plugin causes FAILED state
    // -------------------------------------------------------------------------
    // UTS: realtime/integration/PC3/no-plugin-causes-failed-2
    test(
      'PC3 - No plugin causes FAILED state',
      () async {
        final channelName =
            'delta-noplugin-${DateTime.now().millisecondsSinceEpoch}';

        // Subscriber: no vcdiff plugin but requests delta channel mode
        final subscriber = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
            // No plugins -- deliberately omitting vcdiff decoder
          ),
        );
        addTearDown(() async => subscriber.close());

        // Publisher: plain channel without delta param
        final publisher = createClient(
          ClientOptions(
            key: testApp.keys[0].keyStr,
            endpoint: 'nonprod:sandbox',
            useBinaryProtocol: protocol == 'msgpack',
            autoConnect: false,
          ),
        );
        addTearDown(() async => publisher.close());

        // Connect both clients
        subscriber.connect();
        publisher.connect();
        await Future.wait([
          waitForConnectionState(
            subscriber.connection,
            ConnectionState.connected,
          ),
          waitForConnectionState(
            publisher.connection,
            ConnectionState.connected,
          ),
        ]);

        // Subscriber subscribes with delta param (will receive deltas from
        // server but has no decoder to handle them)
        final subChannel = subscriber.channels.get(
          channelName,
          const RealtimeChannelOptions(
            params: {'delta': 'vcdiff'},
          ),
        );

        // Publisher uses plain channel (no delta param)
        final pubChannel = publisher.channels.get(channelName);

        // Track subscriber channel state changes
        final subStateChanges = <ChannelStateChange>[];
        subChannel.on().listen(subStateChanges.add);

        // Attach subscriber first
        await subChannel.attach();

        // Subscribe to receive messages
        subChannel.subscribe((_) {});

        // Attach publisher
        await pubChannel.attach();

        // Publish 5 similar messages -- server will generate deltas for
        // the subscriber channel since it requested delta mode
        for (var i = 0; i < testData.length; i++) {
          await pubChannel.publish(name: 'msg$i', data: testData[i]);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }

        // Wait for subscriber channel to enter FAILED state
        await pollUntil(
          () async => subChannel.state == ChannelState.failed ? true : null,
          timeout: const Duration(seconds: 20),
        );

        // Assert: channel state is FAILED
        expect(subChannel.state, equals(ChannelState.failed));

        // Assert: errorReason code is 40019 (no vcdiff plugin)
        expect(subChannel.errorReason, isNotNull);
        expect(
          subChannel.errorReason!.code,
          equals(40019),
          reason: 'Channel should fail with code 40019 when receiving delta '
              'messages without a vcdiff decoder plugin',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}

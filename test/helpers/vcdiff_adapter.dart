import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:vcdiff_decoder/vcdiff_decoder.dart' as vcdiff;

/// Adapter wrapping `package:vcdiff` for the Ably VCDiffDecoder interface.
///
/// Used in integration tests where the Ably sandbox generates real
/// vcdiff-encoded deltas.
class VCDiffDecoderAdapter implements VCDiffDecoder {
  /// Number of times [decode] has been called.
  int decodeCount = 0;

  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    decodeCount++;
    // Note: vcdiff package uses (source, delta) argument order
    return vcdiff.decode(base, delta);
  }
}

/// Adapter that always throws, for testing decode failure recovery.
class FailingVCDiffDecoderAdapter implements VCDiffDecoder {
  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    throw Exception('Simulated decode failure');
  }
}

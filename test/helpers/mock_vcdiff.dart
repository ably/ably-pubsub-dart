import 'dart:convert';
import 'dart:typed_data';

import 'package:ably_pubsub_device/ably_pubsub_device.dart';

/// Mock VCDiff encoder for constructing test delta payloads.
///
/// Uses a deterministic format that encodes both the base and value
/// into the delta, allowing the mock decoder to verify correctness.
///
/// See: uts/test/realtime/unit/helpers/mock_vcdiff.md
class MockVCDiffEncoder {
  /// Encodes a string delta: `encodeURIComponent(base)/encodeURIComponent(value)`.
  String encodeString(String base, String value) {
    return '${Uri.encodeComponent(base)}/${Uri.encodeComponent(value)}';
  }

  /// Encodes a binary delta: `base64url(base)/base64url(value)` as UTF-8 bytes.
  Uint8List encodeBinary(Uint8List base, Uint8List value) {
    final encoded = '${base64Url.encode(base).replaceAll('=', '')}/'
        '${base64Url.encode(value).replaceAll('=', '')}';
    return Uint8List.fromList(utf8.encode(encoded));
  }
}

/// Callback type for recording decode calls in tests.
typedef DecodeCallback = void Function(Uint8List delta, Uint8List base);

/// Mock VCDiff decoder implementing the VCDiffDecoder interface.
///
/// Validates that the base argument matches what was encoded, then returns
/// the original value. Optionally calls [onDecode] for recording.
///
/// See: uts/test/realtime/unit/helpers/mock_vcdiff.md
class MockVCDiffDecoder implements VCDiffDecoder {
  /// Creates a MockVCDiffDecoder with an optional [onDecode] callback.
  MockVCDiffDecoder({this.onDecode});

  /// Called before each decode with the raw arguments.
  final DecodeCallback? onDecode;

  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    onDecode?.call(delta, base);

    final deltaString = utf8.decode(delta);
    final slashIndex = deltaString.indexOf('/');
    if (slashIndex == -1) {
      throw Exception('Invalid mock delta format: no separator');
    }

    final encodedBase = deltaString.substring(0, slashIndex);
    final encodedValue = deltaString.substring(slashIndex + 1);

    // Try binary format first (base64url), then string format (URI-encoded)
    Uint8List decodedBase;
    Uint8List decodedValue;
    try {
      decodedBase = _base64UrlDecodeNoPadding(encodedBase);
      decodedValue = _base64UrlDecodeNoPadding(encodedValue);
    } catch (_) {
      // Fall back to URI-encoded string format
      final decodedBaseStr = Uri.decodeComponent(encodedBase);
      final decodedValueStr = Uri.decodeComponent(encodedValue);

      // Validate base matches
      final baseStr = utf8.decode(base);
      if (decodedBaseStr != baseStr) {
        throw Exception(
          'Base mismatch: expected "$decodedBaseStr" but got "$baseStr"',
        );
      }
      return Uint8List.fromList(utf8.encode(decodedValueStr));
    }

    // Validate binary base matches
    if (!_bytesEqual(decodedBase, base)) {
      throw Exception('Base mismatch: expected base does not match delta');
    }
    return decodedValue;
  }

  static Uint8List _base64UrlDecodeNoPadding(String input) {
    // Add padding if needed
    var padded = input;
    switch (padded.length % 4) {
      case 2:
        padded += '==';
      case 3:
        padded += '=';
    }
    return base64Url.decode(padded);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Mock VCDiff decoder that always throws, for testing RTL18 recovery.
///
/// See: uts/test/realtime/unit/helpers/mock_vcdiff.md
class FailingMockVCDiffDecoder implements VCDiffDecoder {
  @override
  Uint8List decode(Uint8List delta, Uint8List base) {
    throw Exception('Simulated vcdiff decode failure');
  }
}

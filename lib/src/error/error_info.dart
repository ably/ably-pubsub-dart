import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Contains error information returned from Ably.
///
/// Spec: TI1, TI2, TI6
@immutable
class ErrorInfo implements Exception {
  /// Creates an ErrorInfo instance.
  const ErrorInfo({
    this.code,
    this.statusCode,
    this.message,
    this.href,
    this.requestId,
    this.cause,
    this.detail,
  });

  /// Creates an ErrorInfo from a JSON map.
  factory ErrorInfo.fromMap(Map<String, dynamic> map) {
    // TI6: `detail` is a map of string keys to string values, omitted when
    // empty. Coerce defensively rather than casting: this factory runs on
    // wire data, and a throw here would escape from inside the transport
    // handler.
    final rawDetail = map['detail'];
    Map<String, String>? detail;
    if (rawDetail is Map && rawDetail.isNotEmpty) {
      detail = {
        for (final entry in rawDetail.entries)
          entry.key.toString(): entry.value.toString(),
      };
    }

    return ErrorInfo(
      code: map['code'] as int?,
      statusCode: map['statusCode'] as int?,
      message: map['message'] as String?,
      href: map['href'] as String?,
      requestId: map['requestId'] as String?,
      cause: map['cause'] != null
          ? ErrorInfo.fromMap(map['cause'] as Map<String, dynamic>)
          : null,
      detail: detail,
    );
  }

  /// Creates an ErrorInfo from a JSON map.
  ///
  /// Alias for [fromMap].
  factory ErrorInfo.fromJson(Map<String, dynamic> json) = ErrorInfo.fromMap;

  /// Ably error code.
  ///
  /// See: https://ably.com/docs/api/realtime-sdk/types#error-info
  final int? code;

  /// HTTP status code associated with the error.
  final int? statusCode;

  /// Error message.
  final String? message;

  /// URL to documentation about the error.
  final String? href;

  /// Request ID for tracing.
  final String? requestId;

  /// The underlying cause of this error, if any.
  /// Can be an Exception or another ErrorInfo.
  final Object? cause;

  /// Server-supplied structured metadata accompanying this error.
  ///
  /// A map of string keys to string values, carried from the `detail`
  /// member of the wire error object (TI6). Omitted from [toMap] when null
  /// or empty, as TI6 requires. Ably Chat uses it for the moderation
  /// rejection detail accompanying error codes 42211 and 42213.
  final Map<String, String>? detail;

  /// Returns the help URL for this error code.
  String? get helpUrl {
    if (href != null) return href;
    if (code != null) return 'https://help.ably.io/error/$code';
    return null;
  }

  @override
  String toString() {
    final parts = <String>[];
    if (code != null) parts.add('code=$code');
    if (statusCode != null) parts.add('statusCode=$statusCode');
    if (message != null) parts.add('message=$message');
    if (requestId != null) parts.add('requestId=$requestId');
    if (href != null) parts.add('href=$href');
    if (detail != null && detail!.isNotEmpty) parts.add('detail=$detail');
    return 'ErrorInfo(${parts.join(', ')})';
  }

  /// Converts this ErrorInfo to a JSON map.
  Map<String, dynamic> toMap() {
    return {
      if (code != null) 'code': code,
      if (statusCode != null) 'statusCode': statusCode,
      if (message != null) 'message': message,
      if (href != null) 'href': href,
      if (requestId != null) 'requestId': requestId,
      if (cause is ErrorInfo) 'cause': (cause! as ErrorInfo).toMap(),
      // TI6: the detail field MUST be omitted when empty.
      if (detail != null && detail!.isNotEmpty) 'detail': detail,
    };
  }

  /// Converts this ErrorInfo to a JSON map.
  ///
  /// Alias for [toMap].
  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ErrorInfo &&
        other.code == code &&
        other.statusCode == statusCode &&
        other.message == message &&
        other.href == href &&
        other.requestId == requestId &&
        other.cause == cause &&
        const MapEquality<String, String>().equals(other.detail, detail);
  }

  @override
  int get hashCode {
    return Object.hash(
      code,
      statusCode,
      message,
      href,
      requestId,
      cause,
      detail == null ? null : const MapEquality<String, String>().hash(detail!),
    );
  }
}

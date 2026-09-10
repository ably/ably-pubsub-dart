import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Decodes a captured request body, whatever wire format the SDK used.
///
/// The UTS mock spec (`mock_http.md`) exposes the request body as bytes and
/// the test specs decode it with `parse_json`; the harness is responsible
/// for decoding the SDK's configured wire format. With the default
/// `useBinaryProtocol: true` the body is msgpack, so fall back to msgpack
/// deserialization (with string-keyed maps) when JSON decoding fails.
dynamic _decodeBody(List<int> body) {
  try {
    return json.decode(utf8.decode(body));
  } on FormatException {
    return _stringKeyed(msgpack.deserialize(Uint8List.fromList(body)));
  }
}

dynamic _stringKeyed(dynamic value) {
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, item) => MapEntry(key.toString(), _stringKeyed(item)),
    );
  }
  if (value is List) {
    return value.map(_stringKeyed).toList();
  }
  return value;
}

/// Callback for handling connection attempts in the mock HTTP client.
typedef ConnectionHandler = void Function(PendingConnection connection);

/// Callback for handling HTTP requests in the mock HTTP client.
typedef RequestHandler = void Function(PendingRequest request);

/// A mock HTTP client for testing.
///
/// Configured using handlers that are called for each connection or request:
///
/// Example:
/// ```dart
/// final mock = MockHttpClient(
///   onRequest: (request) {
///     if (request.url.path == '/time') {
///       request.respondWith(200, {'time': 1234567890000});
///     } else {
///       request.respondWith(404, {'error': {'code': 40400}});
///     }
///   },
/// );
/// ```
class MockHttpClient extends http.BaseClient {
  /// Handler called for each connection attempt.
  final ConnectionHandler? onConnectionAttempt;

  /// Handler called for each HTTP request.
  final RequestHandler? onRequest;

  final List<CapturedRequest> capturedRequests = [];

  /// Controllers for awaitable events.
  final StreamController<PendingConnection> _connectionAttempts =
      StreamController<PendingConnection>.broadcast();
  final StreamController<PendingRequest> _requests =
      StreamController<PendingRequest>.broadcast();

  MockHttpClient({
    this.onConnectionAttempt,
    this.onRequest,
  });

  /// Awaits the next connection attempt.
  ///
  /// Returns a [PendingConnection] that can be used to respond to the
  /// connection attempt.
  ///
  /// Times out after [timeout] (default: 5 seconds).
  Future<PendingConnection> awaitConnectionAttempt({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _connectionAttempts.stream.first.timeout(timeout);
  }

  /// Awaits the next HTTP request.
  ///
  /// Returns a [PendingRequest] that can be used to respond to the request.
  ///
  /// Times out after [timeout] (default: 5 seconds).
  Future<PendingRequest> awaitRequest({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _requests.stream.first.timeout(timeout);
  }

  /// Resets all captured requests.
  void reset() {
    capturedRequests.clear();
  }

  /// Gets captured requests for a specific host.
  List<CapturedRequest> capturedRequestsForHost(String host) {
    return capturedRequests.where((r) => r.url.host == host).toList();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = request is http.Request ? request.bodyBytes : <int>[];
    final capturedRequest = CapturedRequest(
      method: request.method,
      url: request.url,
      headers: Map.from(request.headers),
      bodyBytes: bodyBytes,
    );
    capturedRequests.add(capturedRequest);

    final host = request.url.host;
    final port = request.url.port;
    final tls = request.url.scheme == 'https';

    // Always emit connection attempt (for awaitConnectionAttempt support)
    final pendingConnection = PendingConnection._(
      host: host,
      port: port,
      tls: tls,
      timestamp: DateTime.now(),
    );
    if (!_connectionAttempts.isClosed) {
      _connectionAttempts.add(pendingConnection);
    }

    // Call handler if provided, otherwise auto-succeed
    if (onConnectionAttempt != null) {
      onConnectionAttempt!(pendingConnection);
    } else {
      pendingConnection.respondWithSuccess();
    }

    // Wait for connection resolution
    await pendingConnection._completer.future;

    // Always emit request (for awaitRequest support)
    final pendingRequest = PendingRequest._(
      url: request.url,
      method: request.method,
      headers: Map.from(request.headers),
      body: bodyBytes,
      timestamp: DateTime.now(),
    );
    if (!_requests.isClosed) {
      _requests.add(pendingRequest);
    }

    // Call handler if provided
    if (onRequest != null) {
      onRequest!(pendingRequest);
    } else {
      // Provide default 200 response
      pendingRequest.respondWith(200, {});
    }

    return await pendingRequest._completer.future;
  }

  /// Disposes of resources used by this mock client.
  void dispose() {
    _connectionAttempts.close();
    _requests.close();
  }
}

/// Represents a pending connection attempt that can be responded to by test code.
class PendingConnection {
  /// The hostname being connected to.
  final String host;

  /// The port being connected to.
  final int port;

  /// Whether TLS/HTTPS is being used.
  final bool tls;

  /// The timestamp when the connection was attempted.
  final DateTime timestamp;

  final Completer<void> _completer = Completer<void>();

  PendingConnection._({
    required this.host,
    required this.port,
    required this.tls,
    required this.timestamp,
  });

  /// Responds with a successful connection.
  void respondWithSuccess() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Responds with a connection refused error.
  void respondWithRefused() {
    if (!_completer.isCompleted) {
      _completer.completeError(
        const SocketException('Connection refused'),
      );
    }
  }

  /// Responds with a connection timeout.
  void respondWithTimeout() {
    if (!_completer.isCompleted) {
      _completer.completeError(
        TimeoutException('Connection timed out'),
      );
    }
  }

  /// Responds with a DNS resolution error.
  void respondWithDnsError() {
    if (!_completer.isCompleted) {
      _completer.completeError(
        SocketException('Failed to resolve hostname: $host'),
      );
    }
  }
}

/// Represents a pending HTTP request that can be responded to by test code.
class PendingRequest {
  /// The URL being requested.
  final Uri url;

  /// The HTTP method (GET, POST, etc).
  final String method;

  /// The request headers.
  final Map<String, String> headers;

  /// The request body as bytes.
  final List<int> body;

  /// The timestamp when the request was made.
  final DateTime timestamp;

  final Completer<http.StreamedResponse> _completer =
      Completer<http.StreamedResponse>();

  PendingRequest._({
    required this.url,
    required this.method,
    required this.headers,
    required this.body,
    required this.timestamp,
  });

  /// Gets the request body as a string (UTF-8 decoded).
  String get bodyAsString => utf8.decode(body);

  /// Gets the request body decoded from the SDK's wire format (JSON, or
  /// msgpack when `useBinaryProtocol` is in effect).
  dynamic get jsonBody => _decodeBody(body);

  /// Responds with the specified status code, body, and optional headers.
  void respondWith(
    int status,
    Object body, {
    Map<String, String>? headers,
  }) {
    if (_completer.isCompleted) return;

    final String bodyString;
    if (body is String) {
      bodyString = body;
    } else {
      bodyString = json.encode(body);
    }

    final responseHeaders = Map<String, String>.from(headers ?? {});
    responseHeaders.putIfAbsent('Content-Type', () => 'application/json');

    _completer.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode(bodyString)),
        status,
        headers: responseHeaders,
      ),
    );
  }

  /// Responds with a delay, then the specified status code, body, and headers.
  Future<void> respondWithDelay(
    Duration delay,
    int status,
    Object body, {
    Map<String, String>? headers,
  }) async {
    await Future.delayed(delay);
    respondWith(status, body, headers: headers);
  }

  /// Responds with a timeout error.
  void respondWithTimeout() {
    if (!_completer.isCompleted) {
      _completer.completeError(
        TimeoutException('Request timed out'),
      );
    }
  }
}

/// A captured HTTP request for inspection.
class CapturedRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  CapturedRequest({
    required this.method,
    required this.url,
    required this.headers,
    String? body,
    List<int>? bodyBytes,
  }) : bodyBytes = bodyBytes ?? (body != null ? utf8.encode(body) : []);

  String get bodyAsString => utf8.decode(bodyBytes);

  String? get body => bodyAsString;

  /// The body decoded from the SDK's wire format (JSON, or msgpack when
  /// `useBinaryProtocol` is in effect).
  dynamic get jsonBody => bodyBytes.isNotEmpty ? _decodeBody(bodyBytes) : null;
}

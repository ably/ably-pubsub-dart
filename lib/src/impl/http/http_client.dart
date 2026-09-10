import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import '../../auth/client_options.dart';
import '../../error/ably_exception.dart';
import '../../error/error_info.dart';
import '../../logging/log_level.dart';
import '../../logging/logger.dart';
import '../fallback/error_classifier.dart';
import '../fallback/host_selector.dart';
import 'constants.dart';

/// Response from an Ably HTTP request.
class AblyHttpResponse {
  AblyHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// HTTP status code.
  final int statusCode;

  /// Response headers (lowercase keys).
  final Map<String, String> headers;

  /// Parsed response body (usually Map or List).
  final dynamic body;

  /// Whether the response indicates success (2xx).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Link header for pagination.
  String? get linkHeader => headers[HttpHeaders.link.toLowerCase()];

  /// Ably error code from headers.
  int? get errorCode {
    final code = headers[HttpHeaders.ablyErrorCode.toLowerCase()];
    return code != null ? int.tryParse(code) : null;
  }

  /// Ably error message from headers.
  String? get errorMessage =>
      headers[HttpHeaders.ablyErrorMessage.toLowerCase()];
}

/// Function type for obtaining an authorization header.
typedef AuthHeaderProvider = Future<String> Function();

/// Function type for renewing a token (e.g., calling authorize()).
typedef TokenRenewer = Future<void> Function();

/// HTTP client wrapper for Ably REST API.
class AblyHttpClient {
  AblyHttpClient({
    required ClientOptions options,
    http.Client? httpClient,
    AuthHeaderProvider? authHeaderProvider,
    HostSelector? hostSelector,
    required Logger logger,
  })  : _options = options,
        _httpClient = httpClient ?? http.Client(),
        _authHeaderProvider = authHeaderProvider,
        _logger = logger,
        _hostSelector =
            hostSelector ?? HostSelector(options: options, logger: logger);

  final ClientOptions _options;
  final http.Client _httpClient;
  final AuthHeaderProvider? _authHeaderProvider;
  final Logger _logger;
  final HostSelector _hostSelector;
  final Random _random = Random();

  /// Set the auth header provider (called after Auth is initialized).
  AuthHeaderProvider? authHeaderProvider;

  /// Provider of additional authentication-related headers, e.g. the
  /// X-Ably-ClientId header for basic auth with a clientId (RSA7e2).
  Map<String, String> Function()? additionalAuthHeadersProvider;

  /// Set the token renewer (called to force token renewal on 40142 errors).
  TokenRenewer? tokenRenewer;

  /// Makes an HTTP request to the Ably REST API.
  ///
  /// Automatically retries on token errors (40140-40149) by renewing
  /// the token and retrying once.
  Future<AblyHttpResponse> request(
    String method,
    String path, {
    Map<String, String>? queryParams,
    Object? body,
    bool authenticated = true,
    Map<String, String>? customHeaders,
    int? customVersion,
    bool returnErrorBody = false,
  }) async {
    return _requestWithTokenRetry(
      method,
      path,
      queryParams: queryParams,
      body: body,
      authenticated: authenticated,
      customHeaders: customHeaders,
      customVersion: customVersion,
      tokenRetryAttempted: false,
      returnErrorBody: returnErrorBody,
    );
  }

  Future<AblyHttpResponse> _requestWithTokenRetry(
    String method,
    String path, {
    Map<String, String>? queryParams,
    Object? body,
    bool authenticated = true,
    Map<String, String>? customHeaders,
    int? customVersion,
    required bool tokenRetryAttempted,
    bool returnErrorBody = false,
  }) async {
    final effectiveQueryParams = Map<String, String>.from(queryParams ?? {});

    // Add request_id if configured (RSC7c)
    if (_options.addRequestIds) {
      effectiveQueryParams['request_id'] = _generateRequestId();
    }

    // Try primary host first, then fallbacks
    final hosts = _hostSelector.getHostsToTry(
      primaryHost: _options.effectiveRestHost,
    );
    AblyException? lastException;

    for (var i = 0; i < hosts.length; i++) {
      final host = hosts[i];
      try {
        final response = await _makeRequest(
          method,
          host,
          path,
          queryParams: effectiveQueryParams,
          body: body,
          authenticated: authenticated,
          customHeaders: customHeaders,
          customVersion: customVersion,
          returnErrorBody: returnErrorBody,
        );

        // RSC15f: If we used a fallback host successfully, cache it as preferred
        if (!_hostSelector.isPrimaryHost(host, _options.effectiveRestHost)) {
          _hostSelector.clearFailureTracking(preferredHost: host);
        }

        return response;
      } on AblyException catch (e) {
        lastException = e;

        // RSA4b4: On token error (40140-40149), try to renew token and retry once
        if (!tokenRetryAttempted &&
            authenticated &&
            tokenRenewer != null &&
            e.errorInfo != null &&
            ErrorClassifier.isTokenError(e.errorInfo!)) {
          _logger.debug('Token error, renewing', {
            'code': e.errorInfo!.code,
          });
          await tokenRenewer!();
          return _requestWithTokenRetry(
            method,
            path,
            queryParams: queryParams,
            body: body,
            authenticated: authenticated,
            customHeaders: customHeaders,
            customVersion: customVersion,
            tokenRetryAttempted: true,
            returnErrorBody: returnErrorBody,
          );
        }

        // Only retry on certain errors (5xx, network errors, RSC15l4 CloudFront)
        if (!e.isRetryable && !ErrorClassifier.shouldRetryException(e)) {
          rethrow;
        }

        // Mark this host as failed
        _hostSelector.markHostAsFailed(host);

        final nextHost = i + 1 < hosts.length ? hosts[i + 1] : null;
        if (nextHost != null) {
          _logger.warn('HTTP request failed, trying fallback', {
            'statusCode': e.errorInfo?.statusCode,
            'host': host,
            'nextHost': nextHost,
          });
        }
      }
    }

    _logger.error('HTTP request failed, no more hosts', {
      'statusCode': lastException?.errorInfo?.statusCode,
      'host': hosts.isNotEmpty ? hosts.last : null,
    });

    throw lastException ??
        const AblyException(
          message: 'All hosts failed',
          errorInfo: ErrorInfo(
            message: 'All hosts failed',
            statusCode: 500,
          ),
        );
  }

  Future<AblyHttpResponse> _makeRequest(
    String method,
    String host,
    String path, {
    Map<String, String>? queryParams,
    Object? body,
    bool authenticated = true,
    Map<String, String>? customHeaders,
    int? customVersion,
    bool returnErrorBody = false,
  }) async {
    _logger.debug('HTTP request', {
      'method': method,
      'host': host,
      'path': path,
    });

    // Build URL
    final scheme = _options.tls ? 'https' : 'http';
    final port = _options.effectivePort;
    final hostWithPort =
        port == (_options.tls ? 443 : 80) ? host : '$host:$port';
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    var uri = Uri.parse('$scheme://$hostWithPort$normalizedPath');

    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    // Build headers - use msgpack headers if useBinaryProtocol, otherwise JSON
    final contentType =
        _options.useBinaryProtocol ? ContentTypes.msgpack : ContentTypes.json;

    // RSC19f1: Use explicit version if provided
    final version = customVersion?.toString() ?? ablyProtocolVersion;

    final headers = <String, String>{
      HttpHeaders.ablyVersion: version,
      HttpHeaders.ablyAgent: _buildAgentString(),
      HttpHeaders.accept: contentType,
    };

    if (body != null) {
      headers[HttpHeaders.contentType] = contentType;
    }

    // Add auth header
    if (authenticated) {
      final provider = authHeaderProvider ?? _authHeaderProvider;
      if (provider != null) {
        headers[HttpHeaders.authorization] = await provider();
      }
      // RSA7e2: X-Ably-ClientId for basic auth with a clientId
      final additionalHeaders = additionalAuthHeadersProvider?.call();
      if (additionalHeaders != null) {
        headers.addAll(additionalHeaders);
      }
    }

    // RSC19f: Add custom headers (cannot override auth)
    if (customHeaders != null) {
      for (final entry in customHeaders.entries) {
        // RSC19b: Cannot override authentication
        if (entry.key.toLowerCase() != 'authorization') {
          headers[entry.key] = entry.value;
        }
      }
    }

    // Make request
    http.Response response;
    try {
      final request = http.Request(method, uri);
      request.headers.addAll(headers);

      if (body != null) {
        if (_options.useBinaryProtocol) {
          request.bodyBytes = msgpack.serialize(body);
        } else {
          request.body = json.encode(body);
        }
      }

      if (_logger.shouldLog(LogLevel.verbose)) {
        _logger.verbose('HTTP request detail', {
          'url': uri.toString(),
          'headers': headers.keys.toList(),
          'bodyLength': body != null ? request.contentLength : 0,
        });
      }

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(Duration(milliseconds: _options.httpRequestTimeout));
      response = await http.Response.fromStream(streamedResponse);
    } on TimeoutException {
      throw AblyException(
        message: 'Request timeout',
        errorInfo: ErrorInfo(
          message: 'Request timeout after ${_options.httpRequestTimeout}ms',
          statusCode: 408,
          code: 50003,
        ),
      );
    } catch (e) {
      throw AblyException(
        message: 'Network error: $e',
        errorInfo: ErrorInfo(
          message: 'Network error: $e',
          statusCode: 500,
          code: 80000,
        ),
      );
    }

    // Normalize headers to lowercase keys for case-insensitive lookup
    final normalizedHeaders = <String, String>{};
    response.headers.forEach((key, value) {
      normalizedHeaders[key.toLowerCase()] = value;
    });

    _logger.debug('HTTP response', {
      'statusCode': response.statusCode,
      'host': host,
    });

    if (_logger.shouldLog(LogLevel.verbose)) {
      _logger.verbose('HTTP response detail', {
        'headers': normalizedHeaders.keys.toList(),
        'bodyLength': response.body.length,
      });
    }

    // Check Content-Type for supported types (RSC8e)
    final responseContentType = normalizedHeaders['content-type'] ?? '';
    final isJsonResponse = responseContentType.contains('application/json');
    final isMsgpackResponse =
        responseContentType.contains('application/x-msgpack');
    final isSupported =
        isJsonResponse || isMsgpackResponse || responseContentType.isEmpty;

    // Parse response body
    dynamic parsedBody;
    if (response.bodyBytes.isNotEmpty) {
      if (isMsgpackResponse) {
        try {
          parsedBody = _deepCast(msgpack.deserialize(response.bodyBytes));
        } catch (_) {
          parsedBody = response.bodyBytes;
        }
      } else if (isJsonResponse || responseContentType.isEmpty) {
        try {
          parsedBody = json.decode(response.body);
        } catch (_) {
          parsedBody = response.body;
        }
      } else {
        parsedBody = response.body;
      }
    }

    final ablyResponse = AblyHttpResponse(
      statusCode: response.statusCode,
      headers: normalizedHeaders,
      body: parsedBody,
    );

    // Check for errors
    if (!ablyResponse.isSuccess && !returnErrorBody) {
      // RSC15l4: CloudFront errors are retryable
      final isCloudFront =
          normalizedHeaders['server']?.toLowerCase().contains('cloudfront') ??
              false;
      final forceRetry = isCloudFront && response.statusCode >= 400;
      throw _parseError(
        ablyResponse,
        queryParams?['request_id'],
        isRetryable: forceRetry,
      );
    }

    // For successful responses, check Content-Type support
    if (!isSupported && response.body.isNotEmpty) {
      throw AblyException(
        message: 'Unsupported Content-Type',
        errorInfo: ErrorInfo(
          message: 'Unsupported Content-Type: $responseContentType. '
              'Expected application/json or application/x-msgpack.',
          code: 40013,
          statusCode: 400,
          requestId: queryParams?['request_id'],
        ),
      );
    }

    return ablyResponse;
  }

  String _buildAgentString() {
    final agents = [ablyAgent];

    if (_options.agents != null) {
      for (final entry in _options.agents!.entries) {
        agents.add('${entry.key}/${entry.value}');
      }
    }

    return agents.join(' ');
  }

  String _generateRequestId() {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).substring(0, 16);
  }

  AblyException _parseError(
    AblyHttpResponse response,
    String? requestId, {
    bool isRetryable = false,
  }) {
    ErrorInfo errorInfo;

    if (response.body is Map && response.body['error'] != null) {
      final errorMap = response.body['error'] as Map<String, dynamic>;
      if (requestId != null) {
        errorMap['requestId'] = requestId;
      }
      // Ensure statusCode is set from HTTP response if not in body
      errorMap['statusCode'] ??= response.statusCode;
      errorInfo = ErrorInfo.fromMap(errorMap);
    } else {
      errorInfo = ErrorInfo(
        statusCode: response.statusCode,
        code: response.errorCode,
        message: response.errorMessage ?? 'HTTP ${response.statusCode}',
        requestId: requestId,
      );
    }

    return AblyException.fromErrorInfo(errorInfo, isRetryable: isRetryable);
  }

  static dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (k, v) => MapEntry(k.toString(), _deepCast(v)),
      );
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }

  /// Closes the HTTP client.
  void close() {
    _httpClient.close();
  }
}

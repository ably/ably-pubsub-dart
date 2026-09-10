import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../auth/auth.dart';
import '../auth/client_options.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../pagination/http_paginated_response.dart';
import '../pagination/paginated_result.dart';
import '../push/local_device.dart';
import '../stats/stats.dart';
import 'auth_impl.dart';
import 'http/http_client.dart';
import 'paginated_result_impl.dart';
import 'push_activation_impl.dart';

/// Shared base class for Rest and Realtime client implementations.
///
/// Contains the HTTP client, auth setup, options validation, and
/// methods that are shared between REST and Realtime clients
/// (time, stats, request, etc.).
abstract class BaseClientImpl {
  BaseClientImpl({
    required ClientOptions options,
    http.Client? httpClient,
  }) : _options = options {
    _validateOptions(options);

    logger = Logger(
      level: options.logLevel,
      handler: options.logHandler,
    );

    rawHttpClient = httpClient ?? http.Client();

    ablyHttpClient = AblyHttpClient(
      options: options,
      httpClient: rawHttpClient,
      logger: logger,
    );

    authImpl = AuthImpl(
      options: options,
      httpClient: ablyHttpClient,
      rawHttpClient: rawHttpClient,
      logger: logger,
    );

    // Wire up auth header provider
    ablyHttpClient.authHeaderProvider = authImpl.getAuthorizationHeader;

    // RSA7e2: X-Ably-ClientId header for basic auth with a clientId
    ablyHttpClient.additionalAuthHeadersProvider =
        () => authImpl.additionalAuthHeaders;

    // Wire up token renewer for auto-retry on token errors (RSA4b4)
    if (_hasTokenRenewalMechanism(options)) {
      ablyHttpClient.tokenRenewer = () => authImpl.authorize();
    }

    // RSH8d/RSH8e: observe identity changes for the push LocalDevice
    authImpl.onTokenChanged = () => _pushActivation?.machine.notifyClientId();

    logger.info('Client created', {'type': clientType});
  }

  /// The client type name for logging. Overridden by subclasses.
  @protected
  String get clientType => 'rest';

  final ClientOptions _options;

  /// The logger instance, created from options and shared with all components.
  @protected
  late final Logger logger;

  /// The raw HTTP client, available to subclasses for dependency injection.
  @protected
  late final http.Client rawHttpClient;

  /// The Ably HTTP client used for REST API requests.
  @protected
  late final AblyHttpClient ablyHttpClient;

  /// The auth implementation.
  @protected
  late final AuthImpl authImpl;

  ClientOptions get options => _options;
  Auth get auth => authImpl;
  String? get clientId => authImpl.clientId;

  PushActivation? _pushActivation;

  /// The push activation support (LocalDevice state + Activation State
  /// Machine), created lazily when the client is configured with a push
  /// platform (RSH3h). Null when no push platform is configured.
  @protected
  PushActivation? get pushActivation {
    if (_pushActivation == null && _options.pushPlatform != null) {
      _pushActivation = PushActivation(
        platform: _options.pushPlatform!,
        httpClient: ablyHttpClient,
        auth: authImpl,
        logger: logger,
      );
    }
    return _pushActivation;
  }

  LocalDevice? _deviceOverride;

  /// The local device for push notifications (RSH8).
  ///
  /// Returns a snapshot of the loaded LocalDevice state, or null when the
  /// device has not been loaded yet. An explicitly assigned device takes
  /// precedence (used by tests to install a fixed device).
  LocalDevice? get device {
    final override = _deviceOverride;
    if (override != null) return override;
    final activation = _pushActivation;
    if (activation != null && activation.device.isLoaded) {
      return activation.device.snapshot();
    }
    return null;
  }

  set device(LocalDevice? value) => _deviceOverride = value;

  /// Returns the current LocalDevice, loading it from persisted state on
  /// first call (RSH8, RSH8a).
  Future<LocalDevice> getDevice() async {
    final override = _deviceOverride;
    if (override != null) return override;
    final activation = pushActivation;
    if (activation == null) {
      throw const AblyException(
        message: 'Push activation is not available: '
            'no push platform is configured on this client',
        errorInfo: ErrorInfo(
          message: 'Push activation is not available: '
              'no push platform is configured on this client '
              '(set ClientOptions.pushPlatform)',
          code: 40000,
          statusCode: 400,
        ),
      );
    }
    await activation.device.ensureLoaded();
    return activation.device.snapshot();
  }

  /// Returns true if there's a mechanism to renew tokens.
  /// Token renewal requires either a key, authCallback, or authUrl.
  /// A static token alone cannot be renewed.
  bool _hasTokenRenewalMechanism(ClientOptions options) {
    return options.key != null ||
        options.authCallback != null ||
        options.authUrl != null;
  }

  void _validateOptions(ClientOptions options) {
    // Must have at least one authentication method
    final hasKey = options.key != null;
    final hasAuthCallback = options.authCallback != null;
    final hasAuthUrl = options.authUrl != null;
    final hasToken = options.token != null || options.tokenDetails != null;

    if (!hasKey && !hasAuthCallback && !hasAuthUrl && !hasToken) {
      throw const AblyException(
        message: 'No authentication method provided',
        errorInfo: ErrorInfo(
          message: 'No authentication method provided. '
              'Must provide key, authCallback, authUrl, or token.',
          code: 40106,
          statusCode: 401,
        ),
      );
    }

    // Validate key format if provided
    if (hasKey) {
      final keyParts = options.key!.split(':');
      if (keyParts.length != 2 || keyParts[0].isEmpty || keyParts[1].isEmpty) {
        throw const AblyException(
          message: 'Invalid API key format',
          errorInfo: ErrorInfo(
            message:
                'Invalid API key format. Expected format: keyName:keySecret',
            code: 40101,
            statusCode: 401,
          ),
        );
      }

      // RSC18: Reject Basic auth over non-TLS connection.
      // A clientId alone does not switch to token auth (RSA7e2).
      final wouldUseBasicAuth = options.useTokenAuth != true &&
          !hasAuthCallback &&
          !hasAuthUrl &&
          !hasToken;

      if (wouldUseBasicAuth && !options.tls) {
        throw const AblyException(
          message: 'Cannot use Basic authentication over non-TLS connection',
          errorInfo: ErrorInfo(
            message: 'Basic authentication (API key) requires TLS. '
                'Use token authentication for non-TLS connections.',
            code: 40103,
            statusCode: 401,
          ),
        );
      }
    }
  }

  /// Gets the current server time.
  ///
  /// Spec: RSC16, RTC6a
  Future<DateTime> time() async {
    logger.info('time() called');
    // RSC16: time() does not require authentication
    final response = await ablyHttpClient.request(
      'GET',
      '/time',
      authenticated: false,
    );

    final body = response.body;
    int timestamp;

    // Handle both array format (actual Ably API) and map format (some tests)
    if (body is List) {
      if (body.isEmpty) {
        throw const AblyException(
          message: 'Invalid time response',
          errorInfo: ErrorInfo(
            message: 'Server returned empty time response',
            code: 50000,
            statusCode: 500,
          ),
        );
      }
      timestamp = body[0] as int;
    } else if (body is Map && body.containsKey('time')) {
      timestamp = body['time'] as int;
    } else {
      throw const AblyException(
        message: 'Invalid time response',
        errorInfo: ErrorInfo(
          message: 'Invalid time response format',
          code: 50000,
          statusCode: 500,
        ),
      );
    }

    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Makes an arbitrary HTTP request to the Ably REST API.
  ///
  /// Spec: RSC19, RTC9
  Future<HttpPaginatedResponse<dynamic>> request(
    String method,
    String path, {
    int? version,
    Map<String, String>? params,
    Map<String, String>? headers,
    Object? body,
  }) async {
    logger.info('request() called', {'method': method, 'path': path});
    // Ensure path starts with /
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    // Build query parameters
    final queryParams = Map<String, String>.from(params ?? {});

    // Make the request
    final response = await ablyHttpClient.request(
      method,
      normalizedPath,
      queryParams: queryParams.isNotEmpty ? queryParams : null,
      body: body,
      customHeaders: headers,
      customVersion: version,
    );

    // Parse response items
    final responseBody = response.body;
    List<dynamic> items;

    if (responseBody is List) {
      items = responseBody;
    } else if (responseBody == null) {
      items = [];
    } else {
      // Non-array response - wrap in a list
      items = [responseBody];
    }

    return HttpPaginatedResponseImpl.fromResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      items: items,
      firstUrl: normalizedPath,
      fetcher: (url) => _fetchRequestPage(url, method, headers, version),
    );
  }

  Future<HttpPaginatedResponse<dynamic>> _fetchRequestPage(
    String url,
    String method,
    Map<String, String>? headers,
    int? version,
  ) async {
    final uri = Uri.parse(url);
    final path = uri.path;
    final queryParams = uri.queryParameters.isNotEmpty
        ? Map<String, String>.from(uri.queryParameters)
        : null;

    final response = await ablyHttpClient.request(
      method,
      path,
      queryParams: queryParams,
      customHeaders: headers,
      customVersion: version,
    );

    final responseBody = response.body;
    List<dynamic> items;

    if (responseBody is List) {
      items = responseBody;
    } else if (responseBody == null) {
      items = [];
    } else {
      items = [responseBody];
    }

    return HttpPaginatedResponseImpl.fromResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      items: items,
      firstUrl: path,
      fetcher: (nextUrl) =>
          _fetchRequestPage(nextUrl, method, headers, version),
    );
  }

  /// Gets application statistics.
  ///
  /// Returns a [PaginatedResult] containing [Stats] objects.
  ///
  /// Spec: RSC6, RTC5a
  Future<PaginatedResult<Stats>> stats({
    DateTime? start,
    DateTime? end,
    StatsDirection? direction,
    int? limit,
    StatsUnit? unit,
  }) async {
    logger.info('stats() called');
    final queryParams = <String, String>{};
    if (start != null) {
      queryParams['start'] = start.millisecondsSinceEpoch.toString();
    }
    if (end != null) {
      queryParams['end'] = end.millisecondsSinceEpoch.toString();
    }
    if (direction != null) {
      queryParams['direction'] = direction.name;
    }
    if (limit != null) {
      queryParams['limit'] = limit.toString();
    }
    if (unit != null) {
      queryParams['unit'] = unit.name;
    }

    final response = await ablyHttpClient.request(
      'GET',
      '/stats',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    final items = _parseStats(response.body);

    return PaginatedResultImpl.fromResponse<Stats>(
      response: response,
      items: items,
      fetcher: (url) => _fetchStatsPage(url),
      requestPath: '/stats',
    );
  }

  Future<PaginatedResult<Stats>> _fetchStatsPage(String url) async {
    final uri = Uri.parse(url);
    final path = uri.path;

    final response = await ablyHttpClient.request(
      'GET',
      path,
      queryParams: uri.queryParameters.isNotEmpty
          ? Map<String, String>.from(uri.queryParameters)
          : null,
    );

    final items = _parseStats(response.body);

    return PaginatedResultImpl.fromResponse<Stats>(
      response: response,
      items: items,
      fetcher: (nextUrl) => _fetchStatsPage(nextUrl),
      requestPath: path,
    );
  }

  List<Stats> _parseStats(dynamic body) {
    if (body == null) return [];
    if (body is! List) return [];
    return body.cast<Map<String, dynamic>>().map(Stats.fromMap).toList();
  }
}

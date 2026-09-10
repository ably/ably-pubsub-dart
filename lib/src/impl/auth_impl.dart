import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../auth/auth.dart';
import '../auth/auth_options.dart';
import '../auth/client_options.dart';
import '../auth/token_details.dart';
import '../auth/token_params.dart';
import '../auth/token_request.dart';
import '../auth/token_revocation.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import 'http/http_client.dart';

/// Implementation of the Auth interface.
class AuthImpl implements Auth {
  AuthImpl({
    required ClientOptions options,
    required AblyHttpClient httpClient,
    required Logger logger,
    http.Client? rawHttpClient,
  })  : _options = options,
        _httpClient = httpClient,
        _logger = logger,
        _rawHttpClient = rawHttpClient ?? http.Client() {
    _initialize();
  }

  final ClientOptions _options;
  final AblyHttpClient _httpClient;
  final Logger _logger;
  final http.Client _rawHttpClient;

  TokenDetails? _currentToken;
  AuthOptions? _storedAuthOptions;
  TokenParams? _storedTokenParams;

  /// Called after a new token is obtained and stored, so interested parties
  /// can observe identity changes (e.g. push activation per RSH8d/RSH8e,
  /// when the client becomes identified per RSA7b2/RSA7b3).
  void Function()? onTokenChanged;

  void _initialize() {
    // Initialize with any token provided in options
    if (_options.tokenDetails != null) {
      _validateClientIdConsistency(_options.tokenDetails!);
      _currentToken = _options.tokenDetails;
    } else if (_options.token != null) {
      _currentToken = TokenDetails(token: _options.token);
    }
    _logAuthMethod();
  }

  /// RSA7: Validates that clientId in ClientOptions is consistent with
  /// token's clientId. Throws AblyException if there's a mismatch.
  void _validateClientIdConsistency(TokenDetails token) {
    final optionsClientId = _options.clientId;
    final tokenClientId = token.clientId;

    // No validation needed if either is null
    if (optionsClientId == null || tokenClientId == null) {
      return;
    }

    // Wildcard token allows any clientId
    if (tokenClientId == '*') {
      return;
    }

    // ClientIds must match
    if (optionsClientId != tokenClientId) {
      throw AblyException(
        message: 'ClientId mismatch: options clientId "$optionsClientId" '
            'does not match token clientId "$tokenClientId"',
        errorInfo: ErrorInfo(
          message: 'ClientId mismatch: options clientId "$optionsClientId" '
              'does not match token clientId "$tokenClientId"',
          code: 40102,
          statusCode: 401,
        ),
      );
    }
  }

  @override
  String? get clientId {
    // RSA7: Return clientId with proper precedence
    // If token has wildcard '*', use options clientId if available
    if (_currentToken?.clientId == '*') {
      return _options.clientId ?? '*';
    }
    // Otherwise: options clientId > token clientId > stored params clientId
    return _options.clientId ??
        _currentToken?.clientId ??
        _storedTokenParams?.clientId;
  }

  @override
  AuthMethod get method {
    // Determine auth method based on options (RSA4)
    if (_shouldUseTokenAuth()) {
      return AuthMethod.token;
    }
    return AuthMethod.basic;
  }

  /// Logs auth method selection on first access. Called during initialization.
  void _logAuthMethod() {
    _logger.info('Auth method selected', {'method': method.name});
  }

  @override
  TokenDetails? get tokenDetails => _currentToken;

  bool _shouldUseTokenAuth() {
    // RSA16d: If authorize() switched to basic auth, respect that
    if (_storedAuthOptions?.useTokenAuth == false &&
        _storedAuthOptions?.key != null) {
      return false;
    }

    // RSA4: Use token auth if:
    // - useTokenAuth is explicitly true
    // - authCallback is set
    // - authUrl is set
    // - token or tokenDetails is set
    // - a token has been obtained via authorize()
    // Note: a clientId alone does NOT force token auth — basic auth with a
    // clientId is identified via the X-Ably-ClientId header (RSA7e2).
    if (_options.useTokenAuth == true) return true;
    if (_options.authCallback != null) return true;
    if (_options.authUrl != null) return true;
    if (_options.token != null) return true;
    if (_options.tokenDetails != null) return true;
    if (_currentToken != null) return true; // Token obtained via authorize()
    return false;
  }

  /// Additional authentication-related request headers.
  ///
  /// RSA7e2: for REST clients using basic authentication with a `clientId`
  /// in `ClientOptions`, all requests include an `X-Ably-ClientId` header
  /// with the Base64-encoded clientId.
  Map<String, String> get additionalAuthHeaders {
    final optionsClientId = _options.clientId;
    if (method == AuthMethod.basic &&
        optionsClientId != null &&
        optionsClientId != '*') {
      return {'X-Ably-ClientId': base64.encode(utf8.encode(optionsClientId))};
    }
    return const {};
  }

  /// Gets the authorization header for HTTP requests.
  Future<String> getAuthorizationHeader() async {
    if (method == AuthMethod.basic) {
      return _getBasicAuthHeader();
    }
    return _getTokenAuthHeader();
  }

  String _getBasicAuthHeader() {
    final key = _storedAuthOptions?.key ?? _options.key;
    if (key == null) {
      throw const AblyException(
        message: 'API key required for Basic authentication',
        errorInfo: ErrorInfo(
          message: 'API key required for Basic authentication',
          code: 40101,
          statusCode: 401,
        ),
      );
    }
    return 'Basic ${base64.encode(utf8.encode(key))}';
  }

  Future<String> _getTokenAuthHeader() async {
    // Ensure we have a valid token
    if (_currentToken == null || _currentToken!.isExpired) {
      await authorize();
    }

    final token = _currentToken?.token;
    if (token == null) {
      throw const AblyException(
        message: 'No token available',
        errorInfo: ErrorInfo(
          message: 'No token available',
          code: 40101,
          statusCode: 401,
        ),
      );
    }

    return 'Bearer $token';
  }

  @override
  Future<TokenDetails?> authorize({
    AuthOptions? authOptions,
    TokenParams? tokenParams,
  }) async {
    _logger.info('authorize() called');

    // RSA16d: Switch to basic auth if explicitly requested
    if (authOptions != null &&
        authOptions.useTokenAuth == false &&
        authOptions.key != null) {
      _storedAuthOptions = authOptions;
      _currentToken = null;
      _logger.info('Switched to basic auth');
      return null;
    }

    // RSA10: Authorize and store token
    // If authOptions provided, replace stored options
    if (authOptions != null) {
      _storedAuthOptions = authOptions;
    }

    // RSA10e: If tokenParams provided, save them for reuse
    if (tokenParams != null) {
      _storedTokenParams = tokenParams;
    }

    // Merge token params
    final effectiveParams = _mergeTokenParams(tokenParams);

    // RSA16d: Clear current token before attempting renewal
    // If renewal fails, we don't want to keep using an invalid token
    _currentToken = null;

    try {
      // Request a new token
      _currentToken = await requestToken(
        authOptions: authOptions ?? _storedAuthOptions,
        tokenParams: effectiveParams,
      );
      _logger.info('Token obtained', {
        if (_currentToken!.expires != null)
          'expiresIn':
              _currentToken!.expires! - clock.now().millisecondsSinceEpoch,
      });
      onTokenChanged?.call();
      return _currentToken!;
    } catch (e) {
      // If renewal fails, token remains null (RSA16d)
      // Don't restore the old token - it was invalid
      rethrow;
    }
  }

  @override
  Future<TokenDetails> getValidToken() async {
    // Return cached token if valid (not expired)
    if (_currentToken != null && !_currentToken!.isExpired) {
      _logger.debug('Using cached token', {
        if (_currentToken!.expires != null) 'expires': _currentToken!.expires,
      });
      return _currentToken!;
    }
    _logger.warn('Token expired, renewing');
    // Otherwise get a new token — getValidToken must always return a token,
    // so if authorize() returns null (basic auth switch), fall back to
    // requestToken() which always produces one.
    final token = await authorize();
    if (token != null) return token;
    return requestToken();
  }

  @override
  Future<TokenRequest> createTokenRequest({
    AuthOptions? authOptions,
    TokenParams? tokenParams,
  }) async {
    _logger.info('createTokenRequest() called');
    // RSA9: Create a signed token request
    final effectiveOptions = authOptions ?? _storedAuthOptions ?? _options;
    final key = effectiveOptions.key ?? _options.key;

    if (key == null) {
      throw const AblyException(
        message: 'API key required to create token request',
        errorInfo: ErrorInfo(
          message: 'API key required to create token request',
          code: 40101,
          statusCode: 401,
        ),
      );
    }

    // Parse key into keyName and keySecret
    final keyParts = key.split(':');
    if (keyParts.length != 2) {
      throw const AblyException(
        message: 'Invalid API key format',
        errorInfo: ErrorInfo(
          message: 'Invalid API key format',
          code: 40101,
          statusCode: 401,
        ),
      );
    }
    final keyName = keyParts[0];
    final keySecret = keyParts[1];

    // Merge token params
    final effectiveParams = _mergeTokenParams(tokenParams);

    // Generate nonce if not provided (RSA9c)
    final nonce = effectiveParams.nonce ?? _generateNonce();

    // Get timestamp
    int timestamp;
    if (effectiveParams.timestamp != null) {
      timestamp = effectiveParams.timestamp!;
    } else if (effectiveOptions.queryTime == true ||
        _options.queryTime == true) {
      // Query server time
      final serverTime = await _queryServerTime();
      timestamp = serverTime.millisecondsSinceEpoch;
    } else {
      timestamp = clock.now().millisecondsSinceEpoch;
    }

    // Build the token request
    // RSA5/RSA6: ttl and capability are nullable — null means server decides
    final ttl = effectiveParams.ttl;
    final capability = effectiveParams.capability;
    final requestClientId = effectiveParams.clientId ?? _options.clientId;

    // Create the signing text (RSA9g)
    // Null values produce empty string in the signing text.
    // Trailing newline is required (matches ably-js and ably-python).
    final signText = [
      keyName,
      ttl?.toString() ?? '',
      capability ?? '',
      requestClientId ?? '',
      timestamp.toString(),
      nonce,
      '', // trailing newline
    ].join('\n');

    // Sign with HMAC-SHA256 (RSA9h)
    final mac = _sign(signText, keySecret);

    return TokenRequest(
      keyName: keyName,
      nonce: nonce,
      mac: mac,
      capability: capability,
      clientId: requestClientId,
      timestamp: timestamp,
      ttl: ttl,
    );
  }

  @override
  Future<TokenDetails> requestToken({
    AuthOptions? authOptions,
    TokenParams? tokenParams,
  }) async {
    _logger.info('requestToken() called');
    // RSA8: Request a token without updating stored token
    final effectiveOptions = authOptions ?? _storedAuthOptions ?? _options;
    final effectiveParams = _mergeTokenParams(tokenParams);

    // Try different token acquisition methods in order
    // 1. authCallback
    if (effectiveOptions.authCallback != null) {
      _logger.debug('Requesting token', {'via': 'callback'});
      return _requestTokenFromCallback(effectiveOptions, effectiveParams);
    }

    // 2. authUrl
    if (effectiveOptions.authUrl != null) {
      _logger.debug('Requesting token', {'via': 'url'});
      return _requestTokenFromUrl(effectiveOptions, effectiveParams);
    }

    // 3. Direct token request using API key
    if (effectiveOptions.key != null || _options.key != null) {
      _logger.debug('Requesting token', {'via': 'ably'});
      return _requestTokenFromAbly(effectiveOptions, effectiveParams);
    }

    _logger.error('Authorization failed', {
      'code': 40101,
      'message': 'No authentication method available',
    });
    throw const AblyException(
      message: 'No authentication method available',
      errorInfo: ErrorInfo(
        message: 'No authentication method available',
        code: 40101,
        statusCode: 401,
      ),
    );
  }

  Future<TokenDetails> _requestTokenFromCallback(
    AuthOptions options,
    TokenParams params,
  ) async {
    final result = await options.authCallback!(params);

    if (result is TokenDetails) {
      return result;
    }

    if (result is TokenRequest) {
      // Exchange token request for token
      return _exchangeTokenRequest(result);
    }

    if (result is String) {
      // RSA4f: Validate token string size (max 128KiB = 131072 bytes)
      if (result.length > 131072) {
        throw const AblyException(
          message: 'Invalid authCallback result: token string exceeds 128KiB',
          errorInfo: ErrorInfo(
            message: 'Invalid authCallback result: token string exceeds 128KiB',
            code: 40170,
            statusCode: 401,
          ),
        );
      }
      // Could be a raw token or JWT
      return TokenDetails(token: result);
    }

    if (result is Map<String, dynamic>) {
      // Could be TokenDetails or TokenRequest as JSON
      if (result.containsKey('mac')) {
        return _exchangeTokenRequest(TokenRequest.fromMap(result));
      }
      return TokenDetails.fromMap(result);
    }

    throw AblyException(
      message: 'Invalid authCallback result: ${result.runtimeType}',
      errorInfo: ErrorInfo(
        message: 'Invalid authCallback result: ${result.runtimeType}',
        code: 40170,
        statusCode: 401,
      ),
    );
  }

  Future<TokenDetails> _requestTokenFromUrl(
    AuthOptions options,
    TokenParams params,
  ) async {
    // Build request URL with params
    var uri = Uri.parse(options.authUrl!);

    final queryParams = Map<String, String>.from(options.authParams ?? {});
    queryParams.addAll(params.toQueryParams());

    final method = (options.authMethod ?? 'GET').toUpperCase();

    // Build headers
    final headers = Map<String, String>.from(options.authHeaders ?? {});

    http.Response response;
    if (method == 'GET') {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, ...queryParams},
      );
      response = await _rawHttpClient.get(uri, headers: headers);
    } else {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      response = await _rawHttpClient.post(
        uri,
        headers: headers,
        body: queryParams,
      );
    }

    // Parse response
    dynamic body;
    // HTTP headers are case-insensitive, check both variations
    final contentType = response.headers['content-type'] ??
        response.headers['Content-Type'] ??
        '';
    if (contentType.contains('application/json')) {
      body = json.decode(response.body);
    } else {
      // Try to parse as JSON anyway if it looks like JSON
      final trimmed = response.body.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          body = json.decode(response.body);
        } catch (_) {
          body = response.body;
        }
      } else {
        body = response.body;
      }
    }

    if (body is Map<String, dynamic>) {
      if (body.containsKey('mac')) {
        // It's a TokenRequest
        return _exchangeTokenRequest(TokenRequest.fromMap(body));
      }
      // It's TokenDetails
      return TokenDetails.fromMap(body);
    }

    if (body is String) {
      // Raw token string
      return TokenDetails(token: body);
    }

    throw AblyException(
      message: 'Invalid authUrl response',
      errorInfo: ErrorInfo(
        message: 'Invalid authUrl response: ${body.runtimeType}',
        code: 40170,
        statusCode: 401,
      ),
    );
  }

  Future<TokenDetails> _requestTokenFromAbly(
    AuthOptions options,
    TokenParams params,
  ) async {
    // Create a signed token request
    final tokenRequest = await createTokenRequest(
      authOptions: options,
      tokenParams: params,
    );

    return _exchangeTokenRequest(tokenRequest);
  }

  Future<TokenDetails> _exchangeTokenRequest(TokenRequest tokenRequest) async {
    // POST the token request to Ably
    final response = await _httpClient.request(
      'POST',
      '/keys/${tokenRequest.keyName}/requestToken',
      body: tokenRequest.toMap(),
      authenticated: false, // Token requests are self-authenticating via MAC
    );

    return TokenDetails.fromMap(response.body as Map<String, dynamic>);
  }

  TokenParams _mergeTokenParams(TokenParams? params) {
    // Merge with stored params and default params
    final defaults = _options.defaultTokenParams;
    final stored = _storedTokenParams;

    return TokenParams(
      capability:
          params?.capability ?? stored?.capability ?? defaults?.capability,
      clientId: params?.clientId ??
          stored?.clientId ??
          defaults?.clientId ??
          _options.clientId,
      nonce: params?.nonce ?? stored?.nonce ?? defaults?.nonce,
      timestamp: params?.timestamp ?? stored?.timestamp ?? defaults?.timestamp,
      ttl: params?.ttl ?? stored?.ttl ?? defaults?.ttl,
    );
  }

  Future<DateTime> _queryServerTime() async {
    final response = await _httpClient.request(
      'GET',
      '/time',
      authenticated: false,
    );

    final timestamps = response.body as List<dynamic>;
    return DateTime.fromMillisecondsSinceEpoch(timestamps[0] as int);
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _sign(String text, String secret) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(text);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return base64.encode(digest.bytes);
  }

  @override
  Future<TokenRevocationResponse> revokeTokens(
    List<TokenRevocationTargetSpecifier> specifiers, {
    RevokeTokensOptions? options,
  }) async {
    _logger.info('revokeTokens() called', {'targetCount': specifiers.length});
    // RSA17d: Token auth clients cannot revoke tokens
    if (_shouldUseTokenAuth()) {
      throw const AblyException(
        message: 'Cannot revoke tokens when using token authentication',
        errorInfo: ErrorInfo(
          message: 'Cannot revoke tokens when using token authentication',
          code: 40162,
          statusCode: 401,
        ),
      );
    }

    final apiKey = _options.key;
    if (apiKey == null) {
      throw const AblyException(
        message: 'API key required to revoke tokens',
        errorInfo: ErrorInfo(
          message: 'API key required to revoke tokens',
          code: 40101,
          statusCode: 401,
        ),
      );
    }

    // RSA17g: Extract key name for the path
    final keyName = apiKey.split(':')[0];

    // RSA17b: Map specifiers to type:value strings
    final targets = specifiers.map((s) => s.toTargetString()).toList();

    // Build request body
    final body = <String, dynamic>{
      'targets': targets,
    };

    // RSA17e: Optional issuedBefore
    if (options?.issuedBefore != null) {
      body['issuedBefore'] = options!.issuedBefore;
    }

    // RSA17f: Optional allowReauthMargin
    if (options?.allowReauthMargin != null) {
      body['allowReauthMargin'] = options!.allowReauthMargin;
    }

    final response = await _httpClient.request(
      'POST',
      '/keys/$keyName/revokeTokens',
      body: body,
      returnErrorBody: true,
    );

    final responseBody = response.body;

    // With X-Ably-Version >= 3, the server returns a BatchResult envelope:
    // {successCount, failureCount, results: [...]}
    if (responseBody is Map<String, dynamic> &&
        responseBody.containsKey('results')) {
      return TokenRevocationResponse.fromMap(responseBody);
    }

    // Server error — propagate as exception
    if (responseBody is Map<String, dynamic> &&
        responseBody.containsKey('error')) {
      final errorInfo =
          ErrorInfo.fromMap(responseBody['error'] as Map<String, dynamic>);
      throw AblyException.fromErrorInfo(errorInfo);
    }

    throw AblyException(
      message: 'Unexpected revokeTokens response format',
      errorInfo: ErrorInfo(
        message: 'Unexpected response body type: ${responseBody.runtimeType}',
        statusCode: response.statusCode,
        code: 50000,
      ),
    );
  }
}

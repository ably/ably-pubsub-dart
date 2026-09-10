import 'package:meta/meta.dart';

import '../logging/log_handler.dart';
import '../logging/log_level.dart';
import '../push/push_platform.dart';
import 'auth_options.dart';
import 'token_details.dart';
import 'token_params.dart';

/// Configuration options for the Ably REST client.
///
/// Extends [AuthOptions] with client-specific configuration.
///
/// Spec: TO, RSC1, REC1, REC2, REC3
@immutable
class ClientOptions extends AuthOptions {
  /// Creates a ClientOptions instance.
  factory ClientOptions({
    // AuthOptions fields
    String? key,
    String? authUrl,
    String? authMethod,
    Map<String, String>? authHeaders,
    Map<String, String>? authParams,
    AuthCallback? authCallback,
    TokenDetails? tokenDetails,
    String? token,
    bool? queryTime,
    bool? useTokenAuth,
    // ClientOptions specific fields
    String? clientId,
    LogLevel logLevel = LogLevel.warn,
    LogHandler? logHandler,
    bool tls = true,
    String? endpoint,
    int? port,
    int? tlsPort,
    List<String>? fallbackHosts,
    int httpMaxRetryCount = 3,
    int httpOpenTimeout = 4000,
    int httpRequestTimeout = 10000,
    int fallbackRetryTimeout = 600000,
    bool useBinaryProtocol = true,
    bool idempotentRestPublishing = true,
    bool addRequestIds = false,
    int maxMessageSize = 65536,
    TokenParams? defaultTokenParams,
    Map<String, String>? transportParams,
    Map<String, String>? agents,
    String? connectivityCheckUrl,
    bool echoMessages = true,
    bool queueMessages = true,
    bool autoConnect = true,
    int realtimeRequestTimeout = 10000,
    int disconnectedRetryTimeout = 15000,
    int suspendedRetryTimeout = 30000,
    int channelRetryTimeout = 15000,
    String? recover,
    Map<String, Object>? plugins,
    PushPlatformConfig? pushPlatform,
  }) {
    return ClientOptions._(
      key: key,
      authUrl: authUrl,
      authMethod: authMethod,
      authHeaders: authHeaders,
      authParams: authParams,
      authCallback: authCallback,
      tokenDetails: tokenDetails,
      token: token,
      queryTime: queryTime,
      useTokenAuth: useTokenAuth,
      clientId: clientId,
      logLevel: logLevel,
      logHandler: logHandler,
      tls: tls,
      endpoint: endpoint,
      port: port,
      tlsPort: tlsPort,
      fallbackHosts: fallbackHosts,
      httpMaxRetryCount: httpMaxRetryCount,
      httpOpenTimeout: httpOpenTimeout,
      httpRequestTimeout: httpRequestTimeout,
      fallbackRetryTimeout: fallbackRetryTimeout,
      useBinaryProtocol: useBinaryProtocol,
      idempotentRestPublishing: idempotentRestPublishing,
      addRequestIds: addRequestIds,
      maxMessageSize: maxMessageSize,
      defaultTokenParams: defaultTokenParams,
      transportParams: transportParams,
      agents: agents,
      connectivityCheckUrl: connectivityCheckUrl,
      echoMessages: echoMessages,
      queueMessages: queueMessages,
      autoConnect: autoConnect,
      realtimeRequestTimeout: realtimeRequestTimeout,
      disconnectedRetryTimeout: disconnectedRetryTimeout,
      suspendedRetryTimeout: suspendedRetryTimeout,
      channelRetryTimeout: channelRetryTimeout,
      recover: recover,
      plugins: plugins,
      pushPlatform: pushPlatform,
    );
  }

  /// Internal const constructor.
  const ClientOptions._({
    // AuthOptions fields
    super.key,
    super.authUrl,
    super.authMethod,
    super.authHeaders,
    super.authParams,
    super.authCallback,
    super.tokenDetails,
    super.token,
    super.queryTime,
    super.useTokenAuth,
    // ClientOptions specific fields
    this.clientId,
    this.logLevel = LogLevel.warn,
    this.logHandler,
    this.tls = true,
    this.endpoint,
    this.port,
    this.tlsPort,
    this.fallbackHosts,
    this.httpMaxRetryCount = 3,
    this.httpOpenTimeout = 4000,
    this.httpRequestTimeout = 10000,
    this.fallbackRetryTimeout = 600000,
    this.useBinaryProtocol = true,
    this.idempotentRestPublishing = true,
    this.addRequestIds = false,
    this.maxMessageSize = 65536,
    this.defaultTokenParams,
    this.transportParams,
    this.agents,
    this.connectivityCheckUrl,
    this.echoMessages = true,
    this.queueMessages = true,
    this.autoConnect = true,
    this.realtimeRequestTimeout = 10000,
    this.disconnectedRetryTimeout = 15000,
    this.suspendedRetryTimeout = 30000,
    this.channelRetryTimeout = 15000,
    this.recover,
    this.plugins,
    this.pushPlatform,
  });

  /// Creates ClientOptions from an API key string.
  ///
  /// Throws [ArgumentError] if the key format is invalid.
  /// Valid format is: `keyName:keySecret`
  ///
  /// Spec: RSC1
  factory ClientOptions.fromKey(
    String key, {
    bool useBinaryProtocol = true,
  }) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'API key cannot be empty');
    }
    final parts = key.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        'Invalid API key format. Expected format: keyName:keySecret',
      );
    }
    return ClientOptions._(key: key, useBinaryProtocol: useBinaryProtocol);
  }

  /// The clientId to use for this client.
  ///
  /// The clientId identifies the client to Ably and is associated with
  /// all messages and presence events.
  final String? clientId;

  /// Log level for SDK logging (TO3b).
  ///
  /// Defaults to [LogLevel.warn] (RSC2).
  final LogLevel logLevel;

  /// Custom log handler (TO3c).
  ///
  /// If not provided, logs are printed to stdout.
  final LogHandler? logHandler;

  /// Whether to use TLS for connections.
  ///
  /// Defaults to true.
  final bool tls;

  /// Endpoint configuration (REC1b).
  ///
  /// Can be:
  /// - An explicit hostname (contains '.' or is 'localhost' or IPv6)
  /// - A nonprod routing policy (format: 'nonprod:id')
  /// - A production routing policy (other values)
  final String? endpoint;

  /// Custom non-TLS port.
  final int? port;

  /// Custom TLS port.
  final int? tlsPort;

  /// List of fallback hosts to use if the primary fails.
  final List<String>? fallbackHosts;

  /// Maximum number of HTTP request retries.
  ///
  /// Defaults to 3.
  final int httpMaxRetryCount;

  /// HTTP connection open timeout in milliseconds.
  ///
  /// Defaults to 4000.
  final int httpOpenTimeout;

  /// HTTP request timeout in milliseconds.
  ///
  /// Defaults to 10000.
  final int httpRequestTimeout;

  /// Fallback retry timeout in milliseconds.
  ///
  /// Defaults to 600000 (10 minutes).
  final int fallbackRetryTimeout;

  /// Whether to use binary protocol (MessagePack) instead of JSON.
  ///
  /// Defaults to true.
  final bool useBinaryProtocol;

  /// Whether to use idempotent REST publishing.
  ///
  /// When true, the SDK generates message IDs to enable retries
  /// without duplicate publishing.
  ///
  /// Defaults to true.
  final bool idempotentRestPublishing;

  /// Whether to add request IDs to every HTTP request.
  ///
  /// Defaults to false.
  final bool addRequestIds;

  /// Maximum message size in bytes.
  ///
  /// Defaults to 65536 (64KB).
  final int maxMessageSize;

  /// Default token parameters for token requests.
  final TokenParams? defaultTokenParams;

  /// Custom transport parameters to add to connection.
  final Map<String, String>? transportParams;

  /// Custom agent identifiers to add to the user-agent header.
  final Map<String, String>? agents;

  /// Custom connectivity check URL (REC3b).
  final String? connectivityCheckUrl;

  /// Whether to echo messages back to the sender.
  ///
  /// When true (default), messages published by this client will be echoed
  /// back to it on the same channel. When false, messages will not be echoed.
  ///
  /// This is sent as a query parameter in the WebSocket connection URL.
  ///
  /// Spec: RTC1a
  final bool echoMessages;

  /// Whether to queue messages when the connection is not CONNECTED.
  ///
  /// When true (default), messages published while the connection is
  /// INITIALIZED, CONNECTING, or DISCONNECTED are queued and sent once
  /// the connection becomes CONNECTED. When false, publishing in those
  /// states fails immediately.
  ///
  /// Spec: RTL6c2
  final bool queueMessages;

  /// Whether to automatically connect when the Realtime client is created.
  ///
  /// Defaults to true. Set to false to delay connection until connect() is called.
  final bool autoConnect;

  /// Timeout in milliseconds for realtime connection requests.
  ///
  /// Defaults to 10000 (10 seconds).
  final int realtimeRequestTimeout;

  /// Timeout in milliseconds before retrying from DISCONNECTED state.
  ///
  /// Defaults to 15000 (15 seconds).
  final int disconnectedRetryTimeout;

  /// Timeout in milliseconds before retrying from SUSPENDED state.
  ///
  /// Defaults to 30000 (30 seconds).
  final int suspendedRetryTimeout;

  /// Timeout in milliseconds before retrying a SUSPENDED channel.
  ///
  /// Defaults to 15000 (15 seconds).
  ///
  /// Spec: TO3l7
  final int channelRetryTimeout;

  /// Recovery key string for connection recovery.
  ///
  /// When set, the library will attempt to recover the connection state
  /// from the provided recovery key on first connect.
  ///
  /// Spec: RTC1c, TO3i
  final String? recover;

  /// Plugin map for extensible functionality.
  ///
  /// Keys are plugin type identifiers (e.g., `'vcdiff'` for delta decoding).
  /// Values are plugin objects that implement the appropriate interface
  /// (e.g., [VCDiffDecoder] for vcdiff plugins).
  ///
  /// Spec: TO3o, PC1, PC2, PC3
  final Map<String, Object>? plugins;

  /// The push platform for this client.
  ///
  /// Platforms that support receiving push notifications supply this,
  /// carrying the platform primitives (persistent storage and push transport
  /// token acquisition) plus the device attributes needed for registration.
  /// This is the injection point used by push activation tests (see the
  /// portable helper spec `mock_push_platform.md`).
  ///
  /// When absent, push activation is unavailable; only push administration
  /// (`push.admin`) can be used.
  final PushPlatformConfig? pushPlatform;

  /// Parses the endpoint to determine if it's an explicit hostname (REC1b2).
  ///
  /// Returns true if:
  /// - Contains a period (e.g., 'custom.host.com')
  /// - Is 'localhost'
  /// - Is an IPv6 address (contains '::')
  bool get _isExplicitHostname {
    if (endpoint == null) return false;
    return endpoint!.contains('.') ||
        endpoint!.toLowerCase() == 'localhost' ||
        endpoint!.contains('::');
  }

  /// Returns true if endpoint is a nonprod routing policy (REC1b3).
  ///
  /// Format: 'nonprod:id'
  bool get _isNonprodRoutingPolicy {
    if (endpoint == null) return false;
    return endpoint!.startsWith('nonprod:');
  }

  /// Returns the routing policy ID from the endpoint.
  String? get _routingPolicyId {
    if (endpoint == null) return null;
    if (_isNonprodRoutingPolicy) {
      return endpoint!.substring('nonprod:'.length);
    }
    if (!_isExplicitHostname) {
      return endpoint;
    }
    return null;
  }

  /// Returns the primary domain (REC1).
  ///
  /// The spec defines a single primary domain used for both REST and
  /// realtime connections.
  String get primaryDomain {
    // REC1b2: Endpoint as explicit hostname
    if (endpoint != null && _isExplicitHostname) {
      return endpoint!;
    }

    // REC1b3: Endpoint as nonprod routing policy
    if (endpoint != null && _isNonprodRoutingPolicy) {
      final id = _routingPolicyId;
      return '$id.realtime.ably-nonprod.net';
    }

    // REC1b4: Endpoint as production routing policy
    if (endpoint != null && !_isExplicitHostname) {
      final id = _routingPolicyId;
      return '$id.realtime.ably.net';
    }

    // REC1a: Default primary domain
    return 'main.realtime.ably.net';
  }

  /// Returns the effective REST host.
  ///
  /// Per REC1, both REST and realtime use the same primary domain.
  String get effectiveRestHost => primaryDomain;

  /// Returns the effective realtime host.
  ///
  /// Per REC1, both REST and realtime use the same primary domain.
  String get effectiveRealtimeHost => primaryDomain;

  /// Returns the effective port.
  int get effectivePort {
    if (tls) {
      return tlsPort ?? 443;
    } else {
      return port ?? 80;
    }
  }

  /// Returns the base URL for REST requests.
  String get restBaseUrl {
    final scheme = tls ? 'https' : 'http';
    final hostPort = effectivePort == (tls ? 443 : 80)
        ? effectiveRestHost
        : '$effectiveRestHost:$effectivePort';
    return '$scheme://$hostPort';
  }

  /// Returns the effective fallback hosts (REC2).
  ///
  /// Returns null if fallbacks should not be used.
  List<String>? get effectiveFallbackHosts {
    // REC2a2: Custom fallbackHosts option takes precedence
    if (fallbackHosts != null) {
      return fallbackHosts;
    }

    // REC2c2: Explicit hostname endpoint has no fallbacks
    if (endpoint != null && _isExplicitHostname) {
      return null;
    }

    // REC2c3: Nonprod routing policy fallback domains
    if (endpoint != null && _isNonprodRoutingPolicy) {
      final id = _routingPolicyId;
      return [
        '$id.a.fallback.ably-realtime-nonprod.com',
        '$id.b.fallback.ably-realtime-nonprod.com',
        '$id.c.fallback.ably-realtime-nonprod.com',
        '$id.d.fallback.ably-realtime-nonprod.com',
        '$id.e.fallback.ably-realtime-nonprod.com',
      ];
    }

    // REC2c4: Production routing policy fallback domains (via endpoint)
    if (endpoint != null && !_isExplicitHostname) {
      final id = _routingPolicyId;
      return [
        '$id.a.fallback.ably-realtime.com',
        '$id.b.fallback.ably-realtime.com',
        '$id.c.fallback.ably-realtime.com',
        '$id.d.fallback.ably-realtime.com',
        '$id.e.fallback.ably-realtime.com',
      ];
    }

    // REC2c1: Default fallback domains
    return null; // Will use defaultFallbackHosts from constants
  }

  /// Returns the connectivity check URL (REC3).
  String get effectiveConnectivityCheckUrl {
    // REC3b: Custom connectivity check URL
    if (connectivityCheckUrl != null) {
      return connectivityCheckUrl!;
    }

    // REC3a: Default connectivity check URL
    return 'https://internet-up.ably-realtime.com/is-the-internet-up.txt';
  }

  /// Creates a copy of this ClientOptions with the given fields replaced.
  @override
  ClientOptions copyWith({
    String? key,
    String? authUrl,
    String? authMethod,
    Map<String, String>? authHeaders,
    Map<String, String>? authParams,
    AuthCallback? authCallback,
    TokenDetails? tokenDetails,
    String? token,
    bool? queryTime,
    bool? useTokenAuth,
    String? clientId,
    LogLevel? logLevel,
    LogHandler? logHandler,
    bool? tls,
    String? endpoint,
    int? port,
    int? tlsPort,
    List<String>? fallbackHosts,
    int? httpMaxRetryCount,
    int? httpOpenTimeout,
    int? httpRequestTimeout,
    int? fallbackRetryTimeout,
    bool? useBinaryProtocol,
    bool? idempotentRestPublishing,
    bool? addRequestIds,
    int? maxMessageSize,
    TokenParams? defaultTokenParams,
    Map<String, String>? transportParams,
    Map<String, String>? agents,
    String? connectivityCheckUrl,
    bool? echoMessages,
    bool? queueMessages,
    bool? autoConnect,
    int? realtimeRequestTimeout,
    int? disconnectedRetryTimeout,
    int? suspendedRetryTimeout,
    int? channelRetryTimeout,
    String? recover,
    Map<String, Object>? plugins,
    PushPlatformConfig? pushPlatform,
  }) {
    return ClientOptions._(
      key: key ?? this.key,
      authUrl: authUrl ?? this.authUrl,
      authMethod: authMethod ?? this.authMethod,
      authHeaders: authHeaders ?? this.authHeaders,
      authParams: authParams ?? this.authParams,
      authCallback: authCallback ?? this.authCallback,
      tokenDetails: tokenDetails ?? this.tokenDetails,
      token: token ?? this.token,
      queryTime: queryTime ?? this.queryTime,
      useTokenAuth: useTokenAuth ?? this.useTokenAuth,
      clientId: clientId ?? this.clientId,
      logLevel: logLevel ?? this.logLevel,
      logHandler: logHandler ?? this.logHandler,
      tls: tls ?? this.tls,
      endpoint: endpoint ?? this.endpoint,
      port: port ?? this.port,
      tlsPort: tlsPort ?? this.tlsPort,
      fallbackHosts: fallbackHosts ?? this.fallbackHosts,
      httpMaxRetryCount: httpMaxRetryCount ?? this.httpMaxRetryCount,
      httpOpenTimeout: httpOpenTimeout ?? this.httpOpenTimeout,
      httpRequestTimeout: httpRequestTimeout ?? this.httpRequestTimeout,
      fallbackRetryTimeout: fallbackRetryTimeout ?? this.fallbackRetryTimeout,
      useBinaryProtocol: useBinaryProtocol ?? this.useBinaryProtocol,
      idempotentRestPublishing:
          idempotentRestPublishing ?? this.idempotentRestPublishing,
      addRequestIds: addRequestIds ?? this.addRequestIds,
      maxMessageSize: maxMessageSize ?? this.maxMessageSize,
      defaultTokenParams: defaultTokenParams ?? this.defaultTokenParams,
      transportParams: transportParams ?? this.transportParams,
      agents: agents ?? this.agents,
      connectivityCheckUrl: connectivityCheckUrl ?? this.connectivityCheckUrl,
      echoMessages: echoMessages ?? this.echoMessages,
      queueMessages: queueMessages ?? this.queueMessages,
      autoConnect: autoConnect ?? this.autoConnect,
      realtimeRequestTimeout:
          realtimeRequestTimeout ?? this.realtimeRequestTimeout,
      disconnectedRetryTimeout:
          disconnectedRetryTimeout ?? this.disconnectedRetryTimeout,
      suspendedRetryTimeout:
          suspendedRetryTimeout ?? this.suspendedRetryTimeout,
      channelRetryTimeout: channelRetryTimeout ?? this.channelRetryTimeout,
      recover: recover ?? this.recover,
      plugins: plugins ?? this.plugins,
      pushPlatform: pushPlatform ?? this.pushPlatform,
    );
  }

  @override
  String toString() {
    return 'ClientOptions(clientId=$clientId, tls=$tls, '
        'primaryDomain=$primaryDomain)';
  }
}

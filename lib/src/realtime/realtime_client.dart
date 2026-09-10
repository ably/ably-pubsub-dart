import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../auth/auth.dart';
import '../auth/client_options.dart';
import '../impl/realtime_client_impl.dart';
import '../pagination/http_paginated_response.dart';
import 'timer_manager.dart';
import '../pagination/paginated_result.dart';
import '../push/local_device.dart';
import '../push/push.dart';
import '../stats/stats.dart';
import 'connection.dart';
import 'realtime_channels.dart';
import 'websocket_client.dart';

/// The Ably Realtime client.
///
/// Provides access to realtime messaging, presence, and connection management.
///
/// Spec: RTC1
abstract class RealtimeClient {
  /// Creates a Realtime client with the given options.
  ///
  /// If [key] is provided, it will be used instead of options.key.
  ///
  /// Spec: RTC1a
  factory RealtimeClient({
    ClientOptions? options,
    String? key,
  }) {
    if (options == null && key == null) {
      throw ArgumentError('Must provide either options or key');
    }
    var resolvedOptions = options ?? ClientOptions(key: key);
    if (key != null && options != null) {
      resolvedOptions = resolvedOptions.copyWith(key: key);
    }
    return RealtimeClientImpl(options: resolvedOptions);
  }

  /// Creates a Realtime client from an API key.
  ///
  /// Spec: RTC1b
  factory RealtimeClient.fromKey(String key) {
    return RealtimeClientImpl(options: ClientOptions(key: key));
  }

  /// Creates a Realtime client with test configuration.
  ///
  /// This factory is only for testing purposes and allows injection of
  /// mock dependencies.
  @visibleForTesting
  factory RealtimeClient.forTesting({
    required ClientOptions options,
    WebSocketClient? webSocketClient,
    http.Client? httpClient,
    TimerManager? timerManager,
  }) {
    return RealtimeClientImpl(
      options: options,
      webSocketClient: webSocketClient,
      httpClient: httpClient,
      timerManager: timerManager,
    );
  }

  /// The connection object for this client.
  ///
  /// Spec: RTC2
  Connection get connection;

  /// The channels collection for this client.
  ///
  /// Spec: RTC3
  RealtimeChannels get channels;

  /// The auth object for this client.
  ///
  /// Spec: RTC4
  Auth get auth;

  /// The push interface for this client.
  ///
  /// Spec: RTC13
  Push get push;

  /// The local device for push notifications.
  ///
  /// Returns the current in-memory device, or null when it has not been
  /// loaded yet; use [getDevice] to load it from persisted state.
  ///
  /// Spec: RSH8
  LocalDevice? get device;
  set device(LocalDevice? device);

  /// Returns the [LocalDevice] representing the current state of the device
  /// in respect of it being a target for push notifications, loading it
  /// from persisted state on first call.
  ///
  /// Requires a push platform to be configured via
  /// `ClientOptions.pushPlatform`.
  ///
  /// Spec: RSH8, RSH8a
  Future<LocalDevice> getDevice();

  /// The client options for this client.
  ///
  /// Spec: RTC5
  ClientOptions get options;

  /// The clientId for this client.
  ///
  /// Spec: RTC17
  String? get clientId;

  /// Retrieves the server time from the Ably service.
  ///
  /// Spec: RTC6, RTC6a
  Future<DateTime> time();

  /// Gets application statistics.
  ///
  /// Spec: RTC5, RTC5a, RTC5b
  Future<PaginatedResult<Stats>> stats({
    DateTime? start,
    DateTime? end,
    StatsDirection? direction,
    int? limit,
    StatsUnit? unit,
  });

  /// Makes an arbitrary HTTP request to the Ably REST API.
  ///
  /// Spec: RTC9
  Future<HttpPaginatedResponse<dynamic>> request(
    String method,
    String path, {
    int? version,
    Map<String, String>? params,
    Map<String, String>? headers,
    Object? body,
  });

  /// Explicitly initiates a connection to Ably.
  ///
  /// Spec: RTC1c
  Future<void> connect();

  /// Closes the connection to Ably.
  ///
  /// Spec: RTC16
  Future<void> close();
}

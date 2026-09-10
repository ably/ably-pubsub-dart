import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../auth/auth.dart';
import '../auth/client_options.dart';
import '../batch/batch_presence_result.dart';
import '../batch/batch_publish_spec.dart';
import '../batch/batch_result.dart';
import '../channels/channels.dart';
import '../impl/rest_client_impl.dart';
import '../pagination/http_paginated_response.dart';
import '../pagination/paginated_result.dart';
import '../push/local_device.dart';
import '../push/push.dart';
import '../stats/stats.dart';

/// The Ably REST client.
///
/// Provides stateless access to the Ably REST API for publishing messages
/// and retrieving channel history.
///
/// Spec: RSC
abstract class RestClient {
  /// Creates a REST client with the given options.
  ///
  /// Spec: RSC1
  factory RestClient({
    required ClientOptions options,
  }) {
    return RestClientImpl(options: options);
  }

  /// Creates a REST client from an API key.
  ///
  /// This is a convenience constructor equivalent to:
  /// ```dart
  /// RestClient(options: ClientOptions.fromKey(key))
  /// ```
  ///
  /// Spec: RSC1
  factory RestClient.fromKey(String key) {
    return RestClientImpl(options: ClientOptions(key: key));
  }

  /// Creates a REST client with test configuration.
  ///
  /// This factory is only for testing purposes and allows injection of
  /// a mock [httpClient].
  @visibleForTesting
  factory RestClient.forTesting({
    required ClientOptions options,
    http.Client? httpClient,
  }) {
    return RestClientImpl(options: options, httpClient: httpClient);
  }

  /// The client options.
  ClientOptions get options;

  /// The auth interface for this client.
  ///
  /// Provides methods for token management and authentication.
  Auth get auth;

  /// The channels interface for this client.
  ///
  /// Provides access to REST channels for publishing and history.
  RestChannels get channels;

  /// The push interface for this client.
  ///
  /// Provides access to push notification administration.
  ///
  /// Spec: RSC21
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

  /// Gets the current server time.
  ///
  /// Useful for ensuring accurate timestamps in token requests.
  Future<DateTime> time();

  /// Gets application statistics.
  ///
  /// Returns a [PaginatedResult] containing [Stats] objects.
  ///
  /// Spec: RSC6
  Future<PaginatedResult<Stats>> stats({
    DateTime? start,
    DateTime? end,
    StatsDirection? direction,
    int? limit,
    StatsUnit? unit,
  });

  /// Makes an arbitrary HTTP request to the Ably REST API.
  ///
  /// This provides access to any REST API endpoint, including those not
  /// directly exposed by other client methods.
  ///
  /// The [method] parameter specifies the HTTP method (GET, POST, PUT, etc.).
  /// The [path] parameter specifies the API path (e.g., '/channels/foo/messages').
  ///
  /// Optional parameters:
  /// - [version]: Explicit API version (defaults to current version).
  /// - [params]: Query parameters to add to the request URL.
  /// - [headers]: Additional headers to include in the request.
  /// - [body]: Request body (will be JSON-encoded).
  ///
  /// Returns an [HttpPaginatedResponse] containing the response items and
  /// HTTP metadata (status code, headers, error codes).
  ///
  /// Spec: RSC19
  Future<HttpPaginatedResponse<dynamic>> request(
    String method,
    String path, {
    int? version,
    Map<String, String>? params,
    Map<String, String>? headers,
    Object? body,
  });

  /// Publishes messages to multiple channels in a single request.
  ///
  /// You can provide either:
  /// - A single [BatchPublishSpec] to publish to one or more channels
  /// - A list of [BatchPublishSpec] objects for multiple publish operations
  ///
  /// Returns a list of [BatchResult] objects indicating success or failure
  /// for each channel. When publishing to multiple channels, the result
  /// contains one entry per channel.
  ///
  /// Spec: RSC22
  Future<List<BatchResult>> batchPublish(
    Object spec, {
    Map<String, String>? params,
  });

  /// Retrieves presence state for multiple channels in a single request.
  ///
  /// Takes an array of channel name strings and sends them as a
  /// comma-separated `channels` query parameter in a GET request to
  /// `/presence`.
  ///
  /// Returns a [BatchPresenceResponse] containing per-channel results,
  /// each either a [BatchPresenceSuccessResult] with presence members
  /// or a [BatchPresenceFailureResult] with an error.
  ///
  /// Spec: RSC24
  Future<BatchPresenceResponse> batchPresence(List<String> channels);

  /// Closes this client and releases any resources.
  Future<void> close();
}

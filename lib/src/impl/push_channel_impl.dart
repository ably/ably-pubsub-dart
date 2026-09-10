import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../pagination/paginated_result.dart';
import '../push/local_device.dart';
import '../push/push_channel.dart';
import '../push/push_channel_subscription.dart';
import 'http/http_client.dart';
import 'paginated_result_impl.dart';

/// Implementation of [PushChannel] for per-channel push operations.
///
/// Spec: RSH7
class PushChannelImpl implements PushChannel {
  PushChannelImpl({
    required String channelName,
    required AblyHttpClient httpClient,
    required LocalDevice? Function() getDevice,
    Future<LocalDevice?> Function()? loadDevice,
  })  : _channelName = channelName,
        _httpClient = httpClient,
        _getDevice = getDevice,
        _loadDevice = loadDevice;

  final String _channelName;
  final AblyHttpClient _httpClient;
  final LocalDevice? Function() _getDevice;
  final Future<LocalDevice?> Function()? _loadDevice;

  static const _basePath = '/push/channelSubscriptions';

  /// Returns the current device, hydrating it from persisted state when
  /// first required (RSH8a), throwing if unavailable.
  Future<LocalDevice> _requireDevice() async {
    var device = _getDevice();
    device ??= await _loadDevice?.call();
    if (device == null) {
      throw const AblyException(
        message: 'No device registered',
        errorInfo: ErrorInfo(
          message: 'No device registered',
          code: 40000,
          statusCode: 400,
        ),
      );
    }
    return device;
  }

  /// Returns device auth headers (RSH6a).
  ///
  /// Throws if the device has no deviceIdentityToken.
  Map<String, String> _deviceAuthHeaders(LocalDevice device) {
    final token = device.deviceIdentityToken;
    if (token == null) {
      throw const AblyException(
        message: 'Device does not have a deviceIdentityToken',
        errorInfo: ErrorInfo(
          message: 'Device does not have a deviceIdentityToken',
          code: 40000,
          statusCode: 400,
        ),
      );
    }
    return {'X-Ably-DeviceToken': token};
  }

  /// Subscribes the current device to push notifications on this channel.
  ///
  /// RSH7a1: Fails if no deviceIdentityToken.
  /// RSH7a2: POSTs to /push/channelSubscriptions with deviceId and channel.
  /// RSH7a3: Uses device authentication.
  @override
  Future<void> subscribeDevice() async {
    final device = await _requireDevice();
    final headers = _deviceAuthHeaders(device);

    await _httpClient.request(
      'POST',
      _basePath,
      body: {
        'channel': _channelName,
        'deviceId': device.id,
      },
      customHeaders: headers,
    );
  }

  /// Subscribes the current client to push notifications on this channel.
  ///
  /// RSH7b1: Fails if no clientId.
  /// RSH7b2: POSTs to /push/channelSubscriptions with clientId and channel.
  @override
  Future<void> subscribeClient() async {
    final device = await _requireDevice();
    final clientId = device.clientId;
    if (clientId == null) {
      throw const AblyException(
        message: 'No clientId available',
        errorInfo: ErrorInfo(
          message: 'No clientId available',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    await _httpClient.request(
      'POST',
      _basePath,
      body: {
        'channel': _channelName,
        'clientId': clientId,
      },
    );
  }

  /// Unsubscribes the current device from push notifications on this channel.
  ///
  /// RSH7c1: Fails if no deviceIdentityToken.
  /// RSH7c2: DELETEs from /push/channelSubscriptions with deviceId and channel.
  /// RSH7c3: Uses device authentication.
  @override
  Future<void> unsubscribeDevice() async {
    final device = await _requireDevice();
    final headers = _deviceAuthHeaders(device);

    await _httpClient.request(
      'DELETE',
      _basePath,
      queryParams: {
        'channel': _channelName,
        'deviceId': device.id,
      },
      customHeaders: headers,
    );
  }

  /// Unsubscribes the current client from push notifications on this channel.
  ///
  /// RSH7d1: Fails if no clientId.
  /// RSH7d2: DELETEs from /push/channelSubscriptions with clientId and channel.
  @override
  Future<void> unsubscribeClient() async {
    final device = await _requireDevice();
    final clientId = device.clientId;
    if (clientId == null) {
      throw const AblyException(
        message: 'No clientId available',
        errorInfo: ErrorInfo(
          message: 'No clientId available',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    await _httpClient.request(
      'DELETE',
      _basePath,
      queryParams: {
        'channel': _channelName,
        'clientId': clientId,
      },
    );
  }

  /// Lists push channel subscriptions for this channel and device.
  ///
  /// RSH7e: GETs /push/channelSubscriptions with channel, deviceId,
  /// optional clientId, and concatFilters=true, merged with caller params.
  @override
  Future<PaginatedResult<PushChannelSubscription>> listSubscriptions(
    Map<String, String> params,
  ) async {
    final device = await _requireDevice();

    final queryParams = <String, String>{
      'channel': _channelName,
      'deviceId': device.id,
      'concatFilters': 'true',
    };

    if (device.clientId != null) {
      queryParams['clientId'] = device.clientId!;
    }

    // Merge caller-supplied params (e.g. limit, direction)
    queryParams.addAll(params);

    final response = await _httpClient.request(
      'GET',
      _basePath,
      queryParams: queryParams,
    );

    final items =
        PaginatedResultParser.parsePushChannelSubscriptions(response.body);

    return PaginatedResultImpl.fromResponse(
      response: response,
      items: items,
      fetcher: null,
    );
  }
}

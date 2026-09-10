import '../auth/client_options.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../pagination/paginated_result.dart';
import '../push/device_details.dart';
import '../push/local_device.dart';
import '../push/push.dart';
import '../push/push_admin.dart';
import '../push/push_channel_subscription.dart';
import '../push/push_channel_subscriptions.dart';
import '../push/push_device_registrations.dart';
import '../push/push_platform.dart';
import 'http/http_client.dart';
import 'paginated_result_impl.dart';
import 'push_activation_impl.dart';

/// Provides access to the client's push activation support, or null when no
/// push platform is configured.
typedef PushActivationProvider = PushActivation? Function();

/// Provides the client's current LocalDevice, or null when not loaded.
typedef LocalDeviceProvider = LocalDevice? Function();

/// Implementation of Push.
///
/// Spec: RSH1, RSH2
class PushImpl implements Push {
  PushImpl({
    required AblyHttpClient httpClient,
    required Logger logger,
    this.options,
    PushActivationProvider? getActivation,
    LocalDeviceProvider? getDevice,
  })  : _admin = PushAdminImpl(
          httpClient: httpClient,
          logger: logger,
          getDevice: getDevice,
        ),
        _logger = logger,
        _getActivation = getActivation;

  final PushAdminImpl _admin;
  final Logger _logger;
  final PushActivationProvider? _getActivation;

  /// The client options, providing access to the configured push platform
  /// ([ClientOptions.pushPlatform]) for activation.
  final ClientOptions? options;

  @override
  PushAdmin get admin => _admin;

  /// Returns the activation state machine, or throws when push activation
  /// is not available on this client (no push platform configured).
  ActivationStateMachine _requireMachine() {
    final activation = _getActivation?.call();
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
    return activation.machine;
  }

  // RSH2a — sends a CalledActivate event to the state machine.
  @override
  Future<void> activate({
    RegisterCallback? registerCallback,
    UpdatedCallback? updatedCallback,
  }) async {
    _logger.info('push.activate() called', {});
    final machine = _requireMachine();
    // RSH3h — the machine must not process events before initialisation.
    await machine.ensureInitialized();
    return machine.requestActivate(
      registerCallback: registerCallback,
      updatedCallback: updatedCallback,
    );
  }

  // RSH2b — sends a CalledDeactivate event to the state machine.
  @override
  Future<void> deactivate({
    DeregisterCallback? deregisterCallback,
  }) async {
    _logger.info('push.deactivate() called', {});
    final machine = _requireMachine();
    await machine.ensureInitialized();
    return machine.requestDeactivate(deregisterCallback: deregisterCallback);
  }

  // RSH2f — delivers a rotated or additional push transport token.
  @override
  Future<void> updateToken(PushDeviceToken token) async {
    _logger.info('push.updateToken() called', {
      'transportType': token.transportType,
      if (token.apnsTokenType != null) 'apnsTokenType': token.apnsTokenType,
    });

    // RSH2f1 — validation first, without any side effects.
    if ((token.transportType != 'fcm' && token.transportType != 'apns') ||
        token.token.isEmpty) {
      throw AblyException.fromErrorInfo(
        ErrorInfo(
          message: 'push.updateToken() requires a PushDeviceToken with '
              "transportType 'fcm' or 'apns' and a non-empty token "
              '(got transportType "${token.transportType}")',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    final machine = _requireMachine();
    await machine.ensureInitialized();
    final device = machine.device;

    // RSH2f2 — the device must have completed activation.
    if (device.deviceIdentityToken == null) {
      throw AblyException.fromErrorInfo(
        const ErrorInfo(
          message: 'Push token cannot be updated because the device is not '
              'activated for push notifications; call Push#activate first',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    // RSH2f3 — apply to the recipient slot, persist, then notify the
    // machine (RSH8g); the ensuing sync outcome is reported through the
    // updatedCallback provided to Push#activate.
    device.recipient = LocalDeviceManager.applyTokenToRecipient(
      device.recipient,
      token,
    );
    await device.persistRecipient();
    machine.handleEvent(const GotPushDeviceDetails());
  }
}

/// Implementation of PushAdmin.
///
/// Spec: RSH1a–RSH1c
class PushAdminImpl implements PushAdmin {
  PushAdminImpl({
    required AblyHttpClient httpClient,
    required Logger logger,
    LocalDeviceProvider? getDevice,
  })  : _httpClient = httpClient,
        _logger = logger,
        _getDevice = getDevice;

  final AblyHttpClient _httpClient;
  final Logger _logger;
  final LocalDeviceProvider? _getDevice;

  late final PushDeviceRegistrationsImpl _deviceRegistrations =
      PushDeviceRegistrationsImpl(
    httpClient: _httpClient,
    logger: _logger,
    getDevice: _getDevice,
  );

  late final PushChannelSubscriptionsImpl _channelSubscriptions =
      PushChannelSubscriptionsImpl(
    httpClient: _httpClient,
    logger: _logger,
    getDevice: _getDevice,
  );

  @override
  PushDeviceRegistrations get deviceRegistrations => _deviceRegistrations;

  @override
  PushChannelSubscriptions get channelSubscriptions => _channelSubscriptions;

  @override
  Future<void> publish(
    Map<String, dynamic> recipient,
    Map<String, dynamic> data,
  ) async {
    _logger.info('push.admin.publish() called', {});

    // RSH1a: Reject empty recipient
    if (recipient.isEmpty) {
      throw const AblyException(
        message: 'Recipient must not be empty',
        errorInfo: ErrorInfo(
          message: 'Recipient must not be empty',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    // RSH1a: Reject empty data
    if (data.isEmpty) {
      throw const AblyException(
        message: 'Data must not be empty',
        errorInfo: ErrorInfo(
          message: 'Data must not be empty',
          code: 40000,
          statusCode: 400,
        ),
      );
    }

    final body = <String, dynamic>{
      'recipient': recipient,
      ...data,
    };

    await _httpClient.request('POST', '/push/publish', body: body);
  }
}

/// Push device authentication headers (RSH6) for an admin request that
/// references [deviceId], when it is that of the present client's activated
/// device; null otherwise.
///
/// Spec: RSH1b1, RSH1b3, RSH1b5, RSH1c3, RSH1c4
Map<String, String>? _ownDeviceAuthHeaders(
  LocalDeviceProvider? getDevice,
  String? deviceId,
) {
  if (deviceId == null) return null;
  final local = getDevice?.call();
  if (local == null || local.id != deviceId) return null;
  // RSH6a — the raw deviceIdentityToken when the device has completed
  // activation; RSH6b — the deviceSecret otherwise.
  final token = local.deviceIdentityToken;
  if (token != null) return {'X-Ably-DeviceToken': token};
  final secret = local.deviceSecret;
  if (secret != null) return {'X-Ably-DeviceSecret': secret};
  return null;
}

/// Implementation of PushDeviceRegistrations.
///
/// Spec: RSH1b1–RSH1b5
class PushDeviceRegistrationsImpl implements PushDeviceRegistrations {
  PushDeviceRegistrationsImpl({
    required AblyHttpClient httpClient,
    required Logger logger,
    LocalDeviceProvider? getDevice,
  })  : _httpClient = httpClient,
        _logger = logger,
        _getDevice = getDevice;

  final AblyHttpClient _httpClient;
  final Logger _logger;
  final LocalDeviceProvider? _getDevice;

  @override
  Future<DeviceDetails> get(String deviceId) async {
    _logger.info('push.admin.deviceRegistrations.get() called', {
      'deviceId': deviceId,
    });

    final path = '/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}';
    final response = await _httpClient.request(
      'GET',
      path,
      // RSH1b1 — device auth when the deviceId is the present client's
      customHeaders: _ownDeviceAuthHeaders(_getDevice, deviceId),
    );
    return DeviceDetails.fromMap(response.body as Map<String, dynamic>);
  }

  @override
  Future<PaginatedResult<DeviceDetails>> list(
    Map<String, String> params,
  ) async {
    _logger.info('push.admin.deviceRegistrations.list() called', {});

    final response = await _httpClient.request(
      'GET',
      '/push/deviceRegistrations',
      queryParams: params.isNotEmpty ? params : null,
    );

    final items = PaginatedResultParser.parseDeviceDetails(response.body);

    return PaginatedResultImpl.fromResponse<DeviceDetails>(
      response: response,
      items: items,
      fetcher: _fetchDeviceDetailsPage,
      requestPath: '/push/deviceRegistrations',
    );
  }

  Future<PaginatedResult<DeviceDetails>> _fetchDeviceDetailsPage(
    String url,
  ) async {
    final uri = Uri.parse(url);
    final path = uri.path;
    final response = await _httpClient.request(
      'GET',
      path,
      queryParams: uri.queryParameters.isNotEmpty
          ? Map<String, String>.from(uri.queryParameters)
          : null,
    );
    final items = PaginatedResultParser.parseDeviceDetails(response.body);
    return PaginatedResultImpl.fromResponse<DeviceDetails>(
      response: response,
      items: items,
      fetcher: _fetchDeviceDetailsPage,
      requestPath: path,
    );
  }

  @override
  Future<DeviceDetails> save(DeviceDetails device) async {
    _logger.info('push.admin.deviceRegistrations.save() called', {
      'deviceId': device.id,
    });

    final path = '/push/deviceRegistrations/${Uri.encodeComponent(device.id)}';
    final response = await _httpClient.request(
      'PUT',
      path,
      body: device.toMap(),
      // RSH1b3 — device auth when the deviceId is the present client's
      customHeaders: _ownDeviceAuthHeaders(_getDevice, device.id),
    );
    return DeviceDetails.fromMap(response.body as Map<String, dynamic>);
  }

  @override
  Future<void> remove(String deviceId) async {
    _logger.info('push.admin.deviceRegistrations.remove() called', {
      'deviceId': deviceId,
    });

    final path = '/push/deviceRegistrations/${Uri.encodeComponent(deviceId)}';
    await _httpClient.request('DELETE', path);
  }

  @override
  Future<void> removeWhere(Map<String, String> params) async {
    _logger.info('push.admin.deviceRegistrations.removeWhere() called', {});

    await _httpClient.request(
      'DELETE',
      '/push/deviceRegistrations',
      queryParams: params.isNotEmpty ? params : null,
      // RSH1b5 — device auth when the deviceId param is the present client's
      customHeaders: _ownDeviceAuthHeaders(_getDevice, params['deviceId']),
    );
  }
}

/// Implementation of PushChannelSubscriptions.
///
/// Spec: RSH1c1–RSH1c5
class PushChannelSubscriptionsImpl implements PushChannelSubscriptions {
  PushChannelSubscriptionsImpl({
    required AblyHttpClient httpClient,
    required Logger logger,
    LocalDeviceProvider? getDevice,
  })  : _httpClient = httpClient,
        _logger = logger,
        _getDevice = getDevice;

  final AblyHttpClient _httpClient;
  final Logger _logger;
  final LocalDeviceProvider? _getDevice;

  @override
  Future<PaginatedResult<PushChannelSubscription>> list(
    Map<String, String> params,
  ) async {
    _logger.info('push.admin.channelSubscriptions.list() called', {});

    final response = await _httpClient.request(
      'GET',
      '/push/channelSubscriptions',
      queryParams: params.isNotEmpty ? params : null,
    );

    final items =
        PaginatedResultParser.parsePushChannelSubscriptions(response.body);

    return PaginatedResultImpl.fromResponse<PushChannelSubscription>(
      response: response,
      items: items,
      fetcher: _fetchSubscriptionsPage,
      requestPath: '/push/channelSubscriptions',
    );
  }

  Future<PaginatedResult<PushChannelSubscription>> _fetchSubscriptionsPage(
    String url,
  ) async {
    final uri = Uri.parse(url);
    final path = uri.path;
    final response = await _httpClient.request(
      'GET',
      path,
      queryParams: uri.queryParameters.isNotEmpty
          ? Map<String, String>.from(uri.queryParameters)
          : null,
    );
    final items =
        PaginatedResultParser.parsePushChannelSubscriptions(response.body);
    return PaginatedResultImpl.fromResponse<PushChannelSubscription>(
      response: response,
      items: items,
      fetcher: _fetchSubscriptionsPage,
      requestPath: path,
    );
  }

  @override
  Future<PaginatedResult<String>> listChannels(
    Map<String, String> params,
  ) async {
    _logger.info('push.admin.channelSubscriptions.listChannels() called', {});

    final response = await _httpClient.request(
      'GET',
      '/push/channels',
      queryParams: params.isNotEmpty ? params : null,
    );

    final items = PaginatedResultParser.parseStringList(response.body);

    return PaginatedResultImpl.fromResponse<String>(
      response: response,
      items: items,
      fetcher: _fetchChannelsPage,
      requestPath: '/push/channels',
    );
  }

  Future<PaginatedResult<String>> _fetchChannelsPage(String url) async {
    final uri = Uri.parse(url);
    final path = uri.path;
    final response = await _httpClient.request(
      'GET',
      path,
      queryParams: uri.queryParameters.isNotEmpty
          ? Map<String, String>.from(uri.queryParameters)
          : null,
    );
    final items = PaginatedResultParser.parseStringList(response.body);
    return PaginatedResultImpl.fromResponse<String>(
      response: response,
      items: items,
      fetcher: _fetchChannelsPage,
      requestPath: path,
    );
  }

  @override
  Future<PushChannelSubscription> save(
    PushChannelSubscription subscription,
  ) async {
    _logger.info('push.admin.channelSubscriptions.save() called', {
      'channel': subscription.channel,
    });

    final response = await _httpClient.request(
      'POST',
      '/push/channelSubscriptions',
      body: subscription.toMap(),
      // RSH1c3 — device auth when the subscription's deviceId is the
      // present client's
      customHeaders: _ownDeviceAuthHeaders(_getDevice, subscription.deviceId),
    );
    return PushChannelSubscription.fromMap(
      response.body as Map<String, dynamic>,
    );
  }

  @override
  Future<void> remove(PushChannelSubscription subscription) async {
    _logger.info('push.admin.channelSubscriptions.remove() called', {
      'channel': subscription.channel,
    });

    // RSH1c4: Send subscription attributes as query params
    final params = <String, String>{
      'channel': subscription.channel,
    };
    if (subscription.deviceId != null) {
      params['deviceId'] = subscription.deviceId!;
    }
    if (subscription.clientId != null) {
      params['clientId'] = subscription.clientId!;
    }

    await _httpClient.request(
      'DELETE',
      '/push/channelSubscriptions',
      queryParams: params,
      // RSH1c4 — device auth when the subscription's deviceId is the
      // present client's
      customHeaders: _ownDeviceAuthHeaders(_getDevice, subscription.deviceId),
    );
  }

  @override
  Future<void> removeWhere(Map<String, String> params) async {
    _logger.info('push.admin.channelSubscriptions.removeWhere() called', {});

    await _httpClient.request(
      'DELETE',
      '/push/channelSubscriptions',
      queryParams: params.isNotEmpty ? params : null,
    );
  }
}

import 'dart:async';
import 'dart:convert';

import '../auth/client_options.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../push/local_device.dart';
import '../realtime/channel_state.dart';
import '../realtime/connection_state.dart';
import '../realtime/connection_state_change.dart';
import '../realtime/derive_options.dart';
import '../realtime/realtime_channel.dart';
import '../realtime/realtime_channel_options.dart';
import '../realtime/realtime_channels.dart';
import 'channel_rest_api.dart';
import 'connection_impl.dart';
import 'http/http_client.dart';
import 'realtime_channel_impl.dart';
import 'rest_annotations_impl.dart';
import '../realtime/timer_manager.dart';

/// Collection of realtime channels.
///
/// Spec: RTS1
class RealtimeChannelsImpl implements RealtimeChannels {
  /// Creates a RealtimeChannels collection.
  RealtimeChannelsImpl({
    required ConnectionImpl connection,
    required TimerManager timerManager,
    required ClientOptions options,
    required AblyHttpClient httpClient,
    required LocalDevice? Function() getDevice,
    required Logger logger,
    Future<LocalDevice?> Function()? loadDevice,
  })  : _connection = connection,
        _timerManager = timerManager,
        _options = options,
        _httpClient = httpClient,
        _getDevice = getDevice,
        _loadDevice = loadDevice,
        _logger = logger {
    // RTL3: Propagate connection state changes to channels
    _connectionSubscription = _connection.on().listen(_onConnectionStateChange);
  }

  final ConnectionImpl _connection;
  final TimerManager _timerManager;
  final ClientOptions _options;
  final AblyHttpClient _httpClient;
  final LocalDevice? Function() _getDevice;
  final Future<LocalDevice?> Function()? _loadDevice;
  final Logger _logger;
  final Map<String, RealtimeChannelImpl> _channels = {};
  late final StreamSubscription<ConnectionStateChange> _connectionSubscription;

  /// Gets or creates a channel with the given name.
  ///
  /// If the channel already exists, returns the existing instance.
  /// If the channel does not exist, creates a new one.
  ///
  /// If [options] are provided:
  /// - For a new channel, the options are set on the channel (RTS3b)
  /// - For an existing channel, the options are updated (RTS3c - soft-deprecated)
  ///   - If the options would require reattachment (params or modes changed)
  ///     and the channel is attached/attaching, an error is thrown (RTS3c1)
  ///
  /// Spec: RTS3a, RTS3b, RTS3c, RTS3c1
  @override
  RealtimeChannel get(String name, [RealtimeChannelOptions? options]) {
    final existingChannel = _channels[name];

    if (existingChannel != null) {
      // RTS3c: Update options on existing channel (soft-deprecated)
      if (options != null) {
        // RTS3c1: Error if options would trigger reattachment
        if (options.requiresReattachment &&
            (existingChannel.state == ChannelState.attached ||
                existingChannel.state == ChannelState.attaching)) {
          throw const AblyException(
            errorInfo: ErrorInfo(
              message: 'Cannot update channel options that require '
                  'reattachment via get(). Use channel.setOptions() instead.',
              code: 40000,
              statusCode: 400,
            ),
          );
        }
        // Update options without reattachment
        existingChannel.updateOptionsWithoutReattach(options);
      }
      return existingChannel;
    }

    // RTS3a, RTS3b: Create new channel with options
    final restApi = ChannelRestApi(channelName: name, httpClient: _httpClient);
    final restAnnotations = RestAnnotationsImpl(
      channelName: name,
      httpClient: _httpClient,
      options: _options,
      logger: _logger,
      restApi: restApi,
    );
    final channel = RealtimeChannelImpl(
      connection: _connection,
      timerManager: _timerManager,
      name: name,
      options: _options,
      restApi: restApi,
      restAnnotations: restAnnotations,
      httpClient: _httpClient,
      getDevice: _getDevice,
      loadDevice: _loadDevice,
      logger: _logger,
      channelOptions: options,
    );
    _channels[name] = channel;
    _logger.debug('Channel created', {'channel': name});
    return channel;
  }

  /// Gets or creates a channel with the given name (operator overload).
  ///
  /// Same as [get] without options.
  ///
  /// Spec: RTS3a
  @override
  RealtimeChannel operator [](String name) => get(name);

  /// Returns an existing channel or null without creating one.
  RealtimeChannelImpl? getIfExists(String name) => _channels[name];

  /// Creates a derived channel with a filter expression.
  ///
  /// Derived channels allow subscribing to a filtered subset of messages
  /// on an underlying channel using JMESPath expressions.
  ///
  /// The derived channel name is encoded as:
  /// `[filter=<base64-encoded-filter>]channelName`
  ///
  /// If the channel has params (e.g., rewind), they are included as:
  /// `[filter=<base64-encoded-filter>?rewind=1]channelName`
  ///
  /// Spec: RTS5, RTS5a, RTS5a1, RTS5a2
  @override
  RealtimeChannel getDerived(
    String name,
    DeriveOptions deriveOptions, [
    RealtimeChannelOptions? channelOptions,
  ]) {
    final derivedName = _buildDerivedChannelName(
      name,
      deriveOptions,
      channelOptions,
    );

    return get(derivedName, channelOptions);
  }

  /// Builds the derived channel name with encoded filter and params.
  ///
  /// Spec: RTS5a1, RTS5a2
  String _buildDerivedChannelName(
    String baseName,
    DeriveOptions deriveOptions,
    RealtimeChannelOptions? channelOptions,
  ) {
    // Base64 encode the filter expression (RTS5a1)
    final encodedFilter = base64.encode(utf8.encode(deriveOptions.filter));

    // Build the qualifier with optional params (RTS5a2)
    final buffer = StringBuffer('[filter=$encodedFilter');

    if (channelOptions?.params != null && channelOptions!.params!.isNotEmpty) {
      buffer.write('?');
      final params = channelOptions.params!.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');
      buffer.write(params);
    }

    buffer.write(']');
    buffer.write(baseName);

    return buffer.toString();
  }

  /// Checks if a channel with the given name exists.
  ///
  /// Returns true if the channel has been created (via get or []),
  /// false otherwise.
  ///
  /// Spec: RTS2
  @override
  bool exists(String name) {
    return _channels.containsKey(name);
  }

  /// Releases a channel, removing it from the collection.
  ///
  /// The channel will be detached if currently attached.
  ///
  /// Spec: RTS4, RTS4a
  @override
  Future<void> release(String name) async {
    final channel = _channels[name];
    if (channel != null) {
      _logger.debug('Channel released', {'channel': name});
      // Detach the channel if it's attached
      await channel.detach();
      _channels.remove(name);
    }
  }

  /// Returns an iterator over all channel names.
  ///
  /// Spec: RTS2
  @override
  Iterable<String> get names => _channels.keys;

  /// Returns a map of channel name to channelSerial for all attached channels.
  ///
  /// Used by createRecoveryKey() (RTN16g).
  Map<String, String> getChannelSerials() {
    final serials = <String, String>{};
    for (final entry in _channels.entries) {
      final serial = entry.value.properties.channelSerial;
      if (serial != null) {
        serials[entry.key] = serial;
      }
    }
    return serials;
  }

  /// Handles connection state changes (RTL3).
  void _onConnectionStateChange(ConnectionStateChange stateChange) {
    final current = stateChange.current;
    final errorReason = _connection.errorReason;

    switch (current) {
      case ConnectionState.failed:
        // RTL3a: ATTACHING/ATTACHED → FAILED
        for (final channel in _channels.values) {
          channel.handleConnectionFailed(errorReason);
        }
      case ConnectionState.closed:
        // RTL3b: ATTACHING/ATTACHED → DETACHED
        for (final channel in _channels.values) {
          channel.handleConnectionClosed();
        }
      case ConnectionState.suspended:
        // RTL3c: ATTACHING/ATTACHED → SUSPENDED
        for (final channel in _channels.values) {
          channel.handleConnectionSuspended(errorReason);
        }
      case ConnectionState.connected:
        // RTL3d: ATTACHING/ATTACHED/SUSPENDED → re-attach
        for (final channel in _channels.values) {
          channel.handleConnectionConnected();
        }
      case ConnectionState.disconnected:
        // RTL3e: No effect on channels
        break;
      default:
        break;
    }
  }

  /// Disposes all channels in the collection.
  void dispose() {
    _connectionSubscription.cancel();
    for (final channel in _channels.values) {
      channel.dispose();
    }
    _channels.clear();
  }
}

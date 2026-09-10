import 'dart:convert';

import 'package:meta/meta.dart';

import '../auth/auth.dart';
import '../push/push.dart';
import '../realtime/connection.dart';
import '../realtime/protocol_message.dart';
import '../realtime/realtime_client.dart';
import '../realtime/realtime_channels.dart';
import '../realtime/websocket_client.dart';
import 'base_client_impl.dart';
import 'connection_impl.dart';
import 'push_admin_impl.dart';
import 'realtime_auth.dart';
import 'realtime_channels_impl.dart';
import '../realtime/timer_manager.dart';

/// Implementation of the Ably Realtime client.
///
/// Provides access to realtime messaging, presence, and connection management.
///
/// Spec: RTC1
class RealtimeClientImpl extends BaseClientImpl implements RealtimeClient {
  /// Creates a Realtime client implementation.
  RealtimeClientImpl({
    required super.options,
    super.httpClient,
    WebSocketClient? webSocketClient,
    TimerManager? timerManager,
  })  : _webSocketClient = webSocketClient,
        _timerManager = timerManager {
    _initialize();
  }

  @override
  @protected
  String get clientType => 'realtime';

  final WebSocketClient? _webSocketClient;
  final TimerManager? _timerManager;
  late final TimerManager timerManager;
  late final ConnectionImpl _connection;
  late final RealtimeChannelsImpl _channels;
  late final RealtimeAuth _realtimeAuth;
  late final PushImpl _push;

  void _initialize() {
    timerManager = _timerManager ?? TimerManager();

    // Initialize connection
    _connection = ConnectionImpl(
      options: options,
      auth: authImpl,
      timerManager: timerManager,
      webSocketClient: _webSocketClient,
      httpClient: rawHttpClient,
      logger: logger,
    );

    // Initialize channels
    _channels = RealtimeChannelsImpl(
      connection: _connection,
      timerManager: timerManager,
      options: options,
      httpClient: ablyHttpClient,
      getDevice: () => device,
      loadDevice: () async =>
          options.pushPlatform != null ? await getDevice() : device,
      logger: logger,
    );

    // Initialize push
    _push = PushImpl(
      httpClient: ablyHttpClient,
      logger: logger,
      options: options,
      getActivation: () => pushActivation,
      getDevice: () => device,
    );

    // Wire up channel message dispatch
    _connection.onChannelMessage = _dispatchChannelMessage;

    // RTN16g: Wire up channel serials callback for recovery key generation
    _connection.getChannelSerials = _channels.getChannelSerials;

    // RTN16j: Pre-instantiate channels from recovery key with channelSerials
    if (options.recover != null) {
      _initializeFromRecoveryKey(options.recover!);
    }

    // RTC8: Wrap auth with realtime-specific authorize behavior
    _realtimeAuth = RealtimeAuth(
      authImpl: authImpl,
      connection: _connection,
    );

    // Auto-connect if enabled (RTC1c)
    if (options.autoConnect) {
      Future.microtask(() => _connection.connect());
    }
  }

  @override
  Auth get auth => _realtimeAuth;

  @override
  Push get push => _push;

  @override
  Connection get connection => _connection;

  @override
  RealtimeChannels get channels => _channels;

  @override
  Future<void> connect() async {
    await _connection.connect();
  }

  @override
  Future<void> close() async {
    await _connection.close();
    timerManager.dispose();
  }

  /// Initializes channels and msgSerial from a recovery key.
  ///
  /// RTN16f: Initialize msgSerial from recovery key.
  /// RTN16j: Pre-instantiate channels with channelSerials.
  /// RTN16f1: Log and ignore malformed recovery keys.
  void _initializeFromRecoveryKey(String recoveryKey) {
    try {
      final parsed = jsonDecode(recoveryKey) as Map<String, dynamic>;
      final msgSerial = parsed['msgSerial'] as int?;
      final channelSerials = (parsed['channelSerials'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String));

      // RTN16f: Initialize msgSerial
      if (msgSerial != null) {
        _connection.initializeFromRecoveryKey(recoveryKey);
      }

      // RTN16j: Pre-instantiate channels with channelSerials
      if (channelSerials != null) {
        for (final entry in channelSerials.entries) {
          final channel = _channels.get(entry.key);
          channel.properties.channelSerial = entry.value;
        }
      }
    } catch (e) {
      // RTN16f1: Malformed recovery key - log and continue
      logger.error('Malformed recovery key, ignoring', {
        'error': e.toString(),
      });
    }
  }

  void _dispatchChannelMessage(ProtocolMessage message) {
    if (message.channel == null) return;
    final channel = _channels.getIfExists(message.channel!);
    channel?.handleProtocolMessage(message);
  }
}

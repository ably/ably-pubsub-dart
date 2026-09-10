import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../auth/client_options.dart';
import '../channels/channel_details.dart';
import '../channels/realtime_history_params.dart';
import '../channels/rest_annotations.dart';
import '../channels/rest_history_params.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../message/message.dart';
import '../message/message_action.dart';
import '../message/message_extras.dart';
import '../message/message_filter.dart';
import '../message/message_operation.dart';
import '../message/update_delete_result.dart';
import '../pagination/paginated_result.dart';
import '../plugin/vcdiff_decoder.dart';
import '../push/local_device.dart';
import '../push/push_channel.dart';
import '../realtime/channel_event.dart';
import '../realtime/channel_mode.dart';
import '../realtime/channel_state.dart';
import '../realtime/channel_state_change.dart';
import '../realtime/connection_event.dart';
import '../realtime/connection_state.dart';
import '../realtime/protocol_message.dart';
import '../realtime/publish_result.dart';
import '../realtime/realtime_annotations.dart';
import '../realtime/realtime_channel.dart';
import '../realtime/realtime_channel_options.dart';
import '../realtime/realtime_presence.dart';
import 'channel_rest_api.dart';
import 'connection_impl.dart';
import 'http/http_client.dart';
import 'push_channel_impl.dart';
import 'realtime_annotations_impl.dart';
import 'realtime_presence_impl.dart';
import '../realtime/timer_manager.dart';

/// A realtime channel for pub/sub messaging.
///
/// Spec: RTL
class RealtimeChannelImpl implements RealtimeChannel {
  /// Creates a RealtimeChannelImpl instance.
  RealtimeChannelImpl({
    required ConnectionImpl connection,
    required TimerManager timerManager,
    required String name,
    required ClientOptions options,
    required ChannelRestApi restApi,
    required RestAnnotations restAnnotations,
    required AblyHttpClient httpClient,
    required LocalDevice? Function() getDevice,
    required Logger logger,
    Future<LocalDevice?> Function()? loadDevice,
    RealtimeChannelOptions? channelOptions,
  })  : _connection = connection,
        _timerManager = timerManager,
        _name = name,
        _clientOptions = options,
        _restApi = restApi,
        _logger = logger,
        _options = channelOptions ?? const RealtimeChannelOptions(),
        _state = ChannelState.initialized {
    _annotations = RealtimeAnnotationsImpl(
      channelName: name,
      connection: connection,
      restAnnotations: restAnnotations,
      implicitAttach: attach,
      getChannelState: () => _state,
      getChannelModes: () => _modes,
      getAttachOnSubscribe: () => _options.attachOnSubscribe,
      useBinaryProtocol: _clientOptions.useBinaryProtocol,
      logger: logger,
    );
    _push = PushChannelImpl(
      channelName: name,
      httpClient: httpClient,
      getDevice: getDevice,
      loadDevice: loadDevice,
    );
  }

  final ConnectionImpl _connection;
  final TimerManager _timerManager;
  final ClientOptions _clientOptions;
  final ChannelRestApi _restApi;
  final Logger _logger;
  final String _name;
  RealtimeChannelOptions _options;

  ChannelState _state;
  ErrorInfo? _errorReason;

  /// Channel properties (RTL15).
  @override
  final ChannelProperties properties = ChannelProperties();

  /// Whether this channel has ever been attached (for ATTACH_RESUME flag, RTL4j).
  bool _hasBeenAttached = false;

  /// Delta decoding state — base payload for vcdiff delta reconstruction.
  ///
  /// Stores the decoded payload (after base64 but before json/utf-8) of the
  /// last successfully decoded message. Can be `String` or `Uint8List`.
  ///
  /// Spec: RTL19, RTL19a, RTL19b, RTL19c
  Object? _basePayload;

  /// The message ID of the last successfully decoded message.
  ///
  /// Used to verify delta continuity: the first message's `extras.delta.from`
  /// must match this value.
  ///
  /// Spec: RTL20
  String? _lastPayloadMessageId;

  /// The channelSerial from the ProtocolMessage containing the last
  /// successfully decoded message. Used as the channelSerial in the
  /// ATTACH message during decode failure recovery.
  ///
  /// Spec: RTL18c
  String? _lastPayloadProtocolMessageChannelSerial;

  /// Whether a decode failure recovery is currently in progress.
  ///
  /// Prevents multiple concurrent recovery attempts.
  ///
  /// Spec: RTL18
  bool _decodeFailureRecoveryInProgress = false;

  /// Clears the stored last payload message ID, forcing the next delta
  /// to fail the RTL20 base reference check.
  ///
  /// This is only for testing — it simulates a message gap.
  @visibleForTesting
  void clearLastPayloadMessageId() {
    _lastPayloadMessageId = null;
  }

  /// The annotations object for this channel (RTL26).
  late final RealtimeAnnotationsImpl _annotations;

  /// The presence object for this channel (RTL9).
  late final RealtimePresenceImpl _presence = RealtimePresenceImpl(
    channelName: _name,
    connection: _connection,
    getClientId: () => _clientOptions.clientId,
    implicitAttach: attach,
    getChannelState: () => _state,
    restHistory: ([params]) => _restApi.presenceHistory(params),
    logger: _logger,
  );

  /// Message subscribers (RTL7, RTL8).
  final List<_Subscription> _subscribers = [];

  /// Pending attach operation.
  Completer<void>? _attachCompleter;

  /// Pending detach operation.
  Completer<void>? _detachCompleter;

  final _stateChangeController =
      StreamController<ChannelStateChange>.broadcast();

  /// The name of this channel.
  ///
  /// Spec: RTL23
  @override
  String get name => _name;

  /// The current channel options.
  @override
  RealtimeChannelOptions get options => _options;

  /// The current channel state.
  ///
  /// Spec: RTL2
  @override
  ChannelState get state => _state;

  /// The channel modes as returned by the server on attach.
  ///
  /// This is populated after a successful attach and reflects
  /// the actual modes granted by the server.
  ///
  /// Spec: RTL4m
  @override
  List<ChannelMode>? get modes => _modes;
  List<ChannelMode>? _modes;

  /// The presence object for this channel.
  ///
  /// Spec: RTL9, RTL9a
  @override
  RealtimePresence get presence => _presence;

  /// The annotations object for this channel.
  ///
  /// Spec: RTL26
  @override
  RealtimeAnnotations get annotations => _annotations;

  /// The push interface for this channel.
  ///
  /// Spec: RSH7
  late final PushChannelImpl _push;

  @override
  PushChannel get push => _push;

  /// Error information for the current state (if failed/suspended).
  ///
  /// Spec: RTL24
  @override
  ErrorInfo? get errorReason => _errorReason;

  /// Calls the listener immediately with null if already in the target state,
  /// otherwise registers a one-time listener for that state.
  ///
  /// Spec: RTL25
  @override
  void whenState(
    ChannelState targetState,
    void Function(ChannelStateChange?) listener,
  ) {
    _logger.info('whenState() called', {
      'channel': _name,
      'targetState': targetState.name,
    });
    if (_state == targetState) {
      // RTL25a: Already in target state - call immediately with null
      listener(null);
    } else {
      // RTL25b: Wait for state transition - use once
      final subscription =
          on(ChannelEventExtension.fromState(targetState)).listen(null);
      subscription.onData((change) {
        listener(change);
        subscription.cancel();
      });
    }
  }

  /// Listens to channel state changes.
  ///
  /// If [event] is provided, only emits changes matching that event.
  /// If [event] is null, emits all state changes.
  ///
  /// Spec: RTL2
  @override
  Stream<ChannelStateChange> on([ChannelEvent? event]) {
    if (event == null) {
      return _stateChangeController.stream;
    }

    return _stateChangeController.stream
        .where((change) => change.event == event);
  }

  /// Subscribes to messages on this channel.
  ///
  /// If [name] is provided, the listener only receives messages whose
  /// `name` field matches. If [name] is null, the listener receives all
  /// messages.
  ///
  /// If `attachOnSubscribe` is true (the default) and the channel is in
  /// INITIALIZED, DETACHED, or DETACHING state, an implicit attach is
  /// triggered. The listener is always registered regardless of the
  /// attach result.
  ///
  /// Spec: RTL7, RTL7a, RTL7b, RTL7g, RTL7h
  @override
  void subscribe(void Function(Message) listener, {String? name}) {
    _logger.info('subscribe() called', {'channel': _name});
    // Register the listener
    _subscribers.add(_Subscription(listener: listener, name: name));

    // RTL7g: Implicit attach when attachOnSubscribe is true
    if (_options.attachOnSubscribe) {
      if (_state == ChannelState.initialized ||
          _state == ChannelState.detached ||
          _state == ChannelState.detaching) {
        // Fire-and-forget — RTL7g says listener is registered regardless
        // of attach result.
        unawaited(attach().catchError((_) {}));
      }
    }
  }

  /// Subscribes to messages matching a [MessageFilter].
  ///
  /// Only messages matching all criteria in the filter are delivered to the
  /// listener (AND semantics). Uses the same implicit-attach and
  /// attachOnSubscribe behaviour as [subscribe].
  ///
  /// Spec: RTL22, RTL22a, RTL22b, RTL22c, RTL22d
  @override
  void subscribeFilter(
    MessageFilter filter,
    void Function(Message) listener,
  ) {
    _logger.info('subscribeFilter() called', {'channel': _name});
    _subscribers.add(
      _Subscription(listener: listener, filter: filter),
    );

    if (_options.attachOnSubscribe) {
      if (_state == ChannelState.initialized ||
          _state == ChannelState.detached ||
          _state == ChannelState.detaching) {
        unawaited(attach().catchError((_) {}));
      }
    }
  }

  /// Unsubscribes from messages on this channel.
  ///
  /// If both [listener] and [name] are null, all subscriptions are removed.
  /// If only [listener] is provided, that listener is removed from all-message
  /// subscriptions. If both [listener] and [name] are provided, that specific
  /// name subscription for that listener is removed.
  ///
  /// Spec: RTL8, RTL8a, RTL8b, RTL8c
  @override
  void unsubscribe({void Function(Message)? listener, String? name}) {
    _logger.info('unsubscribe() called', {'channel': _name});
    if (listener == null && name == null) {
      // RTL8c: Remove all subscriptions
      _subscribers.clear();
      return;
    }

    _subscribers.removeWhere((sub) {
      if (name != null) {
        // RTL8b: Remove by listener + name
        return sub.listener == listener && sub.name == name;
      }
      // RTL8a: Remove by listener (all-message subscription only)
      return sub.listener == listener && sub.name == null;
    });
  }

  /// Publishes a message on this channel.
  ///
  /// Either provide [name] and/or [data], a single [message], or a list of
  /// [messages]. Only one of these forms may be used at a time.
  ///
  /// Returns a [PublishResult] containing the message serials from the ACK
  /// response (RTL6j).
  ///
  /// RTL6c state conditions determine whether the message is sent immediately,
  /// queued, or rejected:
  /// - RTL6c1: If connection is CONNECTED and channel is neither SUSPENDED
  ///   nor FAILED, messages are sent immediately.
  /// - RTL6c2: If connection is INITIALIZED, CONNECTING, or DISCONNECTED,
  ///   and channel is neither SUSPENDED nor FAILED, and queueMessages is true,
  ///   messages are queued.
  /// - RTL6c4: Otherwise an error is raised.
  /// - RTL6c5: Publish does NOT trigger an implicit attach.
  ///
  /// Spec: RTL6, RTL6j
  @override
  Future<PublishResult> publish({
    String? name,
    Object? data,
    Message? message,
    List<Message>? messages,
  }) async {
    _logger.info('publish() called', {'channel': _name});
    // RTL6c4: Fail if channel is SUSPENDED or FAILED
    if (_state == ChannelState.suspended || _state == ChannelState.failed) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish when channel is $_state',
          statusCode: 400,
        ),
      );
    }

    // Build the list of Message objects to publish
    final List<Message> messageList;
    if (messages != null) {
      // RTL6i2: Array of messages
      messageList = messages;
    } else if (message != null) {
      // RTL6i1: Single Message object
      messageList = [message];
    } else {
      // RTL6i1/RTL6i3: name and/or data (either or both may be null)
      messageList = [Message(name: name, data: data)];
    }

    // Build protocol message with Message.toMap() for proper encoding (RTL6i3)
    final protocolMessage = ProtocolMessage(
      action: ProtocolAction.message,
      channel: _name,
      messages: messageList
          .map(
            (m) => m.toMap(
              useBinaryProtocol: _clientOptions.useBinaryProtocol,
            ),
          )
          .toList(),
    );

    final connState = _connection.state;

    // RTL6c1: Send immediately if CONNECTED
    if (connState == ConnectionState.connected) {
      return _connection.sendPublishMessage(protocolMessage);
    }

    // RTL6c2: Queue if INITIALIZED, CONNECTING, or DISCONNECTED
    // (and queueMessages is true)
    if (connState == ConnectionState.initialized ||
        connState == ConnectionState.connecting ||
        connState == ConnectionState.disconnected) {
      if (_clientOptions.queueMessages) {
        return _connection.queueMessage(protocolMessage);
      }
      // queueMessages is false — fail
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish when connection is $connState and '
              'queueMessages is false',
          statusCode: 400,
        ),
      );
    }

    // RTL6c4: All other connection states (SUSPENDED, CLOSED, CLOSING, FAILED)
    throw AblyException(
      errorInfo: ErrorInfo(
        code: 90001,
        message: 'Cannot publish when connection is $connState',
        statusCode: 400,
      ),
    );
  }

  /// Retrieves message history for this channel via the REST API.
  ///
  /// Accepts [RestHistoryParams] or [RealtimeHistoryParams]. If
  /// [RealtimeHistoryParams.untilAttach] is true, the query is restricted
  /// to messages prior to the channel's attach point using `fromSerial`.
  ///
  /// Spec: RTL10, RTL10a, RTL10b, RTL10c
  @override
  Future<PaginatedResult<Message>> history([RestHistoryParams? params]) async {
    _logger.info('history() called', {'channel': _name});
    Map<String, String>? extraQueryParams;

    if (params is RealtimeHistoryParams && params.untilAttach) {
      // RTL10b: untilAttach requires an attached channel with attachSerial
      final attachSerial = properties.attachSerial;
      if (attachSerial == null) {
        throw const AblyException(
          errorInfo: ErrorInfo(
            code: 91000,
            message: 'Cannot use untilAttach: channel has no attachSerial',
            statusCode: 400,
          ),
        );
      }
      extraQueryParams = {'fromSerial': attachSerial};
    }

    return _restApi.history(params, extraQueryParams);
  }

  /// Retrieves a single message by serial via the REST API.
  ///
  /// Spec: RTL28 (same as RSL11)
  @override
  Future<Message> getMessage(String serial) {
    _logger.info('getMessage() called', {
      'channel': _name,
      'serial': serial,
    });
    _validateSerial(serial);
    return _restApi.getMessage(serial);
  }

  /// Retrieves all historical versions of a message via the REST API.
  ///
  /// Spec: RTL31 (same as RSL14)
  @override
  Future<PaginatedResult<Message>> getMessageVersions(
    String serial, {
    Map<String, String>? params,
  }) {
    _logger.info('getMessageVersions() called', {
      'channel': _name,
      'serial': serial,
    });
    _validateSerial(serial);
    return _restApi.getMessageVersions(serial, params);
  }

  /// Updates a previously published message via the realtime connection.
  ///
  /// Sends a MESSAGE ProtocolMessage with MESSAGE_UPDATE action.
  ///
  /// Spec: RTL32
  @override
  Future<UpdateDeleteResult> updateMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageUpdate,
      operation: operation,
      params: params,
    );
  }

  /// Deletes a previously published message via the realtime connection.
  ///
  /// Sends a MESSAGE ProtocolMessage with MESSAGE_DELETE action.
  ///
  /// Spec: RTL32
  @override
  Future<UpdateDeleteResult> deleteMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageDelete,
      operation: operation,
      params: params,
    );
  }

  /// Appends to a previously published message via the realtime connection.
  ///
  /// Sends a MESSAGE ProtocolMessage with MESSAGE_APPEND action.
  ///
  /// Spec: RTL32
  @override
  Future<UpdateDeleteResult> appendMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageAppend,
      operation: operation,
      params: params,
    );
  }

  /// Retrieves the channel's current status and occupancy via the REST API.
  ///
  /// Spec: RSL8
  @override
  Future<ChannelDetails> status() {
    _logger.info('status() called', {'channel': _name});
    return _restApi.status();
  }

  /// Attaches to this channel.
  ///
  /// If already attached, this is a no-op.
  ///
  /// Spec: RTL4
  @override
  Future<void> attach() async {
    _logger.info('attach() called', {'channel': _name});
    switch (_state) {
      case ChannelState.attached:
        // Already attached - no-op (RTL4a)
        return;

      case ChannelState.attaching:
        // Already attaching - wait for completion (RTL4h)
        final result = await on().firstWhere(
          (change) =>
              change.current == ChannelState.attached ||
              change.current == ChannelState.suspended ||
              change.current == ChannelState.failed,
        );
        if (result.current != ChannelState.attached) {
          throw AblyException(
            errorInfo: result.reason ??
                const ErrorInfo(code: 90007, message: 'Channel attach failed'),
          );
        }
        return;

      case ChannelState.failed:
        // Clear error and proceed (RTL4g)
        _errorReason = null;
        break;

      case ChannelState.detaching:
        // Wait for detach to complete, then attach (RTL4h)
        await on().firstWhere(
          (change) =>
              change.current == ChannelState.detached ||
              change.current == ChannelState.failed,
        );
        break;

      default:
        break;
    }

    // Check connection state (RTL4b)
    final connState = _connection.state;
    if (connState == ConnectionState.closed ||
        connState == ConnectionState.closing ||
        connState == ConnectionState.failed ||
        connState == ConnectionState.suspended) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot attach when connection is $connState',
          statusCode: 400,
        ),
      );
    }

    // Transition to attaching
    _transitionTo(ChannelState.attaching);

    // Set _attachCompleter before awaiting CONNECTED so that
    // handleConnectionConnected (RTL3d) can see this channel is
    // already managed by an explicit attach() call and skip it.
    final completer = Completer<void>();
    _attachCompleter = completer;

    // If connection is not yet connected, queue and wait (RTL4i)
    if (_connection.state != ConnectionState.connected) {
      // RTL4i: Implicitly initiate connection if not yet started
      if (_connection.state == ConnectionState.initialized) {
        unawaited(_connection.connect());
      }
      await _connection.on(ConnectionEvent.connected).first;
    }

    _sendAttachMessage();
    _startAttachTimeout();

    await completer.future;
  }

  /// Detaches from this channel.
  ///
  /// If already detached, this is a no-op.
  ///
  /// Spec: RTL5
  @override
  Future<void> detach() async {
    _logger.info('detach() called', {'channel': _name});
    switch (_state) {
      case ChannelState.initialized:
      case ChannelState.detached:
        // Already detached - no-op (RTL5a)
        return;

      case ChannelState.detaching:
        // Already detaching - wait for completion (RTL5i)
        await on().firstWhere(
          (change) =>
              change.current == ChannelState.detached ||
              change.current == ChannelState.attached ||
              change.current == ChannelState.failed,
        );
        return;

      case ChannelState.failed:
        // Cannot detach from failed state (RTL5b)
        throw const AblyException(
          errorInfo: ErrorInfo(
            code: 90001,
            message: 'Cannot detach from failed state',
            statusCode: 400,
          ),
        );

      case ChannelState.suspended:
        // Transition directly to detached (RTL5j)
        _timerManager.cancelAll(owner: this);
        _transitionTo(ChannelState.detached);
        return;

      case ChannelState.attaching:
        // If connection isn't connected, skip waiting — fall through to
        // the RTL5l check which transitions directly to detached.
        if (_connection.state != ConnectionState.connected) {
          break;
        }
        // Wait for attach to complete, then detach (RTL5i)
        final attachResult = await on().firstWhere(
          (change) =>
              change.current == ChannelState.attached ||
              change.current == ChannelState.suspended ||
              change.current == ChannelState.failed ||
              change.current == ChannelState.detached,
        );
        // If attach failed, the channel may already be in a state
        // where detach is a no-op
        if (attachResult.current == ChannelState.detached ||
            _state == ChannelState.initialized) {
          return;
        }
        if (attachResult.current == ChannelState.failed) {
          throw const AblyException(
            errorInfo: ErrorInfo(
              code: 90001,
              message: 'Cannot detach from failed state',
              statusCode: 400,
            ),
          );
        }
        break;

      default:
        break;
    }

    // If connection not connected, transition directly (RTL5l)
    if (_connection.state != ConnectionState.connected) {
      _transitionTo(ChannelState.detached);
      return;
    }

    // Transition to detaching
    _transitionTo(ChannelState.detaching);

    final completer = Completer<void>();
    _detachCompleter = completer;
    _sendDetachMessage();
    _startDetachTimeout();

    await completer.future;
  }

  /// Handles connection entering FAILED state (RTL3a).
  ///
  /// Channels in ATTACHING or ATTACHED transition to FAILED.
  void handleConnectionFailed(ErrorInfo? error) {
    if (_state == ChannelState.attaching || _state == ChannelState.attached) {
      _timerManager.cancelAll(owner: this);
      _transitionTo(ChannelState.failed, error: error);
      _failPendingOperations(
        error ?? const ErrorInfo(code: 80000, message: 'Connection failed'),
      );
    }
  }

  /// Handles connection entering CLOSED state (RTL3b).
  ///
  /// Channels in ATTACHING or ATTACHED transition to DETACHED.
  void handleConnectionClosed() {
    if (_state == ChannelState.attaching || _state == ChannelState.attached) {
      _timerManager.cancelAll(owner: this);
      _transitionTo(ChannelState.detached);
      _failPendingOperations(
        const ErrorInfo(code: 80017, message: 'Connection closed'),
      );
    }
  }

  /// Handles connection entering SUSPENDED state (RTL3c).
  ///
  /// Channels in ATTACHING or ATTACHED transition to SUSPENDED.
  void handleConnectionSuspended(ErrorInfo? error) {
    if (_state == ChannelState.attaching || _state == ChannelState.attached) {
      _timerManager.cancelAll(owner: this);
      _transitionTo(ChannelState.suspended, error: error);
      _failPendingOperations(
        error ?? const ErrorInfo(code: 80002, message: 'Connection suspended'),
      );
    }
  }

  /// Handles connection entering CONNECTED state (RTL3d).
  ///
  /// Channels in ATTACHING, ATTACHED, or SUSPENDED re-attach via RTL4c.
  /// Channels in ATTACHING with a pending attach completer are already
  /// being managed by an explicit attach() call (RTL4i) and should not
  /// be re-attached here.
  void handleConnectionConnected() {
    if (_state == ChannelState.attached || _state == ChannelState.suspended) {
      _timerManager.cancelAll(owner: this);
      _transitionTo(ChannelState.attaching);
      _attachCompleter = Completer<void>();
      _attachCompleter!.future.ignore();
      _sendAttachMessage();
      _startAttachTimeout();
    } else if (_state == ChannelState.attaching) {
      // RTN19b: Resend ATTACH on new transport for channels still ATTACHING.
      // Cancel any existing attach timeout from the old transport.
      _timerManager.cancelAll(owner: this);
      _sendAttachMessage();
      _startAttachTimeout();
    } else if (_state == ChannelState.detaching) {
      // RTN19b: Resend DETACH for channels still in DETACHING state
      _sendDetachMessage();
      _startDetachTimeout();
    }
  }

  /// Fails pending attach/detach operations with an error.
  void _failPendingOperations(ErrorInfo error) {
    final exception = AblyException(errorInfo: error);
    if (_attachCompleter != null && !_attachCompleter!.isCompleted) {
      _attachCompleter!.completeError(exception);
    }
    _attachCompleter = null;
    if (_detachCompleter != null && !_detachCompleter!.isCompleted) {
      _detachCompleter!.completeError(exception);
    }
    _detachCompleter = null;
  }

  /// Handles an incoming protocol message dispatched from the connection.
  void handleProtocolMessage(ProtocolMessage message) {
    // RTL15b: Update channelSerial from MESSAGE/PRESENCE/ANNOTATION actions
    if (message.action == ProtocolAction.message ||
        message.action == ProtocolAction.presence ||
        message.action == ProtocolAction.annotation) {
      if (message.channelSerial != null) {
        properties.channelSerial = message.channelSerial;
      }
    }

    switch (message.action) {
      case ProtocolAction.attached:
        _handleAttached(message);
      case ProtocolAction.detached:
        _handleDetached(message);
      case ProtocolAction.error:
        _handleError(message);
      case ProtocolAction.message:
        _handleMessage(message);
      case ProtocolAction.presence:
        _presence.handlePresenceMessage(message);
      case ProtocolAction.sync:
        _presence.handleSyncMessage(message);
      case ProtocolAction.annotation:
        _annotations.handleAnnotationMessage(message);
      default:
        break;
    }
  }

  /// Handles ATTACHED protocol message.
  void _handleAttached(ProtocolMessage message) {
    _timerManager.cancel(owner: this, name: 'attachTimeout');
    _timerManager.cancel(owner: this, name: 'channelRetry');

    // RTL15a: Update attachSerial from ATTACHED response
    properties.attachSerial = message.channelSerial;
    // RTL15b: Update channelSerial from ATTACHED action
    if (message.channelSerial != null) {
      properties.channelSerial = message.channelSerial;
    }

    // Decode modes from flags (RTL4m)
    if (message.flags != null) {
      _modes = decodeModeFlags(message.flags!);
    }

    // Determine resumed/hasBacklog from flags (TR3c, TR3b)
    final resumed = (message.flags ?? 0) & flagResumed != 0;
    final hasBacklog = (message.flags ?? 0) & flagHasBacklog != 0 ? true : null;

    final wasAlreadyAttached = _state == ChannelState.attached;

    if (wasAlreadyAttached) {
      // Handle presence before emitting update
      final shouldReenter = _presence.handleAttached(
        message.flags,
        wasAlreadyAttached: true,
      );
      if (shouldReenter) {
        _presence.performReentry(
          emitUpdate: _stateChangeController.add,
        );
      }
      // RTL12: Only emit UPDATE if resumed flag is false (loss of continuity)
      if (!resumed) {
        _emitUpdate(
          reason: message.error,
          hasBacklog: hasBacklog,
        );
      }
      return;
    }

    if (_state == ChannelState.detached) {
      // Unexpected ATTACHED while detached - send DETACH (RTL5k)
      // Do NOT set _hasBeenAttached — we never entered attached state
      _sendDetachMessage();
      return;
    }

    if (_state == ChannelState.detaching) {
      // ATTACHED received while detaching - send another DETACH (RTL5k)
      _sendDetachMessage();
      return;
    }

    // RTL18c: Clear decode failure recovery flag on successful attach
    _decodeFailureRecoveryInProgress = false;

    _hasBeenAttached = true;
    _transitionTo(
      ChannelState.attached,
      resumed: resumed,
      hasBacklog: hasBacklog,
    );

    // RTAN4e: Check annotation subscribe mode on attach
    _annotations.checkModeOnAttached();

    // Handle presence sync and re-entry
    final shouldReenter = _presence.handleAttached(
      message.flags,
      wasAlreadyAttached: false,
    );

    // Flush queued presence operations (RTP5b)
    _presence.flushPendingQueue();

    if (shouldReenter) {
      _presence.performReentry(
        emitUpdate: _stateChangeController.add,
      );
    }

    // Complete pending attach
    if (_attachCompleter != null && !_attachCompleter!.isCompleted) {
      _attachCompleter!.complete();
    }
    _attachCompleter = null;
  }

  /// Handles DETACHED protocol message.
  ///
  /// If the channel is DETACHING (explicit detach), this completes the normal
  /// detach flow (RTL5). Otherwise it is a server-initiated DETACHED and
  /// RTL13 applies.
  void _handleDetached(ProtocolMessage message) {
    if (_state == ChannelState.detaching) {
      // Normal detach flow (RTL5)
      _timerManager.cancel(owner: this, name: 'detachTimeout');
      _transitionTo(ChannelState.detached);

      if (_detachCompleter != null && !_detachCompleter!.isCompleted) {
        _detachCompleter!.complete();
      }
      _detachCompleter = null;
      return;
    }

    // Server-initiated DETACHED (RTL13)
    final error = message.error;
    _logger.warn('Server-initiated DETACHED', {
      'channel': _name,
      if (error != null) 'reason': error.message,
    });

    if (_state == ChannelState.attached || _state == ChannelState.suspended) {
      // RTL13a: Immediately attempt to reattach
      _timerManager.cancelAll(owner: this);
      _transitionTo(ChannelState.attaching, error: error);
      _attachCompleter = Completer<void>();
      _attachCompleter!.future.ignore();
      _sendAttachMessage();
      _startAttachTimeout();
    } else if (_state == ChannelState.attaching) {
      // RTL13b: Already ATTACHING — go directly to SUSPENDED with retry
      _timerManager.cancelAll(owner: this);
      _failPendingOperations(
        error ?? const ErrorInfo(code: 90007, message: 'Server detached'),
      );
      _transitionTo(ChannelState.suspended, error: error);
      _scheduleChannelRetry();
    }
  }

  /// Handles channel-scoped ERROR protocol message.
  void _handleError(ProtocolMessage message) {
    _timerManager.cancel(owner: this, name: 'attachTimeout');
    _timerManager.cancel(owner: this, name: 'detachTimeout');
    _timerManager.cancel(owner: this, name: 'channelRetry');

    final error =
        message.error ?? const ErrorInfo(code: 50000, message: 'Channel error');

    _transitionTo(ChannelState.failed, error: message.error);

    // Complete pending operations with error so attach()/detach() callers
    // receive the exception.
    final exception = AblyException(errorInfo: error);
    if (_attachCompleter != null && !_attachCompleter!.isCompleted) {
      _attachCompleter!.completeError(exception);
    }
    _attachCompleter = null;
    if (_detachCompleter != null && !_detachCompleter!.isCompleted) {
      _detachCompleter!.completeError(exception);
    }
    _detachCompleter = null;
  }

  /// Handles incoming MESSAGE protocol message.
  ///
  /// Decodes messages with vcdiff delta support (RTL18-RTL21), delivering
  /// individual messages to subscribers. Filters by name for name-specific
  /// subscriptions. Only delivers when the channel is ATTACHED (RTL17).
  /// Filters out self-echoed messages when echoMessages is false (RTL7f).
  void _handleMessage(ProtocolMessage protocolMessage) {
    // RTL17: Only deliver when ATTACHED
    if (_state != ChannelState.attached) {
      return;
    }

    // RTL7f: Filter out messages from this connection when echoMessages is false
    if (!_clientOptions.echoMessages &&
        protocolMessage.connectionId == _connection.id) {
      return;
    }

    final rawMessages = protocolMessage.messages;
    if (rawMessages == null) return;

    // Populate fields from parent ProtocolMessage (mirrors ably-js
    // populateFieldsFromParent). Computes message IDs as
    // `protocolMessageId:index` when the message doesn't have its own ID.
    final maps = <Map<String, dynamic>>[];
    for (var i = 0; i < rawMessages.length; i++) {
      final map = rawMessages[i] is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawMessages[i] as Map<String, dynamic>)
          : (rawMessages[i] as Message)
              .toMap(useBinaryProtocol: _clientOptions.useBinaryProtocol);
      if (map['connectionId'] == null && protocolMessage.connectionId != null) {
        map['connectionId'] = protocolMessage.connectionId;
      }
      if (map['timestamp'] == null && protocolMessage.timestamp != null) {
        map['timestamp'] = protocolMessage.timestamp;
      }
      if (protocolMessage.id != null && map['id'] == null) {
        map['id'] = '${protocolMessage.id}:$i';
      }
      maps.add(map);
    }

    // RTL20: Check delta continuity — first message's delta.from must match
    // the last successfully decoded message ID.
    final firstExtras = maps[0]['extras'] as Map<String, dynamic>?;
    final firstDelta = firstExtras?['delta'] as Map<String, dynamic>?;
    if (firstDelta != null && firstDelta['from'] != _lastPayloadMessageId) {
      _startDecodeFailureRecovery(
        const ErrorInfo(
          code: 40018,
          statusCode: 400,
          message: 'Delta message decode failure - previous message not '
              'available',
        ),
      );
      return; // RTL18b: discard
    }

    // RTL21: Decode messages in ascending index order
    final messages = <Message>[];
    for (final map in maps) {
      final rawData = map['data'];
      final encoding = map['encoding'] as String?;
      final extras = map['extras'] as Map<String, dynamic>?;
      final delta = extras?['delta'] as Map<String, dynamic>?;

      try {
        final decodedData = _decodeMessageData(
          rawData,
          encoding,
          delta != null,
        );
        // Parse action from numeric wire value (TM2j)
        MessageAction? messageAction;
        final rawAction = map['action'];
        if (rawAction is int) {
          messageAction = MessageActionExtension.fromInt(rawAction);
        }

        messages.add(
          Message(
            id: map['id'] as String?,
            name: map['name'] as String?,
            data: decodedData,
            clientId: map['clientId'] as String?,
            connectionId: map['connectionId'] as String?,
            timestamp: map['timestamp'] as int?,
            extras: extras != null ? MessageExtras.fromMap(extras) : null,
            action: messageAction,
            serial: map['serial'] as String?,
          ),
        );
      } on AblyException catch (e) {
        if (e.errorInfo?.code == 40019) {
          // No vcdiff plugin — channel FAILED (PC3)
          _transitionTo(ChannelState.failed, error: e.errorInfo);
          return;
        }
        if (e.errorInfo?.code == 40018) {
          // Decode failure — start recovery (RTL18a, RTL18b)
          _startDecodeFailureRecovery(e.errorInfo!);
          return; // Discard remaining messages
        }
        rethrow;
      }
    }

    // RTL20: Update last message ID (use last in array)
    if (messages.isNotEmpty) {
      _lastPayloadMessageId = messages.last.id;
      _lastPayloadProtocolMessageChannelSerial = protocolMessage.channelSerial;
    }

    // Deliver to subscribers
    for (final message in messages) {
      for (final sub in _subscribers) {
        if (sub.matches(message)) {
          sub.listener(message);
        }
      }
    }
  }

  /// Decodes message data with vcdiff delta support.
  ///
  /// Processes the encoding string right-to-left (outermost encoding first).
  /// For vcdiff-encoded messages, uses the registered plugin to decode the
  /// delta against the stored base payload. Tracks the base payload for
  /// subsequent delta decoding.
  ///
  /// Throws [AblyException] with code 40019 if vcdiff encoding is present
  /// but no plugin is registered, or 40018 if decoding fails.
  ///
  /// Spec: RTL19, PC3, PC3a
  Object? _decodeMessageData(
    Object? data,
    String? encoding,
    bool isDelta,
  ) {
    if (encoding == null || encoding.isEmpty) {
      // No encoding — store raw data as base (RTL19b)
      _basePayload = data;
      return data;
    }

    final encodings = encoding.split('/');
    var result = data;

    // Track the base payload separately from the decoded result.
    // Mirrors ably-js: lastPayload starts as the raw wire data and is
    // only updated by base64 (if outermost) or vcdiff. The json and
    // utf-8 steps do NOT update lastPayload — the base is stored in
    // its wire-encoded form (before json/utf-8 decode).
    var lastPayload = data;

    // Process encodings right-to-left (outermost first)
    for (var i = encodings.length - 1; i >= 0; i--) {
      final enc = encodings[i].trim();

      if (enc == 'vcdiff') {
        // Check plugin exists (PC3)
        final plugin = _clientOptions.plugins?['vcdiff'];
        if (plugin == null || plugin is! VCDiffDecoder) {
          _logger.error('Message decode failed', {
            'channel': _name,
            'reason': 'VCDiff decoder plugin not available',
            'code': 40019,
          });
          throw const AblyException(
            errorInfo: ErrorInfo(
              code: 40019,
              statusCode: 400,
              message: 'VCDiff delta decoding is not supported without a '
                  'vcdiff decoder plugin',
            ),
          );
        }

        // Get base payload (PC3a: UTF-8 encode if String)
        var base = _basePayload;
        if (base is String) {
          base = Uint8List.fromList(utf8.encode(base));
        }
        if (base is! Uint8List) {
          throw const AblyException(
            errorInfo: ErrorInfo(
              code: 40018,
              statusCode: 400,
              message: 'No base payload available for delta decode',
            ),
          );
        }

        // Ensure delta is bytes
        final deltaBytes = result is Uint8List
            ? result
            : Uint8List.fromList(utf8.encode(result as String));
        try {
          result = plugin.decode(deltaBytes, base);
        } catch (e) {
          _logger.error('Message decode failed', {
            'channel': _name,
            'reason': 'VCDiff decode error',
            'code': 40018,
          });
          throw AblyException(
            errorInfo: ErrorInfo(
              code: 40018,
              statusCode: 400,
              message: 'VCDiff decode failed: $e',
            ),
          );
        }
        // RTL19c: Store vcdiff result as new base payload
        lastPayload = result;
      } else if (enc == 'base64') {
        result = Uint8List.fromList(base64.decode(result as String));
        // RTL19a: If base64 is the outermost encoding (last in the string,
        // first processed), store the decoded bytes as base payload.
        if (i == encodings.length - 1) {
          lastPayload = result;
        }
      } else {
        // json, utf-8 — decode but do NOT update lastPayload
        result = Message.decodeSingle(result, enc);
      }
    }

    // Store the tracked base payload for subsequent delta decoding
    _basePayload = lastPayload;

    return result;
  }

  /// Starts decode failure recovery by reattaching the channel.
  ///
  /// Logs the error, transitions to ATTACHING, and sends a new ATTACH
  /// with the channelSerial from the last successfully decoded message.
  /// Only one recovery can be in progress at a time.
  ///
  /// Spec: RTL18, RTL18a, RTL18b, RTL18c
  void _startDecodeFailureRecovery(ErrorInfo reason) {
    if (_decodeFailureRecoveryInProgress) return;

    _logger.warn('Delta decode failure, initiating recovery', {
      'channel': _name,
      'code': reason.code,
      'message': reason.message,
    });

    _decodeFailureRecoveryInProgress = true;
    // RTL18c: Transition to ATTACHING with the error reason
    _transitionTo(ChannelState.attaching, error: reason);
    _sendAttachMessage();
    _startAttachTimeout();
  }

  /// Sends an ATTACH protocol message.
  void _sendAttachMessage() {
    _logger.debug('Sending ATTACH', {'channel': _name});
    var flags = 0;

    // Encode modes as flags (RTL4l)
    if (_options.modes != null && _options.modes!.isNotEmpty) {
      flags |= encodeModeFlags(_options.modes!);
    }

    // Set ATTACH_RESUME if previously attached (RTL4j)
    if (_hasBeenAttached) {
      flags |= flagAttachResume;
    }

    // RTL18c: During decode failure recovery, use the channelSerial from the
    // last successfully decoded message so the server resends from that point.
    final channelSerial = _decodeFailureRecoveryInProgress
        ? _lastPayloadProtocolMessageChannelSerial
        : properties.channelSerial;

    _connection.sendMessage(
      ProtocolMessage(
        action: ProtocolAction.attach,
        channel: _name,
        channelSerial: channelSerial,
        flags: flags != 0 ? flags : null,
        params: _options.params,
      ),
    );
  }

  /// Sends a DETACH protocol message.
  void _sendDetachMessage() {
    _logger.debug('Sending DETACH', {'channel': _name});
    _connection.sendMessage(
      ProtocolMessage(
        action: ProtocolAction.detach,
        channel: _name,
      ),
    );
  }

  /// Starts the attach timeout timer (RTL4f).
  void _startAttachTimeout() {
    _timerManager.schedule(
      owner: this,
      name: 'attachTimeout',
      duration: Duration(milliseconds: _clientOptions.realtimeRequestTimeout),
      callback: () {
        if (_state != ChannelState.attaching) return;

        _logger.warn('Attach timeout', {'channel': _name});
        const error = ErrorInfo(
          code: 90007,
          message: 'Channel attach timed out',
        );
        _transitionTo(ChannelState.suspended, error: error);

        if (_attachCompleter != null && !_attachCompleter!.isCompleted) {
          _attachCompleter!.completeError(
            const AblyException(errorInfo: error),
          );
        }
        _attachCompleter = null;

        // RTL13b: Schedule automatic retry from SUSPENDED
        _scheduleChannelRetry();
      },
    );
  }

  /// Schedules automatic channel retry from SUSPENDED state (RTL13b).
  void _scheduleChannelRetry() {
    if (_connection.state != ConnectionState.connected) return;

    _logger.debug('Channel retry scheduled', {
      'channel': _name,
      'delayMs': _clientOptions.channelRetryTimeout,
    });
    _timerManager.schedule(
      owner: this,
      name: 'channelRetry',
      duration: Duration(
        milliseconds: _clientOptions.channelRetryTimeout,
      ),
      callback: () {
        if (_state == ChannelState.suspended &&
            _connection.state == ConnectionState.connected) {
          _transitionTo(ChannelState.attaching);
          _attachCompleter = Completer<void>();
          _attachCompleter!.future.ignore();
          _sendAttachMessage();
          _startAttachTimeout();
        }
      },
    );
  }

  /// Starts the detach timeout timer (RTL5f).
  void _startDetachTimeout() {
    _timerManager.schedule(
      owner: this,
      name: 'detachTimeout',
      duration: Duration(milliseconds: _clientOptions.realtimeRequestTimeout),
      callback: () {
        if (_state != ChannelState.detaching) return;

        _logger.warn('Detach timeout', {'channel': _name});
        const error = ErrorInfo(
          code: 90007,
          message: 'Channel detach timed out',
        );

        // Return to previous state (attached) — RTL5f
        _transitionTo(ChannelState.attached);

        if (_detachCompleter != null && !_detachCompleter!.isCompleted) {
          _detachCompleter!.completeError(
            const AblyException(errorInfo: error),
          );
        }
        _detachCompleter = null;
      },
    );
  }

  /// Emits an UPDATE event when ATTACHED received while already attached (RTL12).
  void _emitUpdate({ErrorInfo? reason, bool? hasBacklog}) {
    _stateChangeController.add(
      ChannelStateChange(
        event: ChannelEvent.update,
        current: ChannelState.attached,
        previous: ChannelState.attached,
        reason: reason,
        hasBacklog: hasBacklog,
      ),
    );
  }

  /// Transitions to a new state and emits a state change event.
  void _transitionTo(
    ChannelState newState, {
    ErrorInfo? error,
    bool resumed = false,
    bool? hasBacklog,
  }) {
    if (_state == newState && error == null) {
      return;
    }

    final previous = _state;
    _state = newState;

    _logger.info('Channel state changed', {
      'channel': _name,
      'from': previous.name,
      'to': newState.name,
      if (error != null) 'reason': error.message,
    });

    // Log warn/error for specific states
    if (newState == ChannelState.suspended) {
      _logger.warn('Channel SUSPENDED', {
        'channel': _name,
        if (error != null) 'reason': error.message,
      });
    } else if (newState == ChannelState.failed) {
      _logger.error('Channel FAILED', {
        'channel': _name,
        if (error != null) 'reason': error.message,
      });
    }

    // RTL15b1: Clear channelSerial on DETACHED, SUSPENDED, or FAILED
    if (newState == ChannelState.detached ||
        newState == ChannelState.suspended ||
        newState == ChannelState.failed) {
      properties.channelSerial = null;
    }

    // RTP5a: Clear presence maps on DETACHED or FAILED
    if (newState == ChannelState.detached || newState == ChannelState.failed) {
      _presence.handleChannelDetachedOrFailed();
    }

    // RTP5f: Preserve presence map on SUSPENDED, but fail pending queue
    if (newState == ChannelState.suspended) {
      _presence.handleChannelSuspended();
    }

    // Update error reason if provided
    if (error != null) {
      _errorReason = error;
    } else if (newState == ChannelState.attached ||
        newState == ChannelState.detached) {
      // Clear error when successfully attached or detached
      _errorReason = null;
    }

    // Map state to event
    final event = ChannelEventExtension.fromState(newState);

    final change = ChannelStateChange(
      event: event,
      current: newState,
      previous: previous,
      reason: error,
      resumed: resumed,
      hasBacklog: hasBacklog,
    );

    _stateChangeController.add(change);
  }

  /// Sets or updates the channel options.
  ///
  /// If the channel is in the attached or attaching state and the new options
  /// include params or modes, this will trigger a reattachment to apply the
  /// new options on the server.
  ///
  /// Spec: RTL16, RTL16a
  @override
  Future<void> setOptions(RealtimeChannelOptions options) async {
    _logger.info('setOptions() called', {'channel': _name});
    final needsReattach = options.requiresReattachment &&
        (_state == ChannelState.attached || _state == ChannelState.attaching);

    _options = options;

    if (needsReattach) {
      if (_state == ChannelState.attached) {
        _transitionTo(ChannelState.attaching);

        final completer = Completer<void>();
        _attachCompleter = completer;
        _sendAttachMessage();
        _startAttachTimeout();

        await completer.future;
      }
      // If attaching, the current attach operation will use the new options
    }
  }

  /// Updates the channel options without triggering reattachment.
  ///
  /// This is used internally by RealtimeChannels.get() for the soft-deprecated
  /// RTS3c behavior where options are updated but reattachment is not allowed.
  void updateOptionsWithoutReattach(RealtimeChannelOptions options) {
    _options = options;
  }

  /// Shared implementation for updateMessage, deleteMessage, appendMessage.
  ///
  /// RTL32c: Builds a new wire body — does NOT mutate the user's Message.
  /// RTL32b: Sends a MESSAGE ProtocolMessage with the appropriate action.
  /// RTL32d: Returns UpdateDeleteResult from the ACK response.
  Future<UpdateDeleteResult> _mutateMessage(
    Message message,
    MessageAction action, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) async {
    _validateSerial(message.serial);

    _logger.info('${action.name}() called', {
      'channel': _name,
      'serial': message.serial,
    });

    // RTL32c: Build new map, do not mutate the user's message
    final body = <String, dynamic>{};
    body['action'] = action.toInt();
    body['serial'] = message.serial;

    if (message.name != null) body['name'] = message.name;
    if (message.clientId != null) body['clientId'] = message.clientId;
    if (message.extras != null) body['extras'] = message.extras!.toMap();

    // RTL32b / RSL15d: Encode data per RSL4
    if (message.data != null) {
      Message.encodeDataInto(
        body,
        message.data!,
        message.encoding,
        useBinaryProtocol: _clientOptions.useBinaryProtocol,
      );
    }

    // RTL32b2: Include version only when operation is provided
    if (operation != null) {
      body['version'] = operation.toMap();
    }

    // RTL32c4: Fail if channel is SUSPENDED or FAILED
    if (_state == ChannelState.suspended || _state == ChannelState.failed) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish when channel is $_state',
          statusCode: 400,
        ),
      );
    }

    // RTL32b: Send MESSAGE ProtocolMessage
    final protocolMessage = ProtocolMessage(
      action: ProtocolAction.message,
      channel: _name,
      messages: [body],
      params: params,
    );

    final connState = _connection.state;

    final PublishResult result;
    if (connState == ConnectionState.connected) {
      result = await _connection.sendPublishMessage(protocolMessage);
    } else if (connState == ConnectionState.initialized ||
        connState == ConnectionState.connecting ||
        connState == ConnectionState.disconnected) {
      if (_clientOptions.queueMessages) {
        result = await _connection.queueMessage(protocolMessage);
      } else {
        throw AblyException(
          errorInfo: ErrorInfo(
            code: 90001,
            message: 'Cannot publish when connection is $connState and '
                'queueMessages is false',
            statusCode: 400,
          ),
        );
      }
    } else {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish when connection is $connState',
          statusCode: 400,
        ),
      );
    }

    // RTL32d: Parse UpdateDeleteResult from ACK res
    final serials = result.serials;
    final versionSerial =
        (serials.isNotEmpty && serials[0] != null) ? serials[0] : null;
    return UpdateDeleteResult(versionSerial: versionSerial);
  }

  /// Validates that a serial is non-null and non-empty.
  ///
  /// Spec: RTL32a
  void _validateSerial(String? serial) {
    if (serial == null || serial.isEmpty) {
      throw const AblyException(
        message: 'Message serial is required',
        errorInfo: ErrorInfo(
          message: 'Message serial is required',
          code: 40003,
          statusCode: 400,
        ),
      );
    }
  }

  /// Disposes resources used by this channel.
  void dispose() {
    _timerManager.cancelAll(owner: this);
    _subscribers.clear();
    _stateChangeController.close();
  }
}

/// A message subscription registered via [RealtimeChannel.subscribe].
class _Subscription {
  _Subscription({required this.listener, this.name, this.filter});

  /// The callback to invoke when a matching message arrives.
  final void Function(Message) listener;

  /// If non-null, only messages with this name are delivered.
  final String? name;

  /// If non-null, only messages matching all filter criteria are delivered.
  final MessageFilter? filter;

  bool matches(Message message) {
    if (filter != null) {
      return _matchesFilter(message, filter!);
    }
    if (name != null) {
      return name == message.name;
    }
    return true;
  }

  static bool _matchesFilter(Message message, MessageFilter filter) {
    final ref = message.extras?.data['ref'] as Map<String, dynamic>?;
    final hasRef = ref != null;

    if (filter.isRef != null) {
      if (filter.isRef! && !hasRef) return false;
      if (!filter.isRef! && hasRef) return false;
    }
    if (filter.refTimeserial != null) {
      if (!hasRef || ref['timeserial'] != filter.refTimeserial) return false;
    }
    if (filter.refType != null) {
      if (!hasRef || ref['type'] != filter.refType) return false;
    }
    if (filter.name != null) {
      if (message.name != filter.name) return false;
    }
    if (filter.clientId != null) {
      if (message.clientId != filter.clientId) return false;
    }
    return true;
  }
}

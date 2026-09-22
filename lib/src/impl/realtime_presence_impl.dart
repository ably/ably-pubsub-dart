import 'dart:async';

import '../channels/rest_history_params.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../message/presence_message.dart';
import '../pagination/paginated_result.dart';
import '../presence/presence_action.dart';
import '../realtime/channel_event.dart';
import '../realtime/channel_mode.dart';
import '../realtime/channel_state.dart';
import '../realtime/channel_state_change.dart';
import '../realtime/connection_state.dart';
import '../realtime/protocol_message.dart';
import '../realtime/realtime_presence.dart';
import 'connection_impl.dart';
import 'presence_map.dart';

/// Provides realtime presence operations for a channel.
///
/// Spec: RTP1
class RealtimePresenceImpl implements RealtimePresence {
  /// Creates a RealtimePresence instance.
  RealtimePresenceImpl({
    required String channelName,
    required ConnectionImpl connection,
    required String? Function() getClientId,
    required Future<void> Function() implicitAttach,
    required ChannelState Function() getChannelState,
    required Future<PaginatedResult<PresenceMessage>> Function([
      RestHistoryParams? params,
    ]) restHistory,
    required Logger logger,
  })  : _channelName = channelName,
        _connection = connection,
        _getClientId = getClientId,
        _implicitAttach = implicitAttach,
        _getChannelState = getChannelState,
        _restHistory = restHistory,
        _logger = logger;

  final String _channelName;
  final ConnectionImpl _connection;
  final String? Function() _getClientId;
  final Future<void> Function() _implicitAttach;
  final ChannelState Function() _getChannelState;
  final Future<PaginatedResult<PresenceMessage>> Function([
    RestHistoryParams? params,
  ]) _restHistory;
  final Logger _logger;

  /// The presence map of all members on the channel (RTP2).
  final PresenceMap members = PresenceMap();

  /// The internal map of members entered by this connection (RTP17).
  final LocalPresenceMap _myMembers = LocalPresenceMap();

  /// Whether sync has completed (RTP13).
  bool _syncComplete = false;

  /// Completer for waitForSync callers.
  Completer<void>? _syncCompleter;

  /// Presence event subscribers.
  final List<_PresenceSubscription> _subscribers = [];

  /// Queued presence operations waiting for ATTACHED state (RTP16b).
  final List<_QueuedPresenceOp> _pendingQueue = [];

  /// Whether the presence sync is complete.
  ///
  /// Spec: RTP13
  @override
  bool get syncComplete => _syncComplete;

  // ─── Subscribe / Unsubscribe (RTP6, RTP7) ───

  /// Subscribes to presence events on this channel.
  ///
  /// If [action] is provided, only events matching that action are delivered.
  /// If [actions] is provided, only events matching any of those actions are delivered.
  /// If neither is provided, all events are delivered.
  ///
  /// Optionally triggers an implicit attach (RTP6d).
  ///
  /// Spec: RTP6, RTP6a, RTP6b, RTP6d, RTP6e
  @override
  void subscribe(
    void Function(PresenceMessage) listener, {
    PresenceAction? action,
    List<PresenceAction>? actions,
    bool attachOnSubscribe = true,
  }) {
    _logger.info('presence.subscribe() called', {'channel': _channelName});
    final effectiveActions = actions ?? (action != null ? [action] : null);
    _subscribers.add(
      _PresenceSubscription(
        listener: listener,
        actions: effectiveActions,
      ),
    );

    // RTP6d: Implicit attach
    if (attachOnSubscribe) {
      final state = _getChannelState();
      if (state == ChannelState.initialized ||
          state == ChannelState.detached ||
          state == ChannelState.detaching) {
        unawaited(_implicitAttach().catchError((_) {}));
      }
    }
  }

  /// Unsubscribes from presence events.
  ///
  /// If [listener] is null, all subscriptions are removed (RTP7c).
  /// If [listener] is provided, only that listener is removed.
  /// If both [listener] and [action] are provided, only that specific
  /// action subscription for that listener is removed (RTP7b).
  ///
  /// Spec: RTP7, RTP7a, RTP7b, RTP7c
  @override
  void unsubscribe({
    void Function(PresenceMessage)? listener,
    PresenceAction? action,
  }) {
    _logger.info('presence.unsubscribe() called', {'channel': _channelName});
    if (listener == null) {
      // RTP7c: Remove all
      _subscribers.clear();
      return;
    }

    _subscribers.removeWhere((sub) {
      if (action != null) {
        // RTP7b: Remove by listener + action
        return sub.listener == listener &&
            sub.actions != null &&
            sub.actions!.length == 1 &&
            sub.actions!.first == action;
      }
      // RTP7a: Remove by listener (all-action subscription only)
      return sub.listener == listener && sub.actions == null;
    });
  }

  // ─── Enter / Update / Leave (RTP8, RTP9, RTP10) ───

  /// Enters the presence set for the current clientId.
  ///
  /// Spec: RTP8, RTP8a, RTP8c, RTP8d, RTP8e, RTP8j
  @override
  Future<void> enter([Object? data]) async {
    _logger.info('presence.enter() called', {'channel': _channelName});
    final clientId = _getClientId();
    // RTP8j: Error for null or wildcard clientId
    if (clientId == null || clientId == '*') {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 91000,
          message: clientId == '*'
              ? 'Cannot use enter() with a wildcard clientId, '
                  'use enterClient() instead'
              : 'Cannot enter without a clientId',
          statusCode: 400,
        ),
      );
    }

    await _publishPresence(
      PresenceMessage(action: PresenceAction.enter, data: data),
    );
  }

  /// Updates the presence data for the current clientId.
  ///
  /// Spec: RTP9, RTP9a, RTP9d
  @override
  Future<void> update([Object? data]) async {
    _logger.info('presence.update() called', {'channel': _channelName});
    final clientId = _getClientId();
    if (clientId == null || clientId == '*') {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 91000,
          message: clientId == '*'
              ? 'Cannot use update() with a wildcard clientId, '
                  'use updateClient() instead'
              : 'Cannot update without a clientId',
          statusCode: 400,
        ),
      );
    }

    await _publishPresence(
      PresenceMessage(action: PresenceAction.update, data: data),
    );
  }

  /// Leaves the presence set for the current clientId.
  ///
  /// Spec: RTP10, RTP10a, RTP10c
  @override
  Future<void> leave([Object? data]) async {
    _logger.info('presence.leave() called', {'channel': _channelName});
    final clientId = _getClientId();
    if (clientId == null || clientId == '*') {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 91000,
          message: clientId == '*'
              ? 'Cannot use leave() with a wildcard clientId, '
                  'use leaveClient() instead'
              : 'Cannot leave without a clientId',
          statusCode: 400,
        ),
      );
    }

    await _publishPresence(
      PresenceMessage(action: PresenceAction.leave, data: data),
    );
  }

  /// Enters the presence set for a specific clientId.
  ///
  /// Requires the connection to have a wildcard clientId or the same clientId.
  ///
  /// Spec: RTP14, RTP14a, RTP15e, RTP15f
  @override
  Future<void> enterClient(String clientId, [Object? data]) async {
    _logger.info('presence.enterClient() called', {
      'channel': _channelName,
      'clientId': clientId,
    });
    _validateClientIdForClientOp(clientId);
    await _publishPresence(
      PresenceMessage(
        action: PresenceAction.enter,
        clientId: clientId,
        data: data,
      ),
    );
  }

  /// Updates presence data for a specific clientId.
  ///
  /// Spec: RTP15, RTP15a
  @override
  Future<void> updateClient(String clientId, [Object? data]) async {
    _logger.info('presence.updateClient() called', {
      'channel': _channelName,
      'clientId': clientId,
    });
    _validateClientIdForClientOp(clientId);
    await _publishPresence(
      PresenceMessage(
        action: PresenceAction.update,
        clientId: clientId,
        data: data,
      ),
    );
  }

  /// Leaves the presence set for a specific clientId.
  ///
  /// Spec: RTP15, RTP15a
  @override
  Future<void> leaveClient(String clientId, [Object? data]) async {
    _logger.info('presence.leaveClient() called', {
      'channel': _channelName,
      'clientId': clientId,
    });
    _validateClientIdForClientOp(clientId);
    await _publishPresence(
      PresenceMessage(
        action: PresenceAction.leave,
        clientId: clientId,
        data: data,
      ),
    );
  }

  /// Validates that the connection's clientId allows the *Client operation.
  void _validateClientIdForClientOp(String targetClientId) {
    final connClientId = _getClientId();
    // RTP15f: Non-wildcard clientId can only act on itself
    if (connClientId != null &&
        connClientId != '*' &&
        connClientId != targetClientId) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 91000,
          message: 'Cannot enter/update/leave for clientId "$targetClientId" '
              'when connection clientId is "$connClientId"',
          statusCode: 400,
        ),
      );
    }
  }

  // ─── Get (RTP11) ───

  /// Gets the current presence members on this channel.
  ///
  /// By default, waits for sync to complete. Set [waitForSync] to false
  /// to return immediately with whatever members are available.
  ///
  /// Spec: RTP11, RTP11a, RTP11b, RTP11c1, RTP11c2, RTP11c3, RTP11d
  @override
  Future<List<PresenceMessage>> get({
    bool waitForSync = true,
    String? clientId,
    String? connectionId,
  }) async {
    _logger.info('presence.get() called', {'channel': _channelName});
    final channelState = _getChannelState();

    // RTP11d: Error on SUSPENDED with default waitForSync
    if (channelState == ChannelState.suspended && waitForSync) {
      throw const AblyException(
        errorInfo: ErrorInfo(
          code: 91005,
          message: 'Cannot get presence members when channel is SUSPENDED',
          statusCode: 400,
        ),
      );
    }

    // RTP11b: Implicit attach
    if (channelState == ChannelState.initialized ||
        channelState == ChannelState.detached) {
      await _implicitAttach();
    }

    // RTP11a: Wait for sync to complete
    if (waitForSync && !_syncComplete) {
      _syncCompleter ??= Completer<void>();
      await _syncCompleter!.future;
    }

    // Return members, filtered by clientId/connectionId
    var result = members.values();

    if (clientId != null) {
      result = result.where((m) => m.clientId == clientId).toList();
    }
    if (connectionId != null) {
      result = result.where((m) => m.connectionId == connectionId).toList();
    }

    return result;
  }

  // ─── History (RTP12) ───

  /// Gets the presence history for this channel.
  ///
  /// Delegates to the REST presence history endpoint.
  ///
  /// Spec: RTP12, RTP12a, RTP12c, RTP12d
  @override
  Future<PaginatedResult<PresenceMessage>> history([
    RestHistoryParams? params,
  ]) {
    _logger.info('presence.history() called', {'channel': _channelName});
    return _restHistory(params);
  }

  // ─── Internal: Protocol message handling ───

  /// Handles incoming PRESENCE protocol messages.
  ///
  /// Applies each presence message to the PresenceMap and emits to
  /// subscribers.
  void handlePresenceMessage(ProtocolMessage protocolMessage) {
    final rawPresence = protocolMessage.presence;
    if (rawPresence == null) return;

    for (final raw in rawPresence) {
      final msg = raw is PresenceMessage
          ? raw
          : PresenceMessage.fromMap(raw as Map<String, dynamic>);

      // RTF1: ignore only when the wire carried an action value this SDK
      // could not decode — a member with no action field at all is
      // unaffected. CHA-M4m5 fixes the level at INFO.
      final rawAction = raw is Map<String, dynamic> ? raw['action'] : null;
      if ((rawAction is int || rawAction is String) && msg.action == null) {
        _logger.info('Ignoring presence message with unrecognised action', {
          'channel': _channelName,
          'action': rawAction,
        });
        continue;
      }

      _processPresenceMessage(msg);
    }
  }

  /// Handles incoming SYNC protocol messages.
  ///
  /// SYNC messages contain presence state from the server. They use
  /// channelSerial to indicate sync progress:
  /// - Non-empty cursor after ':' = more SYNC messages coming
  /// - Empty cursor after ':' (or no ':') = sync complete
  ///
  /// Spec: RTP18, RTP18a, RTP18b, RTP18c
  void handleSyncMessage(ProtocolMessage protocolMessage) {
    final channelSerial = protocolMessage.channelSerial;

    // Start sync if not already in progress
    if (!members.isSyncInProgress) {
      members.startSync();
    }

    // Process presence messages in the SYNC
    final rawPresence = protocolMessage.presence;
    if (rawPresence != null) {
      for (final raw in rawPresence) {
        final msg = raw is PresenceMessage
            ? raw
            : PresenceMessage.fromMap(raw as Map<String, dynamic>);

        // RTF1: ignore only when the wire carried an action value this
        // SDK could not decode — a member with no action field at all is
        // unaffected. CHA-M4m5 fixes the level at INFO.
        final rawAction = raw is Map<String, dynamic> ? raw['action'] : null;
        if ((rawAction is int || rawAction is String) && msg.action == null) {
          _logger.info('Ignoring SYNC member with unrecognised action', {
            'channel': _channelName,
            'action': rawAction,
          });
          continue;
        }

        // During sync, process as put (PRESENT/ENTER/UPDATE) or remove (LEAVE)
        if (msg.action == PresenceAction.leave ||
            msg.action == PresenceAction.absent) {
          members.remove(msg);
        } else {
          members.put(msg);
        }
      }
    }

    // Check if sync is complete (empty cursor after ':')
    final syncComplete = _isSyncComplete(channelSerial);

    if (syncComplete) {
      final leaveEvents = members.endSync();

      // Emit synthesized LEAVE events
      for (final leave in leaveEvents) {
        _emitPresenceEvent(leave);
      }

      _syncComplete = true;
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
      _syncCompleter = null;
    }
  }

  /// Called when the channel receives ATTACHED.
  ///
  /// If HAS_PRESENCE flag is set, we expect a sync.
  /// If not set, the presence set is empty (RTP19a).
  /// If RESUMED, no re-entry needed.
  ///
  /// Returns true if auto re-entry should be performed.
  bool handleAttached(int? flags, {required bool wasAlreadyAttached}) {
    final hasPresence = (flags ?? 0) & flagHasPresence != 0;
    final resumed = (flags ?? 0) & flagResumed != 0;

    if (hasPresence) {
      // Expect SYNC messages — sync will be started when first SYNC arrives
      _syncComplete = false;
      if (_syncCompleter == null) {
        _syncCompleter = Completer<void>();
        // Ensure the future's error is handled even if nobody calls
        // get(waitForSync: true) before the channel detaches/fails.
        _syncCompleter!.future.ignore();
      }
    } else {
      // RTP19a: No HAS_PRESENCE — clear existing members
      final existingMembers = members.values();
      members.clear();

      // Emit LEAVE for any cleared members
      for (final member in existingMembers) {
        _emitPresenceEvent(
          member.copyWith(
            action: PresenceAction.leave,
            clearId: true,
            timestamp: DateTime.now(),
          ),
        );
      }

      _syncComplete = true;
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
      _syncCompleter = null;
    }

    // RTP17i: Auto re-entry on non-RESUMED ATTACHED
    // (except when already attached and RESUMED)
    if (wasAlreadyAttached && resumed) {
      return false; // No re-entry
    }
    return true; // Do re-entry
  }

  /// Called when channel enters DETACHED or FAILED state (RTP5a).
  ///
  /// Clears both presence maps silently (no LEAVE events).
  void handleChannelDetachedOrFailed() {
    members.clear();
    _myMembers.clear();
    _syncComplete = false;
    _failPendingQueue(
      const ErrorInfo(
        code: 90001,
        message: 'Channel is no longer attached',
        statusCode: 400,
      ),
    );
    // Cancel any pending sync waiter
    if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
      _syncCompleter!.completeError(
        const AblyException(
          errorInfo: ErrorInfo(
            code: 90001,
            message: 'Channel detached or failed',
            statusCode: 400,
          ),
        ),
      );
    }
    _syncCompleter = null;
  }

  /// Called when channel enters SUSPENDED state (RTP5f).
  ///
  /// Preserves presence map but fails pending queue.
  void handleChannelSuspended() {
    _failPendingQueue(
      const ErrorInfo(
        code: 91005,
        message: 'Channel is SUSPENDED',
        statusCode: 400,
      ),
    );
  }

  /// Called when channel becomes ATTACHED — flushes queued presence ops (RTP5b).
  void flushPendingQueue() {
    final queue = List<_QueuedPresenceOp>.from(_pendingQueue);
    _pendingQueue.clear();
    for (final op in queue) {
      _sendPresence(op.message).then(
        (_) => op.completer.complete(),
        onError: op.completer.completeError,
      );
    }
  }

  /// Performs auto re-entry for all members in the internal map (RTP17i).
  ///
  /// Called after ATTACHED is received without RESUMED flag.
  /// Returns a list of futures for each re-entry operation.
  void performReentry({
    required void Function(ChannelStateChange) emitUpdate,
  }) {
    final myMembers = _myMembers.values();
    if (myMembers.isEmpty) return;

    final currentConnectionId = _connection.id;

    for (final member in myMembers) {
      // RTP17g: Re-enter with ENTER action, original clientId and data
      // RTP17g1: Omit id if connectionId changed
      final omitId = currentConnectionId != null &&
          member.connectionId != currentConnectionId;

      final reentryMessage = PresenceMessage(
        action: PresenceAction.enter,
        clientId: member.clientId,
        data: member.data,
        id: omitId ? null : member.id,
      );

      // Fire-and-forget but handle errors (RTP17e)
      _sendPresence(reentryMessage).catchError((Object error) {
        // RTP17e: Failed re-entry emits UPDATE with error
        final cause = error is AblyException ? error.errorInfo : null;
        final updateError = ErrorInfo(
          code: 91004,
          message: 'Automatic re-entry failed for clientId '
              '"${member.clientId}"',
          statusCode: 400,
          cause: cause,
        );
        emitUpdate(
          ChannelStateChange(
            event: ChannelEvent.update,
            current: ChannelState.attached,
            previous: ChannelState.attached,
            resumed: true,
            reason: updateError,
          ),
        );
      });
    }
  }

  // ─── Internal helpers ───

  /// Processes a single presence message: updates maps and emits to subscribers.
  void _processPresenceMessage(PresenceMessage msg) {
    PresenceMessage? emitted;

    if (msg.action == PresenceAction.leave) {
      emitted = members.remove(msg);
      // Update internal map
      _myMembers.remove(msg);
    } else {
      emitted = members.put(msg);
      // Track in internal map if it's from this connection
      if (msg.connectionId == _connection.id) {
        _myMembers.put(msg);
      }
    }

    if (emitted != null) {
      _emitPresenceEvent(emitted);
    }
  }

  /// Emits a presence message to matching subscribers.
  void _emitPresenceEvent(PresenceMessage msg) {
    for (final sub in _subscribers) {
      if (sub.actions == null || sub.actions!.contains(msg.action)) {
        sub.listener(msg);
      }
    }
  }

  /// Publishes a presence message, handling channel state (RTP16).
  Future<void> _publishPresence(PresenceMessage message) async {
    final channelState = _getChannelState();

    // RTP16c: Error in DETACHED, FAILED, SUSPENDED
    if (channelState == ChannelState.detached ||
        channelState == ChannelState.failed ||
        channelState == ChannelState.suspended) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish presence when channel is $channelState',
          statusCode: 400,
        ),
      );
    }

    // RTP8d, RTP15e: Implicit attach from INITIALIZED
    if (channelState == ChannelState.initialized) {
      unawaited(_implicitAttach().catchError((_) {}));
    }

    // RTP16a: Send immediately when ATTACHED
    if (channelState == ChannelState.attached) {
      await _sendPresence(message);
      return;
    }

    // RTP16b: Queue when ATTACHING or INITIALIZED (waiting for attach)
    if (channelState == ChannelState.attaching ||
        channelState == ChannelState.initialized) {
      final completer = Completer<void>();
      _pendingQueue.add(
        _QueuedPresenceOp(message: message, completer: completer),
      );
      return completer.future;
    }

    throw const AblyException(
      errorInfo: ErrorInfo(
        code: 90001,
        message: 'Cannot publish presence in current state',
        statusCode: 400,
      ),
    );
  }

  /// Sends a presence protocol message via the connection.
  Future<void> _sendPresence(PresenceMessage message) async {
    final protocolMessage = ProtocolMessage(
      action: ProtocolAction.presence,
      channel: _channelName,
      presence: [message.toMap()],
    );

    final connState = _connection.state;

    if (connState == ConnectionState.connected) {
      await _connection.sendPublishMessage(protocolMessage);
      // Update internal map for enter/update (not leave).
      // If clientId is null (implicit from enter/update/leave), use the
      // connection's clientId for tracking.
      final trackingMessage = message.clientId != null
          ? message
          : PresenceMessage(
              action: message.action,
              clientId: _getClientId(),
              connectionId: _connection.id,
              data: message.data,
            );
      if (trackingMessage.clientId != null) {
        if (message.action == PresenceAction.enter ||
            message.action == PresenceAction.update) {
          _myMembers.put(trackingMessage);
        } else if (message.action == PresenceAction.leave) {
          _myMembers.remove(trackingMessage);
        }
      }
      return;
    }

    throw AblyException(
      errorInfo: ErrorInfo(
        code: 80000,
        message: 'Cannot send presence: connection is $connState',
        statusCode: 400,
      ),
    );
  }

  /// Fails all queued presence operations.
  void _failPendingQueue(ErrorInfo error) {
    final exception = AblyException(errorInfo: error);
    for (final op in _pendingQueue) {
      if (!op.completer.isCompleted) {
        op.completer.completeError(exception);
      }
    }
    _pendingQueue.clear();
  }

  /// Checks if a channelSerial indicates sync completion.
  ///
  /// Format: `cursor_value:sequence_id` — if nothing after ':', sync is done.
  /// Or if channelSerial is null/empty, sync is done (single-message case).
  bool _isSyncComplete(String? channelSerial) {
    if (channelSerial == null || channelSerial.isEmpty) return true;
    final colonIdx = channelSerial.indexOf(':');
    if (colonIdx < 0) return true;
    // Cursor is the part after the colon
    final cursor = channelSerial.substring(colonIdx + 1);
    return cursor.isEmpty;
  }
}

/// A presence subscription registered via [RealtimePresence.subscribe].
class _PresenceSubscription {
  _PresenceSubscription({
    required this.listener,
    this.actions,
  });

  final void Function(PresenceMessage) listener;
  final List<PresenceAction>? actions;
}

/// A queued presence operation waiting for ATTACHED state.
class _QueuedPresenceOp {
  _QueuedPresenceOp({
    required this.message,
    required this.completer,
  });

  final PresenceMessage message;
  final Completer<void> completer;
}

import 'dart:async';

import '../channels/rest_annotations.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../message/annotation.dart';
import '../message/annotation_action.dart';
import '../message/message.dart';
import '../pagination/paginated_result.dart';
import '../realtime/channel_mode.dart';
import '../realtime/channel_state.dart';
import '../realtime/connection_state.dart';
import '../realtime/protocol_message.dart';
import '../realtime/realtime_annotations.dart';
import 'connection_impl.dart';

/// Realtime annotations for pub/sub annotation messaging on a channel.
///
/// Spec: RTL26, RTAN1–RTAN5
class RealtimeAnnotationsImpl implements RealtimeAnnotations {
  /// Creates a RealtimeAnnotations instance.
  RealtimeAnnotationsImpl({
    required String channelName,
    required ConnectionImpl connection,
    required RestAnnotations restAnnotations,
    required Future<void> Function() implicitAttach,
    required ChannelState Function() getChannelState,
    required List<ChannelMode>? Function() getChannelModes,
    required bool Function() getAttachOnSubscribe,
    required bool useBinaryProtocol,
    required Logger logger,
  })  : _channelName = channelName,
        _connection = connection,
        _restAnnotations = restAnnotations,
        _implicitAttach = implicitAttach,
        _getChannelState = getChannelState,
        _getChannelModes = getChannelModes,
        _getAttachOnSubscribe = getAttachOnSubscribe,
        _useBinaryProtocol = useBinaryProtocol,
        _logger = logger;

  final String _channelName;
  final ConnectionImpl _connection;
  final RestAnnotations _restAnnotations;
  final Future<void> Function() _implicitAttach;
  final ChannelState Function() _getChannelState;
  final List<ChannelMode>? Function() _getChannelModes;
  final bool Function() _getAttachOnSubscribe;
  final bool _useBinaryProtocol;
  final Logger _logger;

  /// Annotation subscribers.
  final List<_AnnotationSubscription> _subscribers = [];

  /// Publishes an annotation on a message via the realtime connection.
  ///
  /// Sends an ANNOTATION ProtocolMessage with ANNOTATION_CREATE action.
  ///
  /// Spec: RTAN1
  @override
  Future<void> publish(String messageSerial, Annotation annotation) async {
    _logger.info('annotations.publish() called', {
      'channel': _channelName,
      'messageSerial': messageSerial,
    });

    await _sendAnnotation(
      messageSerial,
      annotation,
      AnnotationAction.annotationCreate,
    );
  }

  /// Deletes an annotation from a message via the realtime connection.
  ///
  /// Sends an ANNOTATION ProtocolMessage with ANNOTATION_DELETE action.
  ///
  /// Spec: RTAN2
  @override
  Future<void> delete(String messageSerial, Annotation annotation) async {
    _logger.info('annotations.delete() called', {
      'channel': _channelName,
      'messageSerial': messageSerial,
    });

    await _sendAnnotation(
      messageSerial,
      annotation,
      AnnotationAction.annotationDelete,
    );
  }

  /// Retrieves annotations for a message via the REST API.
  ///
  /// Identical to RestAnnotations#get (RTAN3a).
  ///
  /// Spec: RTAN3
  @override
  Future<PaginatedResult<Annotation>> get(
    String messageSerial, {
    Map<String, String>? params,
  }) {
    return _restAnnotations.get(messageSerial, params: params);
  }

  /// Subscribes to annotations on this channel.
  ///
  /// If [type] is provided, the listener only receives annotations whose
  /// `type` field matches. If [type] is null, the listener receives all
  /// annotations.
  ///
  /// Triggers implicit attach when attachOnSubscribe is true (RTAN4d).
  /// Logs a warning if ANNOTATION_SUBSCRIBE mode is missing (RTAN4e).
  ///
  /// Spec: RTAN4
  @override
  void subscribe(void Function(Annotation) listener, {String? type}) {
    _logger.info('annotations.subscribe() called', {'channel': _channelName});

    // Register the listener
    _subscribers.add(_AnnotationSubscription(listener: listener, type: type));

    // RTAN4d: Same implicit attach behavior as RTL7g
    final attachOnSubscribe = _getAttachOnSubscribe();
    final channelState = _getChannelState();

    if (attachOnSubscribe) {
      if (channelState == ChannelState.initialized ||
          channelState == ChannelState.detached ||
          channelState == ChannelState.detaching) {
        unawaited(_implicitAttach().catchError((_) {}));
      }
    }

    // RTAN4e: Check for ANNOTATION_SUBSCRIBE mode once attached
    if (channelState == ChannelState.attached) {
      _checkAnnotationSubscribeMode();
    } else if (!attachOnSubscribe) {
      // RTAN4e1: Skip check if attachOnSubscribe is false and not attached
    }
  }

  /// Unsubscribes from annotations on this channel.
  ///
  /// If both [listener] and [type] are null, all subscriptions are removed.
  ///
  /// Spec: RTAN5
  @override
  void unsubscribe({void Function(Annotation)? listener, String? type}) {
    _logger.info('annotations.unsubscribe() called', {
      'channel': _channelName,
    });

    if (listener == null && type == null) {
      _subscribers.clear();
      return;
    }

    _subscribers.removeWhere((sub) {
      if (type != null) {
        return sub.listener == listener && sub.type == type;
      }
      return sub.listener == listener && sub.type == null;
    });
  }

  /// Handles an incoming ANNOTATION ProtocolMessage.
  ///
  /// Decodes annotations and delivers to registered listeners.
  ///
  /// Spec: RTAN4b
  void handleAnnotationMessage(ProtocolMessage protocolMessage) {
    final rawAnnotations = protocolMessage.annotations;
    if (rawAnnotations == null) return;

    for (final rawAnnotation in rawAnnotations) {
      final map = rawAnnotation is Map<String, dynamic>
          ? rawAnnotation
          : (rawAnnotation as Annotation).toMap();

      // Populate fields from parent ProtocolMessage
      final annotationMap = Map<String, dynamic>.from(map);
      if (annotationMap['connectionId'] == null &&
          protocolMessage.connectionId != null) {
        annotationMap['connectionId'] = protocolMessage.connectionId;
      }
      if (annotationMap['timestamp'] == null &&
          protocolMessage.timestamp != null) {
        annotationMap['timestamp'] = protocolMessage.timestamp;
      }

      final annotation = Annotation.fromMap(annotationMap);

      // RTF1: an unrecognised action is ignored with a log rather than
      // thrown. CHA-M4m5 fixes the level at INFO.
      final rawAction = annotationMap['action'];
      if (rawAction is int && annotation.action == null) {
        _logger.info('Ignoring annotation with unrecognised action', {
          'channel': _channelName,
          'action': rawAction,
        });
        continue;
      }

      // RTAN4c: Deliver to listeners, filtering by type
      for (final sub in _subscribers) {
        if (sub.type == null || sub.type == annotation.type) {
          sub.listener(annotation);
        }
      }
    }
  }

  /// Checks attached mode (RTAN4e) after becoming ATTACHED.
  void checkModeOnAttached() {
    if (_subscribers.isNotEmpty) {
      _checkAnnotationSubscribeMode();
    }
  }

  /// Sends an annotation via the realtime connection.
  ///
  /// RTAN1b: Has the same connection and channel state conditions as
  /// message publishing (RTL6c).
  Future<void> _sendAnnotation(
    String messageSerial,
    Annotation annotation,
    AnnotationAction action,
  ) async {
    // RTAN1a3: type is required
    if (annotation.type == null || annotation.type!.isEmpty) {
      throw const AblyException(
        message: 'Annotation type is required',
        errorInfo: ErrorInfo(
          message: 'Annotation type is required',
          code: 40003,
          statusCode: 400,
        ),
      );
    }

    // RTAN1b: Same state conditions as RTL6c
    final channelState = _getChannelState();
    if (channelState == ChannelState.suspended ||
        channelState == ChannelState.failed) {
      throw AblyException(
        errorInfo: ErrorInfo(
          code: 90001,
          message: 'Cannot publish annotation when channel is $channelState',
          statusCode: 400,
        ),
      );
    }

    // Build the wire annotation — do not mutate the user's object
    final wireAnnotation = <String, dynamic>{};
    wireAnnotation['action'] = action.toInt();
    wireAnnotation['messageSerial'] = messageSerial;
    if (annotation.type != null) wireAnnotation['type'] = annotation.type;
    if (annotation.name != null) wireAnnotation['name'] = annotation.name;
    if (annotation.clientId != null) {
      wireAnnotation['clientId'] = annotation.clientId;
    }

    // RTAN1a / RSAN1c3: Encode data per RSL4
    if (annotation.data != null) {
      Message.encodeDataInto(
        wireAnnotation,
        annotation.data!,
        null,
        useBinaryProtocol: _useBinaryProtocol,
      );
    }

    if (annotation.extras != null) {
      wireAnnotation['extras'] = annotation.extras!.toMap();
    }

    // RTAN1c: Build ANNOTATION ProtocolMessage
    final protocolMessage = ProtocolMessage(
      action: ProtocolAction.annotation,
      channel: _channelName,
      annotations: [wireAnnotation],
    );

    final connState = _connection.state;

    // RTAN1b / RTL6c1: Send immediately if CONNECTED
    if (connState == ConnectionState.connected) {
      // RTAN1d: ACK indicates success; await completion
      await _connection.sendPublishMessage(protocolMessage);
      return;
    }

    // RTAN1b / RTL6c2: Queue if appropriate
    if (connState == ConnectionState.initialized ||
        connState == ConnectionState.connecting ||
        connState == ConnectionState.disconnected) {
      await _connection.queueMessage(protocolMessage);
      return;
    }

    // RTL6c4: All other states
    throw AblyException(
      errorInfo: ErrorInfo(
        code: 90001,
        message: 'Cannot publish annotation when connection is $connState',
        statusCode: 400,
      ),
    );
  }

  /// Logs a warning if ANNOTATION_SUBSCRIBE mode is not present.
  ///
  /// Spec: RTAN4e
  void _checkAnnotationSubscribeMode() {
    final modes = _getChannelModes();
    if (modes != null && !modes.contains(ChannelMode.annotationSubscribe)) {
      _logger.warn(
        'Annotation listener registered without ANNOTATION_SUBSCRIBE '
        'channel mode. Annotations will not be received. Request the '
        'ANNOTATION_SUBSCRIBE mode in ChannelOptions.',
        {'channel': _channelName},
      );
    }
  }
}

/// An annotation subscription registered via [RealtimeAnnotations.subscribe].
class _AnnotationSubscription {
  _AnnotationSubscription({required this.listener, this.type});

  /// The callback to invoke when a matching annotation arrives.
  final void Function(Annotation) listener;

  /// If non-null, only annotations with this type are delivered.
  final String? type;
}

import '../error/error_info.dart';
import 'publish_result.dart';

/// Protocol message actions.
enum ProtocolAction {
  heartbeat, // 0
  ack, // 1
  nack, // 2
  connect, // 3
  connected, // 4
  disconnect, // 5
  disconnected, // 6
  close, // 7
  closed, // 8
  error, // 9
  attach, // 10
  attached, // 11
  detach, // 12
  detached, // 13
  presence, // 14
  message, // 15
  sync, // 16
  auth, // 17
  // 18, 19, 20 unused
  annotation, // 21 (TR2/TR3w)
}

extension ProtocolActionExtension on ProtocolAction {
  /// Wire protocol integer for this action.
  static const Map<ProtocolAction, int> _toWire = {
    ProtocolAction.heartbeat: 0,
    ProtocolAction.ack: 1,
    ProtocolAction.nack: 2,
    ProtocolAction.connect: 3,
    ProtocolAction.connected: 4,
    ProtocolAction.disconnect: 5,
    ProtocolAction.disconnected: 6,
    ProtocolAction.close: 7,
    ProtocolAction.closed: 8,
    ProtocolAction.error: 9,
    ProtocolAction.attach: 10,
    ProtocolAction.attached: 11,
    ProtocolAction.detach: 12,
    ProtocolAction.detached: 13,
    ProtocolAction.presence: 14,
    ProtocolAction.message: 15,
    ProtocolAction.sync: 16,
    ProtocolAction.auth: 17,
    ProtocolAction.annotation: 21,
  };

  static final Map<int, ProtocolAction> _fromWire = {
    for (final entry in _toWire.entries) entry.value: entry.key,
  };

  /// Converts action to integer for wire protocol.
  int toInt() => _toWire[this]!;

  /// Creates action from integer.
  ///
  /// Returns `null` for a value this SDK does not recognise (RTF1), so a
  /// future protocol action degrades instead of throwing from inside the
  /// transport handler. Callers must ignore-with-log.
  static ProtocolAction? fromInt(int value) => _fromWire[value];
}

/// Protocol message for WebSocket communication with Ably.
///
/// This represents the protocol messages sent between client and server
/// over the WebSocket transport. Messages are encoded using JSON or MessagePack.
///
/// See: https://ably.com/docs/realtime/messages
class ProtocolMessage {
  /// Creates a protocol message.
  ProtocolMessage({
    this.action,
    this.unrecognisedAction,
    this.channel,
    this.channelSerial,
    this.connectionId,
    this.connectionKey,
    this.connectionDetails,
    this.error,
    this.flags,
    this.id,
    this.msgSerial,
    this.timestamp,
    this.messages,
    this.presence,
    this.annotations,
    this.auth,
    this.params,
    this.count,
    this.res,
  });

  /// The action this message represents.
  final ProtocolAction? action;

  /// The raw wire action value, when the wire sent an integer this SDK
  /// does not recognise (RTF1) and [action] therefore decoded to `null`.
  ///
  /// `null` whenever [action] decoded successfully, and also `null` when
  /// the wire omitted the action field altogether — that distinction lets
  /// callers ignore-with-log only a genuinely unrecognised action, and
  /// leave a message that never carried one untouched.
  final int? unrecognisedAction;

  /// Channel name (for channel-specific messages).
  final String? channel;

  /// Channel serial for message continuity.
  final String? channelSerial;

  /// Unique connection identifier.
  final String? connectionId;

  /// Private connection key for resume.
  final String? connectionKey;

  /// Connection details from CONNECTED message.
  final ConnectionDetails? connectionDetails;

  /// Error information (for ERROR, DISCONNECTED messages).
  final ErrorInfo? error;

  /// Bit flags for message properties.
  final int? flags;

  /// Message identifier.
  final String? id;

  /// Serial number for ordering.
  final int? msgSerial;

  /// Timestamp in milliseconds since epoch.
  final int? timestamp;

  /// Array of Message objects (for MESSAGE action).
  final List<dynamic>? messages;

  /// Array of PresenceMessage objects (for PRESENCE action).
  final List<dynamic>? presence;

  /// Array of Annotation objects (for ANNOTATION action).
  final List<dynamic>? annotations;

  /// Auth details for AUTH action.
  final dynamic auth;

  /// Channel params (for ATTACH messages).
  final Map<String, String>? params;

  /// Number of messages being acknowledged (for ACK/NACK).
  ///
  /// Spec: TR4g
  final int? count;

  /// Array of PublishResult objects (for ACK messages).
  ///
  /// Contains one PublishResult per acknowledged ProtocolMessage in order,
  /// each containing the serials of the messages that were published.
  ///
  /// Spec: TR4s
  final List<PublishResult>? res;

  /// Creates a ProtocolMessage from JSON.
  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    // RTF1: distinguish "the wire sent an action value this SDK cannot
    // decode" from "the wire omitted the action field" — only the former
    // is unrecognisedAction, so ignore-with-log guards don't drop a
    // message that never carried an action in the first place.
    final rawAction = json['action'];
    final decodedAction =
        rawAction is int ? ProtocolActionExtension.fromInt(rawAction) : null;
    return ProtocolMessage(
      action: decodedAction,
      unrecognisedAction:
          rawAction is int && decodedAction == null ? rawAction : null,
      channel: json['channel'] as String?,
      channelSerial: json['channelSerial'] as String?,
      connectionId: json['connectionId'] as String?,
      connectionKey: json['connectionKey'] as String?,
      connectionDetails: json['connectionDetails'] != null
          ? ConnectionDetails.fromJson(
              json['connectionDetails'] as Map<String, dynamic>,
            )
          : null,
      error: json['error'] != null
          ? ErrorInfo.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      flags: json['flags'] as int?,
      id: json['id'] as String?,
      msgSerial: json['msgSerial'] as int?,
      timestamp: json['timestamp'] as int?,
      messages: json['messages'] as List<dynamic>?,
      presence: json['presence'] as List<dynamic>?,
      annotations: json['annotations'] as List<dynamic>?,
      auth: json['auth'],
      params: json['params'] != null
          ? Map<String, String>.from(json['params'] as Map)
          : null,
      count: json['count'] as int?,
      res: json['res'] != null
          ? (json['res'] as List)
              .map((e) => PublishResult.fromMap(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Converts this ProtocolMessage to JSON.
  Map<String, dynamic> toJson() {
    return {
      if (action != null) 'action': action!.toInt(),
      if (channel != null) 'channel': channel,
      if (channelSerial != null) 'channelSerial': channelSerial,
      if (connectionId != null) 'connectionId': connectionId,
      if (connectionKey != null) 'connectionKey': connectionKey,
      if (connectionDetails != null)
        'connectionDetails': connectionDetails!.toJson(),
      if (error != null) 'error': error!.toJson(),
      if (flags != null) 'flags': flags,
      if (id != null) 'id': id,
      if (msgSerial != null) 'msgSerial': msgSerial,
      if (timestamp != null) 'timestamp': timestamp,
      if (messages != null) 'messages': messages,
      if (presence != null) 'presence': presence,
      if (annotations != null) 'annotations': annotations,
      if (auth != null) 'auth': auth,
      if (params != null) 'params': params,
      if (count != null) 'count': count,
      if (res != null) 'res': res,
    };
  }

  @override
  String toString() => 'ProtocolMessage(action: $action, channel: $channel)';
}

/// Connection details from CONNECTED message (CD* specs).
class ConnectionDetails {
  /// Creates connection details.
  ConnectionDetails({
    this.clientId,
    this.connectionKey,
    this.connectionStateTtl,
    this.maxIdleInterval,
    this.maxMessageSize,
    this.maxFrameSize,
    this.maxInboundRate,
    this.serverId,
  });

  /// Client identifier from server.
  final String? clientId;

  /// Private connection key for resume.
  final String? connectionKey;

  /// Connection state TTL in milliseconds.
  final int? connectionStateTtl;

  /// Max idle interval in milliseconds before heartbeat required.
  final int? maxIdleInterval;

  /// Maximum message size in bytes.
  final int? maxMessageSize;

  /// Maximum frame size in bytes.
  final int? maxFrameSize;

  /// Maximum inbound message rate.
  final int? maxInboundRate;

  /// Server identifier.
  final String? serverId;

  /// Creates ConnectionDetails from JSON.
  factory ConnectionDetails.fromJson(Map<String, dynamic> json) {
    return ConnectionDetails(
      clientId: json['clientId'] as String?,
      connectionKey: json['connectionKey'] as String?,
      connectionStateTtl: json['connectionStateTtl'] as int?,
      maxIdleInterval: json['maxIdleInterval'] as int?,
      maxMessageSize: json['maxMessageSize'] as int?,
      maxFrameSize: json['maxFrameSize'] as int?,
      maxInboundRate: json['maxInboundRate'] as int?,
      serverId: json['serverId'] as String?,
    );
  }

  /// Converts this ConnectionDetails to JSON.
  Map<String, dynamic> toJson() {
    return {
      if (clientId != null) 'clientId': clientId,
      if (connectionKey != null) 'connectionKey': connectionKey,
      if (connectionStateTtl != null) 'connectionStateTtl': connectionStateTtl,
      if (maxIdleInterval != null) 'maxIdleInterval': maxIdleInterval,
      if (maxMessageSize != null) 'maxMessageSize': maxMessageSize,
      if (maxFrameSize != null) 'maxFrameSize': maxFrameSize,
      if (maxInboundRate != null) 'maxInboundRate': maxInboundRate,
      if (serverId != null) 'serverId': serverId,
    };
  }
}

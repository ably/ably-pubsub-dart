import 'package:ably_pubsub_device/src/error/error_info.dart';
import 'package:ably_pubsub_device/src/realtime/protocol_message.dart';
import 'package:ably_pubsub_device/src/realtime/publish_result.dart';
import 'package:ably_pubsub_device/src/message/message.dart';

/// Helper functions for creating common protocol messages in tests.
class ProtocolMessageHelpers {
  /// Creates a CONNECTED protocol message.
  static ProtocolMessage connected({
    String connectionId = 'test-connection-id',
    String connectionKey = 'test-connection-key',
    int connectionStateTtl = 120000,
    int maxIdleInterval = 15000,
    int? maxMessageSize,
    String? serverId,
    String? clientId,
    ErrorInfo? error,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.connected,
      connectionId: connectionId,
      connectionKey: connectionKey,
      error: error,
      connectionDetails: ConnectionDetails(
        connectionKey: connectionKey,
        connectionStateTtl: connectionStateTtl,
        maxIdleInterval: maxIdleInterval,
        maxMessageSize: maxMessageSize,
        serverId: serverId,
        clientId: clientId,
      ),
    );
  }

  /// Creates a CLOSED protocol message.
  static ProtocolMessage closed() {
    return ProtocolMessage(action: ProtocolAction.closed);
  }

  /// Creates a DISCONNECTED protocol message.
  static ProtocolMessage disconnected({ErrorInfo? error}) {
    return ProtocolMessage(
      action: ProtocolAction.disconnected,
      error: error,
    );
  }

  /// Creates an ERROR protocol message.
  static ProtocolMessage error({
    required int code,
    required String message,
    int? statusCode,
    String? channel,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.error,
      channel: channel,
      error: ErrorInfo(
        code: code,
        message: message,
        statusCode: statusCode ?? (code ~/ 100),
      ),
    );
  }

  /// Creates an ATTACHED protocol message.
  static ProtocolMessage attached({
    required String channel,
    String? channelSerial,
    int? flags,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.attached,
      channel: channel,
      channelSerial: channelSerial,
      flags: flags,
    );
  }

  /// Creates a DETACHED protocol message.
  static ProtocolMessage detached({
    required String channel,
    ErrorInfo? error,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.detached,
      channel: channel,
      error: error,
    );
  }

  /// Creates an AUTH protocol message.
  static ProtocolMessage auth({required dynamic authDetails}) {
    return ProtocolMessage(
      action: ProtocolAction.auth,
      auth: authDetails,
    );
  }

  /// Creates a HEARTBEAT protocol message.
  static ProtocolMessage heartbeat({String? id}) {
    return ProtocolMessage(action: ProtocolAction.heartbeat, id: id);
  }

  /// Creates an ACK protocol message.
  static ProtocolMessage ack({
    required int msgSerial,
    int count = 1,
    List<PublishResult>? res,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.ack,
      msgSerial: msgSerial,
      count: count,
      res: res,
    );
  }

  /// Creates a MESSAGE protocol message.
  static ProtocolMessage message({
    required String channel,
    String? name,
    dynamic data,
    String? channelSerial,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.message,
      channel: channel,
      channelSerial: channelSerial,
      messages: [
        Message(
          name: name,
          data: data,
        ),
      ],
    );
  }

  /// Creates a PRESENCE protocol message.
  static ProtocolMessage presence({
    required String channel,
    String? channelSerial,
  }) {
    return ProtocolMessage(
      action: ProtocolAction.presence,
      channel: channel,
      channelSerial: channelSerial,
    );
  }
}

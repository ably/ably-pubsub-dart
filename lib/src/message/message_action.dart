/// The type of action performed on a message.
///
/// Spec: TM5
enum MessageAction {
  /// A newly created message.
  messageCreate,

  /// An update to an existing message.
  messageUpdate,

  /// A deletion of an existing message.
  messageDelete,

  /// A meta-message (not a regular message).
  meta,

  /// A summary of a message and its annotations.
  messageSummary,

  /// An append to an existing message.
  messageAppend,
}

/// Extension methods for MessageAction.
extension MessageActionExtension on MessageAction {
  /// Converts to the numeric representation used by the Ably wire protocol.
  ///
  /// Values: messageCreate=0, messageUpdate=1, messageDelete=2,
  /// meta=3, messageSummary=4, messageAppend=5.
  int toInt() {
    switch (this) {
      case MessageAction.messageCreate:
        return 0;
      case MessageAction.messageUpdate:
        return 1;
      case MessageAction.messageDelete:
        return 2;
      case MessageAction.meta:
        return 3;
      case MessageAction.messageSummary:
        return 4;
      case MessageAction.messageAppend:
        return 5;
    }
  }

  /// Creates a MessageAction from the numeric wire protocol value.
  ///
  /// Returns `null` for a value this SDK does not recognise, so a future
  /// server-side action degrades instead of throwing from inside the
  /// transport handler. Callers must ignore-with-log.
  static MessageAction? fromInt(int value) {
    switch (value) {
      case 0:
        return MessageAction.messageCreate;
      case 1:
        return MessageAction.messageUpdate;
      case 2:
        return MessageAction.messageDelete;
      case 3:
        return MessageAction.meta;
      case 4:
        return MessageAction.messageSummary;
      case 5:
        return MessageAction.messageAppend;
      default:
        return null;
    }
  }
}

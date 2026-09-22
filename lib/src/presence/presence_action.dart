/// The type of presence action.
enum PresenceAction {
  /// Not present.
  absent,

  /// Present when initial channel subscription completed.
  present,

  /// Newly entered the channel.
  enter,

  /// Left the channel.
  leave,

  /// Updated presence data.
  update,
}

/// Extension methods for PresenceAction.
extension PresenceActionExtension on PresenceAction {
  /// Converts to the numeric representation used by the Ably wire protocol.
  ///
  /// Values match the Ably protocol: absent=0, present=1, enter=2, leave=3, update=4.
  int toInt() {
    switch (this) {
      case PresenceAction.absent:
        return 0;
      case PresenceAction.present:
        return 1;
      case PresenceAction.enter:
        return 2;
      case PresenceAction.leave:
        return 3;
      case PresenceAction.update:
        return 4;
    }
  }

  /// Creates a PresenceAction from the numeric wire protocol value.
  ///
  /// Returns `null` for a value this SDK does not recognise, so a future
  /// server-side action degrades instead of throwing from inside the
  /// transport handler. Callers must ignore-with-log.
  static PresenceAction? fromInt(int value) {
    switch (value) {
      case 0:
        return PresenceAction.absent;
      case 1:
        return PresenceAction.present;
      case 2:
        return PresenceAction.enter;
      case 3:
        return PresenceAction.leave;
      case 4:
        return PresenceAction.update;
      default:
        return null;
    }
  }

  /// Converts to the string representation used by Ably.
  String toAblyString() {
    switch (this) {
      case PresenceAction.absent:
        return 'absent';
      case PresenceAction.present:
        return 'present';
      case PresenceAction.enter:
        return 'enter';
      case PresenceAction.leave:
        return 'leave';
      case PresenceAction.update:
        return 'update';
    }
  }

  /// Creates a PresenceAction from an Ably string.
  ///
  /// Returns `null` for a value this SDK does not recognise.
  static PresenceAction? fromAblyString(String value) {
    switch (value.toLowerCase()) {
      case 'absent':
        return PresenceAction.absent;
      case 'present':
        return PresenceAction.present;
      case 'enter':
        return PresenceAction.enter;
      case 'leave':
        return PresenceAction.leave;
      case 'update':
        return PresenceAction.update;
      default:
        return null;
    }
  }
}

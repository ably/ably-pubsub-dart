import '../error/ably_exception.dart';
import 'channel_state.dart';
import 'derive_options.dart';
import 'realtime_channel.dart';
import 'realtime_channel_options.dart';

/// Collection of realtime channels.
///
/// Spec: RTS1
abstract class RealtimeChannels {
  /// Gets or creates a channel by name, optionally with channel options.
  ///
  /// Spec: RTS3, RTS3a, RTS3b, RTS3c
  RealtimeChannel get(String name, [RealtimeChannelOptions? options]);

  /// Gets a channel by name (shorthand for [get]).
  RealtimeChannel operator [](String name);

  /// Gets a derived channel with filter expressions.
  ///
  /// Spec: RTS5
  RealtimeChannel getDerived(
    String name,
    DeriveOptions deriveOptions, [
    RealtimeChannelOptions? channelOptions,
  ]);

  /// Returns whether a channel with the given name exists.
  bool exists(String name);

  /// Releases a channel, removing it from the collection so that it can be
  /// garbage collected.
  ///
  /// The channel must be in the [ChannelState.initialized],
  /// [ChannelState.detached] or [ChannelState.failed] state. Otherwise an
  /// [AblyException] with code 90011 is thrown and the channel is left in the
  /// collection. To release an attached channel, `await channel.detach()`
  /// first. Releasing a channel that does not exist does nothing.
  ///
  /// Using a channel reference after it has been released is not supported.
  ///
  /// Spec: RTS4, RTS4c, RTS4d, RTS4e
  void release(String name);

  /// Returns the names of all channels in this collection.
  Iterable<String> get names;
}

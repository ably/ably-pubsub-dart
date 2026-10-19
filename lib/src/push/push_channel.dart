import '../pagination/paginated_result.dart';
import 'push_channel_subscription.dart';

/// Per-channel push notification operations.
///
/// Available on [RealtimeChannel.push].
/// Operates from the perspective of the local device (the push target).
///
/// Spec: RSH7
abstract class PushChannel {
  /// Subscribes the current device to push notifications on this channel.
  ///
  /// Spec: RSH7a, RSH7a1, RSH7a2, RSH7a3
  Future<void> subscribeDevice();

  /// Subscribes the current client to push notifications on this channel.
  ///
  /// Spec: RSH7b, RSH7b1, RSH7b2
  Future<void> subscribeClient();

  /// Unsubscribes the current device from push notifications on this channel.
  ///
  /// Spec: RSH7c, RSH7c1, RSH7c2, RSH7c3
  Future<void> unsubscribeDevice();

  /// Unsubscribes the current client from push notifications on this channel.
  ///
  /// Spec: RSH7d, RSH7d1, RSH7d2
  Future<void> unsubscribeClient();

  /// Lists push channel subscriptions filtered by this channel and device.
  ///
  /// Spec: RSH7e
  Future<PaginatedResult<PushChannelSubscription>> listSubscriptions(
    Map<String, String> params,
  );
}

import 'push_admin.dart';
import 'push_platform.dart';

/// The Push object provides access to push notification administration and,
/// on platforms that support receiving push notifications, push activation.
///
/// Spec: RSH1, RSH2
abstract class Push {
  /// The PushAdmin interface for managing push notifications.
  ///
  /// Spec: RSH1
  PushAdmin get admin;

  /// Activates this device for push notifications.
  ///
  /// Sends a `CalledActivate` event to the activation state machine (RSH3).
  /// The returned future completes when activation succeeds, or completes
  /// with an error if activation fails.
  ///
  /// If [registerCallback] is provided, registration is performed by the
  /// callback (typically against the app's own server) instead of directly
  /// with Ably (RSH3b3a).
  ///
  /// On platforms whose push device details can change after first set,
  /// [updatedCallback] is invoked when a subsequent registration sync
  /// completes (RSH3e2c, RSH3e3d).
  ///
  /// Spec: RSH2a
  Future<void> activate({
    RegisterCallback? registerCallback,
    UpdatedCallback? updatedCallback,
  });

  /// Deactivates this device for push notifications.
  ///
  /// Sends a `CalledDeactivate` event to the activation state machine
  /// (RSH3). The returned future completes when deactivation succeeds, or
  /// completes with an error if deactivation fails.
  ///
  /// If [deregisterCallback] is provided, deregistration is performed by the
  /// callback instead of directly with Ably (RSH3d2a).
  ///
  /// Spec: RSH2b
  Future<void> deactivate({
    DeregisterCallback? deregisterCallback,
  });

  /// Delivers a new push transport token to the library.
  ///
  /// On platforms where changes to the push transport details are delivered
  /// to the application rather than to the library (e.g. an FCM registration
  /// token refresh observed by the application, or an ActivityKit token
  /// update), this provides the means for the application to deliver the new
  /// details.
  ///
  /// The token is validated (RSH2f1) and requires that the device has
  /// completed activation (RSH2f2); the new details are applied to the local
  /// device's push recipient and synced with Ably (RSH2f3).
  ///
  /// Spec: RSH2f
  Future<void> updateToken(PushDeviceToken token);
}

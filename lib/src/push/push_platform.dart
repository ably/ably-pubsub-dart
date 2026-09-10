import '../error/error_info.dart';
import 'device_details.dart';

/// Persistent string key/value storage supplied by the application or
/// platform adapter.
///
/// Push activation state (the Activation State Machine and `LocalDevice`
/// state) outlives the client instance and the process (RSH3), so it must be
/// persisted (RSH8a, RSH8b, RSH8c) and recovered on restart (RSH3h). All
/// methods are asynchronous, because every real backend (AsyncStorage,
/// SharedPreferences, Keychain, a file) is asynchronous or should be treated
/// as such.
///
/// The standard keys used by the SDK are:
/// - `ably.push.deviceId`
/// - `ably.push.deviceSecret`
/// - `ably.push.deviceIdentityToken`
/// - `ably.push.pushRecipient`
/// - `ably.push.activationState`
abstract class PushKeyValueStorage {
  /// Returns the value stored under [key], or null if absent.
  Future<String?> getItem(String key);

  /// Stores [value] under [key].
  Future<void> setItem(String key, String value);

  /// Removes any value stored under [key].
  Future<void> removeItem(String key);
}

/// A push transport token, tagged with its transport so the SDK can build
/// the correct push recipient.
///
/// Spec: PDT1
class PushDeviceToken {
  /// Creates a PushDeviceToken.
  ///
  /// The constructor performs no validation; tokens are validated when
  /// delivered to the library via `Push#updateToken` (RSH2f1).
  const PushDeviceToken({
    required this.transportType,
    required this.token,
    this.apnsTokenType,
  });

  /// The push transport the token belongs to, one of `fcm`, `apns` or `web`.
  ///
  /// Spec: PDT2
  final String transportType;

  /// The token value.
  ///
  /// Spec: PDT3
  final String token;

  /// For `apns` tokens only: the token slot the token belongs to, per PCP3a
  /// (`default`, `location`, `pushToStart`; slot names are extensible).
  /// When absent, defaults to `default`.
  ///
  /// Spec: PDT4
  final String? apnsTokenType;
}

/// Token acquisition callback. Called by the SDK whenever it needs the
/// current push transport token (RSH3a2d).
///
/// Requesting user notification permission beforehand is the application's
/// responsibility, not the SDK's: platform tokens are generally obtainable
/// without notification permission, which only gates displaying
/// notifications.
typedef RequestTokenCallback = Future<PushDeviceToken> Function();

/// The push platform supplied to a client, carrying the platform primitives
/// (persistent storage and token acquisition) plus the device attributes
/// needed for registration.
///
/// Platforms that support receiving push notifications configure a client
/// with one of these via `ClientOptions.pushPlatform`. See the portable
/// helper spec `mock_push_platform.md` for the interface definition.
class PushPlatformConfig {
  /// Creates a PushPlatformConfig.
  const PushPlatformConfig({
    required this.platform,
    required this.formFactor,
    required this.storage,
    required this.requestToken,
  });

  /// The device platform: one of `android`, `ios`, `browser`.
  ///
  /// Spec: PCD6
  final String platform;

  /// The device form factor: one of `phone`, `tablet`, `desktop`, `tv`,
  /// `watch`, `car`, `embedded`, `other`.
  ///
  /// Spec: PCD4
  final String formFactor;

  /// Persistent key/value storage for activation and device state.
  final PushKeyValueStorage storage;

  /// Callback used by the SDK to obtain the current push transport token.
  final RequestTokenCallback requestToken;
}

/// The result of a custom registration performed by a [RegisterCallback].
///
/// Carries the device identity token issued by the app server's registration
/// (RSH3b3a, RSH3c2a) and optionally a clientId associated with the
/// registration.
class DeviceRegistrationResult {
  /// Creates a DeviceRegistrationResult.
  const DeviceRegistrationResult({
    this.deviceIdentityToken,
    this.clientId,
  });

  /// The device identity token issued for the registered device.
  final String? deviceIdentityToken;

  /// The clientId associated with the registration, if any.
  final String? clientId;
}

/// Custom registration callback, optionally provided to `Push#activate`.
///
/// When provided, the library passes it the local [DeviceDetails] updated
/// with the push details instead of registering directly with Ably
/// (RSH3b3a); the callback performs the registration (typically via the
/// app's own server) and returns the issued identity token (RSH3c2a).
typedef RegisterCallback = Future<DeviceRegistrationResult> Function(
  DeviceDetails device,
);

/// Custom deregistration callback, optionally provided to `Push#deactivate`.
///
/// When provided, the library passes it the local device's id instead of
/// deregistering directly with Ably (RSH3d2a).
typedef DeregisterCallback = Future<void> Function(String deviceId);

/// Callback invoked when a registration sync triggered by an updated push
/// token completes, with no error on success (RSH3e2c) or the error on
/// failure (RSH3e3d).
typedef UpdatedCallback = void Function(ErrorInfo? error);

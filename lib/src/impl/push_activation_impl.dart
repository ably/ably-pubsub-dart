import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../push/device_push_details.dart';
import '../push/local_device.dart';
import '../push/push_platform.dart';
import 'auth_impl.dart';
import 'http/http_client.dart';

/// Standard persisted-state storage keys (see the portable helper spec
/// `mock_push_platform.md`).
class PushStorageKeys {
  PushStorageKeys._();

  /// `LocalDevice.id`, stored as a plain string (RSH8b).
  static const deviceId = 'ably.push.deviceId';

  /// `LocalDevice.deviceSecret`, stored as a plain string (RSH8b).
  static const deviceSecret = 'ably.push.deviceSecret';

  /// `LocalDevice.deviceIdentityToken`, stored JSON-encoded (RSH8c).
  static const deviceIdentityToken = 'ably.push.deviceIdentityToken';

  /// The push recipient, stored as a JSON-encoded object.
  static const pushRecipient = 'ably.push.pushRecipient';

  /// The Activation State Machine state name, stored as a plain string.
  static const activationState = 'ably.push.activationState';

  /// `LocalDevice.clientId`, stored as a plain string (RSH8b, RSH8d).
  ///
  /// The portable helper spec does not standardise this key; it is an
  /// ably-dart choice.
  static const clientId = 'ably.push.clientId';
}

/// Push activation support for a client: the local device state and the
/// Activation State Machine, created when a push platform is configured.
///
/// Spec: RSH3, RSH8
class PushActivation {
  /// Creates the activation support for one client.
  PushActivation({
    required PushPlatformConfig platform,
    required AblyHttpClient httpClient,
    required AuthImpl auth,
    required Logger logger,
  }) : device = LocalDeviceManager(
          platform: platform,
          auth: auth,
          logger: logger,
        ) {
    machine = ActivationStateMachine(
      device: device,
      httpClient: httpClient,
      auth: auth,
      logger: logger,
    );
  }

  /// The local device state (RSH8).
  final LocalDeviceManager device;

  /// The Activation State Machine (RSH3).
  late final ActivationStateMachine machine;
}

/// Manages the `LocalDevice` state: loading from persisted storage (RSH8a),
/// identifier generation (RSH3a2b, RSH8b), and persistence of the individual
/// attributes.
///
/// Spec: RSH8
class LocalDeviceManager {
  /// Creates a LocalDeviceManager over the given push platform.
  LocalDeviceManager({
    required this.platform,
    required AuthImpl auth,
    required Logger logger,
  })  : _auth = auth,
        _logger = logger;

  /// The configured push platform (storage + token acquisition).
  final PushPlatformConfig platform;

  final AuthImpl _auth;
  final Logger _logger;

  /// The device id (RSH8b), set once loaded.
  String? id;

  /// The device secret (RSH8b, RSH8k2), set once loaded.
  String? deviceSecret;

  /// The device identity token (RSH8c, RSH8k1).
  String? deviceIdentityToken;

  /// The device clientId (RSH8b, RSH8d, RSH8f).
  String? clientId;

  /// The push recipient (push transport details).
  Map<String, dynamic>? recipient;

  bool _loaded = false;
  Future<void>? _loadFuture;

  /// Whether the device has been loaded from persisted state.
  bool get isLoaded => _loaded;

  /// Loads the device from persisted state on first call (RSH8a).
  ///
  /// A failed load is not cached (RSH8b): a later call retries from scratch.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final future = _loadFuture ??= _load();
    try {
      await future;
    } catch (_) {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _load() async {
    final storage = platform.storage;
    var storedId = await storage.getItem(PushStorageKeys.deviceId);
    var storedSecret = await storage.getItem(PushStorageKeys.deviceSecret);

    // RSH8a1 — a half-present id/secret pair means the device load has
    // failed: discard all persisted LocalDevice attributes and the persisted
    // Activation State Machine data.
    if ((storedId == null) != (storedSecret == null)) {
      _logger.warn('Persisted push device state is corrupt, discarding', {
        'hasId': storedId != null,
        'hasSecret': storedSecret != null,
      });
      await _discardAllPersisted();
      storedId = null;
      storedSecret = null;
    }

    // RSH8a — the remaining attributes are populated "to the extent that
    // they exist", independently of whether an id/secret pair is persisted:
    // a recipient may legitimately be present on its own (e.g. supplied by
    // the platform integration before first activation), in which case
    // RSH3a2c uses it instead of requesting a platform token.
    String? storedIdentityToken;
    Map<String, dynamic>? storedRecipient;
    String? storedClientId;
    try {
      final rawToken =
          await storage.getItem(PushStorageKeys.deviceIdentityToken);
      storedIdentityToken =
          rawToken == null ? null : json.decode(rawToken) as String?;
      final rawRecipient = await storage.getItem(PushStorageKeys.pushRecipient);
      storedRecipient = rawRecipient == null
          ? null
          : (json.decode(rawRecipient) as Map).cast<String, dynamic>();
      storedClientId = await storage.getItem(PushStorageKeys.clientId);
    } on FormatException catch (e) {
      // RSH8a1 — otherwise-corrupt persisted state: discard everything.
      _logger.warn('Persisted push device state is corrupt, discarding', {
        'error': e.toString(),
      });
      await _discardAllPersisted();
      storedId = null;
      storedSecret = null;
      storedIdentityToken = null;
      storedRecipient = null;
      storedClientId = null;
    }

    final authClientId = _authClientId();
    if (storedId == null) {
      // RSH3a2b / RSH8b — generate the identifiers and persist them; a
      // failed persist propagates so the triggering operation fails.
      final newId = _generateDeviceId();
      final newSecret = _generateDeviceSecret();
      await storage.setItem(PushStorageKeys.deviceId, newId);
      await storage.setItem(PushStorageKeys.deviceSecret, newSecret);
      if (authClientId != null) {
        await storage.setItem(PushStorageKeys.clientId, authClientId);
      }
      // RSH8a — the other persisted attributes are still populated to the
      // extent that they exist: in particular a pre-seeded recipient (with
      // no id/secret yet) is a legitimate partial state consumed by RSH3a2c.
      id = newId;
      deviceSecret = newSecret;
      deviceIdentityToken = storedIdentityToken;
      recipient = storedRecipient;
      clientId = storedClientId ?? authClientId;
    } else {
      id = storedId;
      deviceSecret = storedSecret;
      deviceIdentityToken = storedIdentityToken;
      recipient = storedRecipient;
      clientId = storedClientId ?? authClientId;
    }
    _loaded = true;
    _logger.debug('Push local device loaded', {
      'deviceId': id,
      'registered': deviceIdentityToken != null,
    });
  }

  /// The present client's clientId per RSA7, or null when unidentified.
  String? _authClientId() {
    final value = _auth.clientId;
    if (value == null || value == '*') return null;
    return value;
  }

  Future<void> _discardAllPersisted() async {
    final storage = platform.storage;
    await storage.removeItem(PushStorageKeys.deviceId);
    await storage.removeItem(PushStorageKeys.deviceSecret);
    await storage.removeItem(PushStorageKeys.deviceIdentityToken);
    await storage.removeItem(PushStorageKeys.pushRecipient);
    await storage.removeItem(PushStorageKeys.clientId);
    await storage.removeItem(PushStorageKeys.activationState);
  }

  /// A UUID v4 generated from a secure random source (RSH3a2b).
  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// base64(sha256(secure random bytes)): a digest of at least 32 bytes,
  /// base64-encoded (RSH3a2b).
  String _generateDeviceSecret() {
    final random = Random.secure();
    final entropy = List<int>.generate(32, (_) => random.nextInt(256));
    return base64.encode(sha256.convert(entropy).bytes);
  }

  /// Persists the deviceIdentityToken, JSON-encoded (RSH8c).
  Future<void> persistIdentityToken() => platform.storage.setItem(
        PushStorageKeys.deviceIdentityToken,
        json.encode(deviceIdentityToken),
      );

  /// Persists the push recipient, JSON-encoded.
  Future<void> persistRecipient() => platform.storage
      .setItem(PushStorageKeys.pushRecipient, json.encode(recipient));

  /// Persists the clientId (RSH8b, RSH8d).
  Future<void> persistClientId() =>
      platform.storage.setItem(PushStorageKeys.clientId, clientId!);

  /// Clears the registration artifacts — the deviceIdentityToken and the
  /// push recipient — from memory and from storage (RSH3g2a).
  Future<void> clearRegistration() async {
    deviceIdentityToken = null;
    recipient = null;
    await platform.storage.removeItem(PushStorageKeys.deviceIdentityToken);
    await platform.storage.removeItem(PushStorageKeys.pushRecipient);
  }

  /// Resets the device identity after deregistration: generates and persists
  /// a fresh id/secret pair and re-derives the clientId from auth, so the
  /// old identity cannot be reused by a later activation (RSH3g2a).
  Future<void> resetIdentity() async {
    id = _generateDeviceId();
    deviceSecret = _generateDeviceSecret();
    clientId = _authClientId();
    final storage = platform.storage;
    await storage.setItem(PushStorageKeys.deviceId, id!);
    await storage.setItem(PushStorageKeys.deviceSecret, deviceSecret!);
    if (clientId != null) {
      await storage.setItem(PushStorageKeys.clientId, clientId!);
    } else {
      await storage.removeItem(PushStorageKeys.clientId);
    }
  }

  /// A snapshot of the current device state as a [LocalDevice] (RSH8).
  ///
  /// Only valid once [isLoaded] is true.
  LocalDevice snapshot() => LocalDevice(
        id: id!,
        clientId: clientId,
        platform: platform.platform,
        formFactor: platform.formFactor,
        push: DevicePushDetails(
          recipient: recipient == null
              ? const {}
              : Map<String, dynamic>.from(recipient!),
        ),
        deviceIdentityToken: deviceIdentityToken,
        deviceSecret: deviceSecret,
      );

  /// Push device authentication headers (RSH6): `X-Ably-DeviceToken` with
  /// the raw deviceIdentityToken when present (RSH6a), else
  /// `X-Ably-DeviceSecret` with the deviceSecret (RSH6b).
  Map<String, String> deviceAuthHeaders() {
    final token = deviceIdentityToken;
    if (token != null) return {'X-Ably-DeviceToken': token};
    final secret = deviceSecret;
    if (secret != null) return {'X-Ably-DeviceSecret': secret};
    return const {};
  }

  /// Applies a [PushDeviceToken] to a recipient map, preserving registered
  /// token variants (RSH2f3, RSH8l2, PCP3a).
  static Map<String, dynamic> applyTokenToRecipient(
    Map<String, dynamic>? existing,
    PushDeviceToken token,
  ) {
    final transportType = token.transportType;
    final Map<String, dynamic> updated;
    if (existing != null && existing['transportType'] == transportType) {
      updated = Map<String, dynamic>.from(existing);
    } else {
      updated = <String, dynamic>{'transportType': transportType};
    }
    switch (transportType) {
      case 'fcm':
        updated['registrationToken'] = token.token;
      case 'apns':
        final slot = token.apnsTokenType ?? 'default';
        if (slot == 'default') {
          // PCP3a — the default slot uses the top-level deviceToken.
          updated['deviceToken'] = token.token;
        } else {
          // PCP3a — variant slots accumulate in apnsDeviceTokens without
          // discarding other registered variants (RSH8l2).
          final slots = Map<String, dynamic>.from(
            updated['apnsDeviceTokens'] as Map? ?? const {},
          );
          slots[slot] = token.token;
          updated['apnsDeviceTokens'] = slots;
        }
      default:
        updated['token'] = token.token;
    }
    return updated;
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// An event delivered to the Activation State Machine (RSH3).
sealed class ActivationEvent {
  const ActivationEvent();

  /// The spec name of the event.
  String get name;
}

/// RSH2a.
class CalledActivate extends ActivationEvent {
  /// Creates the event.
  const CalledActivate();
  @override
  String get name => 'CalledActivate';
}

/// RSH2b.
class CalledDeactivate extends ActivationEvent {
  /// Creates the event.
  const CalledDeactivate();
  @override
  String get name => 'CalledDeactivate';
}

/// RSH8g.
class GotPushDeviceDetails extends ActivationEvent {
  /// Creates the event.
  const GotPushDeviceDetails();
  @override
  String get name => 'GotPushDeviceDetails';
}

/// RSH8h.
class GettingPushDeviceDetailsFailed extends ActivationEvent {
  /// Creates the event.
  const GettingPushDeviceDetailsFailed(this.reason);

  /// The error that caused the failure.
  final ErrorInfo reason;
  @override
  String get name => 'GettingPushDeviceDetailsFailed';
}

/// RSH3b3c.
class GotDeviceRegistration extends ActivationEvent {
  /// Creates the event.
  const GotDeviceRegistration({this.deviceIdentityToken, this.clientId});

  /// The identity token issued by the registration.
  final String? deviceIdentityToken;

  /// The clientId returned by the registration response (RSH8f).
  final String? clientId;
  @override
  String get name => 'GotDeviceRegistration';
}

/// RSH3b3c.
class GettingDeviceRegistrationFailed extends ActivationEvent {
  /// Creates the event.
  const GettingDeviceRegistrationFailed(this.reason);

  /// The error that caused the failure.
  final ErrorInfo reason;
  @override
  String get name => 'GettingDeviceRegistrationFailed';
}

/// RSH3d3c.
class RegistrationSynced extends ActivationEvent {
  /// Creates the event.
  const RegistrationSynced({this.clientId});

  /// The clientId returned by the sync response (RSH8f).
  final String? clientId;
  @override
  String get name => 'RegistrationSynced';
}

/// RSH3d3c.
class SyncRegistrationFailed extends ActivationEvent {
  /// Creates the event.
  const SyncRegistrationFailed(this.reason);

  /// The error that caused the failure.
  final ErrorInfo reason;
  @override
  String get name => 'SyncRegistrationFailed';
}

/// RSH3d2c.
class Deregistered extends ActivationEvent {
  /// Creates the event.
  const Deregistered();
  @override
  String get name => 'Deregistered';
}

/// RSH3d2c.
class DeregistrationFailed extends ActivationEvent {
  /// Creates the event.
  const DeregistrationFailed(this.reason);

  /// The error that caused the failure.
  final ErrorInfo reason;
  @override
  String get name => 'DeregistrationFailed';
}

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------

/// The push Activation State Machine (RSH3).
///
/// Event handling is atomic and sequential (RSH5): `processEvent`
/// implementations are synchronous; all side effects (HTTP requests,
/// persistence, platform calls) are fired without awaiting, and deliver
/// their outcomes as new events. Events with no transition defined for the
/// current state go into the pending-event queue (RSH4), which is drained
/// after each transition with peek/consume/put-back semantics.
class ActivationStateMachine {
  /// Creates the machine over the given device state.
  ActivationStateMachine({
    required this.device,
    required AblyHttpClient httpClient,
    required AuthImpl auth,
    required Logger logger,
  })  : _httpClient = httpClient,
        _auth = auth,
        _logger = logger;

  /// The local device state.
  final LocalDeviceManager device;

  final AblyHttpClient _httpClient;
  final AuthImpl _auth;
  final Logger _logger;

  _ActivationState? _current;
  Future<void>? _initFuture;

  /// RSH4 — the pending events queue.
  final List<ActivationEvent> _pendingEvents = [];

  /// RSH5 — events awaiting sequential handling.
  final List<ActivationEvent> _incoming = [];
  bool _handling = false;

  /// Serializes asynchronous activation-state writes so an earlier slow
  /// write cannot complete after a later transition and persist stale state.
  Future<void> _stateWrite = Future<void>.value();

  /// The custom register callback provided to `Push#activate` (RSH3b3a).
  RegisterCallback? registerCallback;

  /// The custom deregister callback provided to `Push#deactivate` (RSH3d2a).
  DeregisterCallback? deregisterCallback;

  /// The updated callback provided to `Push#activate` (RSH3e2c, RSH3e3d).
  UpdatedCallback? updatedCallback;

  /// Pending `Push#activate` operations; all resolved together (RSH3b1a).
  final List<Completer<void>> _activateCompleters = [];

  /// Pending `Push#deactivate` operations; all resolved together (RSH3g1a).
  final List<Completer<void>> _deactivateCompleters = [];

  /// Whether the device clientId changed since the last registration sync,
  /// so the next sync PATCH carries it (amended RSH3d3b, RSH8d/RSH8e).
  bool _clientIdChanged = false;

  static const _persistentStateNames = {
    'NotActivated',
    'WaitingForNewPushDeviceDetails',
    'AfterRegistrationSyncFailed',
  };

  /// Initialises the machine on first need (RSH3h): (1) loads the
  /// LocalDevice (RSH8a, which may discard the persisted machine state per
  /// RSH8a1); (2) constructs the in-memory state from the persisted state.
  ///
  /// No events are processed before this completes. A failed initialisation
  /// is not cached, so a later attempt retries.
  Future<void> ensureInitialized() async {
    await device.ensureLoaded();
    if (_current != null) return;
    final future = _initFuture ??= _init();
    try {
      await future;
    } catch (_) {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _init() async {
    final name =
        await device.platform.storage.getItem(PushStorageKeys.activationState);
    _current = _stateFromPersistedName(name);
    _logger.debug('Push activation state machine initialised', {
      'persistedState': name,
      'state': _current!.name,
    });
  }

  /// Constructs the in-memory state from a persisted state name (RSH3h).
  ///
  /// An unrecognised (or absent) name yields `NotActivated`. A persisted
  /// `WaitingForNewPushDeviceDetails` is recovered with the recovered-device
  /// flag set: the next `CalledActivate` performs the RSH3a2a registration
  /// validation and the next `GotPushDeviceDetails` performs the RSH3d3
  /// sync, exactly as a `NotActivated` machine with a registered device
  /// would.
  _ActivationState _stateFromPersistedName(String? name) {
    switch (name) {
      case 'NotActivated':
        return const _NotActivated();
      case 'WaitingForNewPushDeviceDetails':
        return const _WaitingForNewPushDeviceDetails(recovered: true);
      case 'AfterRegistrationSyncFailed':
        return const _AfterRegistrationSyncFailed();
      default:
        return const _NotActivated();
    }
  }

  /// Registers a `Push#activate` operation and dispatches `CalledActivate`
  /// (RSH2a). Multiple concurrent operations coalesce: all their futures
  /// resolve when the machine reaches the "makes `Push#activate` return"
  /// step (RSH3b1a, RSH3c1a).
  Future<void> requestActivate({
    RegisterCallback? registerCallback,
    UpdatedCallback? updatedCallback,
  }) {
    if (registerCallback != null) {
      this.registerCallback = registerCallback;
    }
    if (updatedCallback != null) {
      this.updatedCallback = updatedCallback;
    }
    final completer = Completer<void>();
    _activateCompleters.add(completer);
    handleEvent(const CalledActivate());
    return completer.future;
  }

  /// Registers a `Push#deactivate` operation and dispatches
  /// `CalledDeactivate` (RSH2b). Concurrent operations coalesce (RSH3g1a).
  Future<void> requestDeactivate({
    DeregisterCallback? deregisterCallback,
  }) {
    if (deregisterCallback != null) {
      this.deregisterCallback = deregisterCallback;
    }
    final completer = Completer<void>();
    _deactivateCompleters.add(completer);
    handleEvent(const CalledDeactivate());
    return completer.future;
  }

  /// RSH8d/RSH8e — called when the client's auth identity may have changed
  /// (a new token was obtained). If the device exists without a clientId and
  /// the client is now identified, sets and persists the device clientId;
  /// if the device is registered and the machine is in any state other than
  /// `NotActivated`, sends `GotPushDeviceDetails` to trigger a registration
  /// sync carrying the new clientId (amended RSH3d3b).
  void notifyClientId() {
    if (!device.isLoaded) return;
    if (device.clientId != null) return;
    final authClientId = _auth.clientId;
    if (authClientId == null || authClientId == '*') return;

    // RSH8d — set and persist.
    device.clientId = authClientId;
    _logger.debug('Push local device clientId set from auth', {
      'clientId': authClientId,
    });
    unawaited(
      device.persistClientId().catchError((Object e) {
        _logger.error('Failed to persist push device clientId', {
          'error': e.toString(),
        });
      }),
    );

    // RSH8e — trigger a registration sync once the clientId is set.
    if (device.deviceIdentityToken != null &&
        _current != null &&
        _current is! _NotActivated) {
      _clientIdChanged = true;
      handleEvent(const GotPushDeviceDetails());
    }
  }

  /// Delivers an event to the machine (RSH5: atomic, sequential handling).
  ///
  /// Must not be called before [ensureInitialized] has completed (RSH3h).
  void handleEvent(ActivationEvent event) {
    _incoming.add(event);
    if (_handling) return;
    _handling = true;
    try {
      while (_incoming.isNotEmpty) {
        _processEvent(_incoming.removeAt(0));
      }
    } finally {
      _handling = false;
    }
  }

  void _processEvent(ActivationEvent event) {
    final current = _current!;
    final next = current.processEvent(this, event);
    if (next == null) {
      // RSH4 — no transition defined: queue the event.
      _logger.debug('Push activation event queued', {
        'event': event.name,
        'state': current.name,
      });
      _pendingEvents.add(event);
      return;
    }
    _transition(event, next);

    // RSH4 — drain the pending queue: peek, consume on transition, put back
    // in place otherwise.
    while (_pendingEvents.isNotEmpty) {
      final pending = _pendingEvents.first;
      final consumed = _current!.processEvent(this, pending);
      if (consumed == null) break;
      _pendingEvents.removeAt(0);
      _transition(pending, consumed);
    }
  }

  void _transition(ActivationEvent event, _ActivationState next) {
    _logger.debug('Push activation state transition', {
      'from': _current!.name,
      'event': event.name,
      'to': next.name,
    });
    _current = next;
    _persistState();
  }

  /// Persists the current state name when it is one of the persistent
  /// states; transient states leave the previously persisted value.
  void _persistState() {
    final name = _current!.name;
    if (!_persistentStateNames.contains(name)) return;
    _stateWrite = _stateWrite.then((_) async {
      try {
        await device.platform.storage
            .setItem(PushStorageKeys.activationState, name);
      } catch (e) {
        _logger.error('Failed to persist push activation state', {
          'state': name,
          'error': e.toString(),
        });
      }
    });
  }

  // -- Operation resolution --------------------------------------------------

  void _resolveActivate([ErrorInfo? error]) {
    final completers = List.of(_activateCompleters);
    _activateCompleters.clear();
    for (final completer in completers) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(AblyException.fromErrorInfo(error));
      }
    }
  }

  void _resolveDeactivate([ErrorInfo? error]) {
    final completers = List.of(_deactivateCompleters);
    _deactivateCompleters.clear();
    for (final completer in completers) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(AblyException.fromErrorInfo(error));
      }
    }
  }

  // -- Side effects (fired without awaiting; outcomes become events) --------

  /// RSH3a2a — validation of an existing registration: the RSH3a2a1
  /// clientId compatibility check, then the registration sync via the
  /// custom registerCallback (RSH3a2a2) or the canonical RSH3d3b PATCH
  /// (RSH3a2a3). Also used by RSH3f1 and by a recovered
  /// `WaitingForNewPushDeviceDetails`.
  _ActivationState _validateRegistration({required bool byActivate}) {
    final deviceClientId = device.clientId;
    final authClientId = _auth.clientId;
    if (deviceClientId != null &&
        deviceClientId.isNotEmpty &&
        authClientId != null &&
        authClientId != '*' &&
        authClientId != deviceClientId) {
      // RSH3a2a1 — incompatible identity.
      handleEvent(
        SyncRegistrationFailed(
          ErrorInfo(
            message:
                'Activation failed: present clientId "$authClientId" is not '
                'compatible with the device registration clientId '
                '"$deviceClientId"',
            code: 61002,
            statusCode: 400,
          ),
        ),
      );
    } else if (registerCallback != null) {
      _callCustomRegisterer(isNew: false);
    } else {
      _updateRegistration();
    }
    // RSH3a2a4.
    return _WaitingForRegistrationSync(byActivate: byActivate);
  }

  /// RSH3d3 — the registration sync for changed push device details: the
  /// custom registerCallback (RSH3d3a) or the RSH3d3b PATCH.
  _ActivationState _syncRegistration({required bool byActivate}) {
    if (registerCallback != null) {
      _callCustomRegisterer(isNew: false);
    } else {
      _updateRegistration();
    }
    return _WaitingForRegistrationSync(byActivate: byActivate);
  }

  /// RSH3a2d / RSH8h — obtains the push transport token from the platform.
  void _getPushDeviceDetails() {
    unawaited(() async {
      try {
        final token = await device.platform.requestToken();
        device.recipient = LocalDeviceManager.applyTokenToRecipient(
          device.recipient,
          token,
        );
        await device.persistRecipient();
        handleEvent(const GotPushDeviceDetails());
      } catch (e) {
        // RSH8h.
        handleEvent(GettingPushDeviceDetailsFailed(_toErrorInfo(e)));
      }
    }());
  }

  /// RSH3b3b — first-time registration: POST /push/deviceRegistrations with
  /// the LocalDevice (including the deviceSecret) as body.
  void _register() {
    unawaited(() async {
      try {
        final response = await _httpClient.request(
          'POST',
          '/push/deviceRegistrations',
          body: device.snapshot().toMap(),
        );
        final body = response.body;
        String? identityToken;
        String? responseClientId;
        if (body is Map) {
          final tokenField = body['deviceIdentityToken'];
          if (tokenField is Map) {
            identityToken = tokenField['token'] as String?;
          } else if (tokenField is String) {
            identityToken = tokenField;
          }
          responseClientId = body['clientId'] as String?;
        }
        handleEvent(
          GotDeviceRegistration(
            deviceIdentityToken: identityToken,
            clientId: responseClientId,
          ),
        );
      } catch (e) {
        handleEvent(GettingDeviceRegistrationFailed(_toErrorInfo(e)));
      }
    }());
  }

  /// RSH3b3a / RSH3a2a2 / RSH3d3a — registration (or registration sync)
  /// through the custom registerCallback.
  void _callCustomRegisterer({required bool isNew}) {
    final callback = registerCallback!;
    unawaited(() async {
      try {
        final result = await callback(device.snapshot());
        if (isNew) {
          handleEvent(
            GotDeviceRegistration(
              deviceIdentityToken: result.deviceIdentityToken,
              clientId: result.clientId,
            ),
          );
        } else {
          handleEvent(RegistrationSynced(clientId: result.clientId));
        }
      } catch (e) {
        if (isNew) {
          handleEvent(GettingDeviceRegistrationFailed(_toErrorInfo(e)));
        } else {
          handleEvent(SyncRegistrationFailed(_toErrorInfo(e)));
        }
      }
    }());
  }

  /// RSH3d3b — the canonical registration sync: PATCH
  /// /push/deviceRegistrations/:deviceId carrying the complete
  /// push.recipient, together with the clientId when it has changed
  /// (RSH8d), with push device authentication (RSH6).
  void _updateRegistration() {
    unawaited(() async {
      try {
        final body = <String, dynamic>{
          'push': {'recipient': device.recipient},
        };
        if (_clientIdChanged && device.clientId != null) {
          body['clientId'] = device.clientId;
        }
        final response = await _httpClient.request(
          'PATCH',
          '/push/deviceRegistrations/${Uri.encodeComponent(device.id!)}',
          body: body,
          customHeaders: device.deviceAuthHeaders(),
        );
        final responseBody = response.body;
        String? responseClientId;
        if (responseBody is Map) {
          responseClientId = responseBody['clientId'] as String?;
        }
        handleEvent(RegistrationSynced(clientId: responseClientId));
      } catch (e) {
        handleEvent(SyncRegistrationFailed(_toErrorInfo(e)));
      }
    }());
  }

  /// RSH3d2 — deregistration: the custom deregisterCallback (RSH3d2a) or a
  /// DELETE to /push/deviceRegistrations with push device authentication
  /// and no other token or key authentication (RSH3d2b).
  void _deregister() {
    final callback = deregisterCallback;
    unawaited(() async {
      try {
        if (callback != null) {
          await callback(device.id!);
        } else {
          await _httpClient.request(
            'DELETE',
            '/push/deviceRegistrations',
            queryParams: {'deviceId': device.id!},
            customHeaders: device.deviceAuthHeaders(),
            authenticated: false,
          );
        }
        handleEvent(const Deregistered());
      } on AblyException catch (e) {
        // RSH3d2c1 — 401 or error code 40005 count as success.
        if (e.statusCode == 401 || e.code == 40005) {
          handleEvent(const Deregistered());
        } else {
          handleEvent(DeregistrationFailed(_toErrorInfo(e)));
        }
      } catch (e) {
        handleEvent(DeregistrationFailed(_toErrorInfo(e)));
      }
    }());
  }

  /// RSH3c2a + RSH8c — adopts a registration result: sets and persists the
  /// deviceIdentityToken, and adopts the response clientId when the local
  /// one is unset (RSH8f).
  void _adoptRegistration(GotDeviceRegistration event) {
    if (event.deviceIdentityToken != null) {
      device.deviceIdentityToken = event.deviceIdentityToken;
      unawaited(
        device.persistIdentityToken().catchError((Object e) {
          _logger.error('Failed to persist push device identity token', {
            'error': e.toString(),
          });
        }),
      );
    }
    _adoptResponseClientId(event.clientId);
  }

  /// RSH8f — sets the device clientId from a registration or sync response
  /// when the local one is unset.
  void _adoptResponseClientId(String? responseClientId) {
    if (responseClientId == null ||
        responseClientId.isEmpty ||
        device.clientId != null) {
      return;
    }
    device.clientId = responseClientId;
    unawaited(
      device.persistClientId().catchError((Object e) {
        _logger.error('Failed to persist push device clientId', {
          'error': e.toString(),
        });
      }),
    );
  }

  /// RSH3g2a — clears the registration and resets the device identity after
  /// deregistration.
  void _handleDeregistered() {
    unawaited(() async {
      try {
        await device.clearRegistration();
        await device.resetIdentity();
      } catch (e) {
        _logger.error('Failed to clear persisted push device state', {
          'error': e.toString(),
        });
      }
    }());
  }

  ErrorInfo _toErrorInfo(Object error) {
    if (error is AblyException) {
      return error.errorInfo ??
          ErrorInfo(message: error.message, code: 40000, statusCode: 400);
    }
    if (error is ErrorInfo) return error;
    return ErrorInfo(message: error.toString(), code: 40000, statusCode: 400);
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// A state of the Activation State Machine. `processEvent` is synchronous
/// (RSH5); it returns the next state, or null when no transition is defined
/// for the event (RSH4 queues it).
abstract class _ActivationState {
  const _ActivationState();

  String get name;

  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  );
}

/// RSH3a.
class _NotActivated extends _ActivationState {
  const _NotActivated();

  @override
  String get name => 'NotActivated';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledDeactivate():
        if (machine.device.deviceIdentityToken != null) {
          // RSH3a1c — same as RSH3d2.
          machine._deregister();
          return _WaitingForDeregistration(previous: this);
        }
        // RSH3a1d — same as RSH3g2 (there is no registration to clear;
        // the id/secret identity is retained).
        machine._resolveDeactivate();
        return const _NotActivated();
      case CalledActivate():
        if (machine.device.deviceIdentityToken != null) {
          // RSH3a2a — validate the existing registration.
          return machine._validateRegistration(byActivate: true);
        }
        // RSH3a2b — the id/secret pair is generated and persisted as part
        // of the LocalDevice load, which has completed before any event is
        // processed (RSH3h).
        if (machine.device.recipient != null) {
          // RSH3a2c.
          machine.handleEvent(const GotPushDeviceDetails());
        } else {
          // RSH3a2d.
          machine._getPushDeviceDetails();
        }
        // RSH3a2e.
        return const _WaitingForPushDeviceDetails();
      case GotPushDeviceDetails():
        // RSH3a3a — consume.
        return const _NotActivated();
      default:
        return null;
    }
  }
}

/// RSH3b.
class _WaitingForPushDeviceDetails extends _ActivationState {
  const _WaitingForPushDeviceDetails();

  @override
  String get name => 'WaitingForPushDeviceDetails';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledActivate():
        // RSH3b1a.
        return this;
      case CalledDeactivate():
        // RSH3b2.
        machine._resolveDeactivate();
        return const _NotActivated();
      case GotPushDeviceDetails():
        // RSH3b3.
        if (machine.registerCallback != null) {
          machine._callCustomRegisterer(isNew: true);
        } else {
          machine._register();
        }
        return const _WaitingForDeviceRegistration();
      case GettingPushDeviceDetailsFailed(:final reason):
        // RSH3b4.
        machine._resolveActivate(reason);
        return const _NotActivated();
      default:
        return null;
    }
  }
}

/// RSH3c.
class _WaitingForDeviceRegistration extends _ActivationState {
  const _WaitingForDeviceRegistration();

  @override
  String get name => 'WaitingForDeviceRegistration';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledActivate():
        // RSH3c1a.
        return this;
      case GotDeviceRegistration():
        // RSH3c2.
        machine._adoptRegistration(event);
        machine._resolveActivate();
        return const _WaitingForNewPushDeviceDetails(recovered: false);
      case GettingDeviceRegistrationFailed(:final reason):
        // RSH3c3.
        machine._resolveActivate(reason);
        return const _NotActivated();
      default:
        return null;
    }
  }
}

/// RSH3d.
///
/// [recovered] is set when this state was recovered from persisted state by
/// a fresh machine (RSH3h): the registration then needs validation, so
/// `CalledActivate` performs RSH3a2a and `GotPushDeviceDetails` performs the
/// RSH3d3 sync against the recovered registration.
class _WaitingForNewPushDeviceDetails extends _ActivationState {
  const _WaitingForNewPushDeviceDetails({required this.recovered});

  final bool recovered;

  @override
  String get name => 'WaitingForNewPushDeviceDetails';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledActivate():
        if (recovered) {
          // RSH3a2a — a fresh machine over a persisted registration
          // validates it.
          return machine._validateRegistration(byActivate: true);
        }
        // RSH3d1.
        machine._resolveActivate();
        return this;
      case CalledDeactivate():
        // RSH3d2.
        machine._deregister();
        return _WaitingForDeregistration(previous: this);
      case GotPushDeviceDetails():
        // RSH3d3.
        return machine._syncRegistration(byActivate: false);
      default:
        return null;
    }
  }
}

/// RSH3e.
class _WaitingForRegistrationSync extends _ActivationState {
  const _WaitingForRegistrationSync({required this.byActivate});

  /// Whether the machine is in this state as a result of a `CalledActivate`
  /// event (RSH3e1, RSH3e2b, RSH3e3c).
  final bool byActivate;

  @override
  String get name => 'WaitingForRegistrationSync';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledActivate():
        if (byActivate) {
          // RSH3e1 carve-out: no transition defined — queue (RSH4).
          return null;
        }
        // RSH3e1a.
        machine._resolveActivate();
        return const _WaitingForRegistrationSync(byActivate: true);
      case RegistrationSynced(:final clientId):
        machine._adoptResponseClientId(clientId);
        machine._clientIdChanged = false;
        if (byActivate) {
          // RSH3e2b.
          machine._resolveActivate();
        } else {
          // RSH3e2c.
          machine.updatedCallback?.call(null);
        }
        // RSH3e2a.
        return const _WaitingForNewPushDeviceDetails(recovered: false);
      case SyncRegistrationFailed(:final reason):
        if (byActivate) {
          // RSH3e3c.
          machine._resolveActivate(reason);
        } else {
          // RSH3e3d.
          machine.updatedCallback?.call(reason);
        }
        // RSH3e3b.
        return const _AfterRegistrationSyncFailed();
      default:
        return null;
    }
  }
}

/// RSH3f.
class _AfterRegistrationSyncFailed extends _ActivationState {
  const _AfterRegistrationSyncFailed();

  @override
  String get name => 'AfterRegistrationSyncFailed';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledActivate():
        // RSH3f1a — same as RSH3a2a.
        return machine._validateRegistration(byActivate: true);
      case GotPushDeviceDetails():
        // RSH3f1a — same as RSH3a2a.
        return machine._validateRegistration(byActivate: false);
      case CalledDeactivate():
        // RSH3f2a — same as RSH3d2.
        machine._deregister();
        return _WaitingForDeregistration(previous: this);
      default:
        return null;
    }
  }
}

/// RSH3g.
class _WaitingForDeregistration extends _ActivationState {
  const _WaitingForDeregistration({required this.previous});

  /// The state to roll back to on `DeregistrationFailed` (RSH3g3b).
  final _ActivationState previous;

  @override
  String get name => 'WaitingForDeregistration';

  @override
  _ActivationState? processEvent(
    ActivationStateMachine machine,
    ActivationEvent event,
  ) {
    switch (event) {
      case CalledDeactivate():
        // RSH3g1a.
        return this;
      case Deregistered():
        // RSH3g2.
        machine._handleDeregistered();
        machine._resolveDeactivate();
        return const _NotActivated();
      case DeregistrationFailed(:final reason):
        // RSH3g3.
        machine._resolveDeactivate(reason);
        return previous;
      default:
        return null;
    }
  }
}

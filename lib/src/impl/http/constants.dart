/// HTTP constants for Ably REST API.
library;

/// Ably protocol version.
const String ablyProtocolVersion = '5';

/// SDK version.
const String sdkVersion = '0.2.0';

/// Default Ably agent string.
const String ablyAgent = 'ably-pubsub-dart/$sdkVersion ably-pubsub-device';

/// Default primary domain per REC1a specification.
const String defaultPrimaryDomain = 'main.realtime.ably.net';

/// Default fallback hosts (REC2c1).
const List<String> defaultFallbackHosts = [
  'main.a.fallback.ably-realtime.com',
  'main.b.fallback.ably-realtime.com',
  'main.c.fallback.ably-realtime.com',
  'main.d.fallback.ably-realtime.com',
  'main.e.fallback.ably-realtime.com',
];

/// Fallback domain suffixes for nonprod routing policy (REC2c3).
///
/// Full domain is `[id].[suffix]`, e.g. `myapp.a.fallback.ably-realtime-nonprod.com`.
const List<String> nonprodFallbackSuffixes = [
  'a.fallback.ably-realtime-nonprod.com',
  'b.fallback.ably-realtime-nonprod.com',
  'c.fallback.ably-realtime-nonprod.com',
  'd.fallback.ably-realtime-nonprod.com',
  'e.fallback.ably-realtime-nonprod.com',
];

/// Fallback domain suffixes for production routing policy (REC2c4/REC2c5).
///
/// Full domain is `[id].[suffix]`, e.g. `sandbox.a.fallback.ably-realtime.com`.
const List<String> productionFallbackSuffixes = [
  'a.fallback.ably-realtime.com',
  'b.fallback.ably-realtime.com',
  'c.fallback.ably-realtime.com',
  'd.fallback.ably-realtime.com',
  'e.fallback.ably-realtime.com',
];

/// Default connectivity check URL (REC3a).
const String defaultConnectivityCheckUrl =
    'https://internet-up.ably-realtime.com/is-the-internet-up.txt';

/// HTTP header names.
class HttpHeaders {
  static const String contentType = 'Content-Type';
  static const String accept = 'Accept';
  static const String authorization = 'Authorization';
  static const String ablyVersion = 'X-Ably-Version';
  static const String ablyAgent = 'Ably-Agent';
  static const String ablyErrorCode = 'X-Ably-Errorcode';
  static const String ablyErrorMessage = 'X-Ably-Errormessage';
  static const String link = 'Link';
}

/// Content types.
class ContentTypes {
  static const String json = 'application/json';
  static const String msgpack = 'application/x-msgpack';
}

# Dart Test Implementation Completion Status

This matrix lists all spec items from the [Ably features spec](https://sdk.ably.com/builds/ably/specification/main/features/) and indicates which have a Dart test implementation.

Each Dart test corresponds to a UTS test spec. Where the UTS spec exists but the Dart test does not, the gap is noted.

**Legend:**
- **Yes** — Dart test exists covering this item
- **Partial** — some sub-items covered, others not
- *blank* — no Dart test exists
- **N/A** — not applicable or deleted spec item

**Test counts:** 537 passing, 0 failing, 1 skipped (`dart test`, the unit suite). The integration and proxy suites (`dart test -P integration`, `-P proxy`) need a sandbox app and the local test proxy.

---

## Specification and Protocol Versions

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| CSV1–CSV2 | Specification & protocol versions | Information only |

## Client Library Endpoint Configuration

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| REC1 | Primary domain determination (REC1a–REC1b4) | Partial — `realtime/unit/connection/fallback_hosts_test.dart` |
| REC2 | Fallback domains determination (REC2a2–REC2c4) | Partial — `realtime/unit/connection/fallback_hosts_test.dart` (RTN17h) |
| REC3 | Connectivity check URL (REC3a–REC3b) | Partial — `realtime/unit/connection/fallback_hosts_test.dart` (RTN17j) |

---

## REST (HTTP) Layer

The SDK does not ship a standalone REST client. The spec items below are still
implemented and are reached through the Realtime client: `time()`, `stats()`,
`request()`, channel `history()`/`status()`/`getMessage()`/message
update-delete-append, presence `history()`, and push admin.

Spec items that only exist on a REST client (`RestClient`, `RestChannel`,
`RestPresence`, batch publish and batch presence) are marked N/A.

### HTTP client (RSC)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSC1 | Constructor options (RSC1a–RSC1c) | N/A — no REST client; see RTC1 |
| RSC2 | Logger default | |
| RSC3 | Log level configuration | |
| RSC4 | Custom logger | |
| RSC5 | Auth object attribute | |
| RSC6 | Stats function (RSC6a–RSC6b4) | |
| RSC7 | HTTP request headers (RSC7a–RSC7d7) | |
| RSC8 | Protocol support (RSC8a–RSC8e2) | |
| RSC9 | Auth usage for authentication | Information only |
| RSC10 | Token error retry handling | |
| RSC13 | Connection and request timeouts | |
| RSC15 | Host fallback behaviour (RSC15a–RSC15n) | Partial — `realtime/unit/connection/fallback_hosts_test.dart` (RTN17e) |
| RSC16 | Time function | |
| RSC17 | ClientId attribute | |
| RSC18 | TLS configuration | |
| RSC19 | Request function (RSC19a–RSC19f1) | |
| RSC20 | Deprecated exception reporting (RSC20a–RSC20f) | N/A |
| RSC21 | Push object attribute | |
| RSC22 | BatchPublish (RSC22a–RSC22d) | N/A — REST-only API, not implemented |
| RSC23 | Deleted | N/A |
| RSC24 | BatchPresence | N/A — REST-only API, not implemented |
| RSC25 | Request endpoint | |
| RSC26 | CreateWrapperSDKProxy (RSC26a–RSC26c) | |

### Auth

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSA1 | Basic Auth requires HTTPS | |
| RSA2 | Basic Auth default | |
| RSA3 | Token Auth support (RSA3a–RSA3d) | |
| RSA4 | Token Auth selection logic (RSA4a–RSA4g) | Partial — `realtime/unit/auth/connection_auth_test.dart`, `realtime/unit/auth/token_expiry_non_renewable_test.dart`, `realtime/unit/auth/auth_callback_errors_test.dart` |
| RSA5 | TTL for tokens | |
| RSA6 | Capability JSON | |
| RSA7 | ClientId and authenticated clients (RSA7a–RSA7e2) | Partial — `realtime/integration/auth_test.dart` |
| RSA8 | RequestToken function (RSA8a–RSA8g) | Partial — `realtime/unit/auth/connection_auth_test.dart` |
| RSA9 | CreateTokenRequest (RSA9a–RSA9i) | |
| RSA10 | Authorize function (RSA10a–RSA10l) | Partial — `realtime/unit/auth/realtime_authorize_test.dart` (RTC8) |
| RSA11 | Base64 encoded API key | |
| RSA12 | Auth#clientId attribute (RSA12a–RSA12b) | |
| RSA14 | Error when token auth selected without token | |
| RSA15 | ClientId validation (RSA15a–RSA15c) | Partial — `realtime/integration/auth_test.dart` |
| RSA16 | TokenDetails attribute (RSA16a–RSA16d) | |
| RSA17 | RevokeTokens (RSA17a–RSA17g) | |

### Channels (REST)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSN1–RSN4 | REST channels collection (RSN1–RSN4c) | N/A — REST-only API, not implemented |

### RestChannel

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSL1–RSL15 | RestChannel publish, history, status, message get/update/delete | N/A — REST-only API, not implemented. The equivalent Realtime operations are covered under RTL. |

### RestPresence

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSP1–RSP5 | RestPresence get, history, decoding | N/A — REST-only API, not implemented. Realtime presence history is covered under RTP. |

### RestAnnotations

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSAN1–RSAN3 | Annotations publish/delete/get | Partial — `realtime/unit/channels/channel_annotations_test.dart` |

### Plugins

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| PC1–PC5 | Plugin architecture, VCDiff, Objects | Partial — `realtime/unit/channels/channel_delta_decoding_test.dart`, `realtime/integration/delta_decoding_test.dart` |
| PT1–PT2 | PluginType enum | |
| VD1–VD2 | VCDiffDecoder | Partial — mock at `test/helpers/mock_vcdiff.dart` |

### Encryption

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSE1 | Crypto::getDefaultParams (RSE1a–RSE1e) | |
| RSE2 | Crypto::generateRandomKey (RSE2a–RSE2b) | |

### Forwards Compatibility (REST)

| Spec item | Description | Dart test |
|

---

## Realtime Client Library

### PubSubClient

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTC1 | ClientOptions (RTC1a–RTC1f1) | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC2 | Connection object attribute | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC3 | Channels object attribute | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC4 | Auth object attribute (RTC4a) | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC5 | Stats function (RTC5a–RTC5b) | |
| RTC6 | Time function (RTC6a) | |
| RTC7 | Uses configured timeouts | Yes — `realtime/unit/client/realtime_timeouts_test.dart` |
| RTC8 | Authorize function for realtime (RTC8a–RTC8c) | Yes — `realtime/unit/auth/realtime_authorize_test.dart`, `realtime/integration/auth_test.dart` |
| RTC9 | Request function | |
| RTC10–RTC11 | Deleted | N/A |
| RTC12 | Same constructors as RestClient | N/A — no REST client |
| RTC13 | Push object attribute | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC14 | CreateWrapperSDKProxy (RTC14a–RTC14c) | |
| RTC15 | Connect function (RTC15a) | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC16 | Close function (RTC16a) | Yes — `realtime/unit/client/pubsub_client_test.dart` |
| RTC17 | ClientId attribute (RTC17a) | Yes — `realtime/unit/client/pubsub_client_test.dart` |

### Connection

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTN1 | Uses websocket connection | Information only |
| RTN2 | Default host and query string params (RTN2a–RTN2g) | Partial — `realtime/unit/auth/connection_auth_test.dart` covers RTN2e |
| RTN3 | AutoConnect option | Yes — `realtime/unit/connection/auto_connect_test.dart` |
| RTN4 | Connection event emission (RTN4a–RTN4i) | Partial — `realtime/integration/connection_lifecycle_test.dart`, `realtime/unit/connection/update_events_test.dart` |
| RTN5 | Concurrency test (50+ clients) | |
| RTN6 | Successful connection definition | Information only |
| RTN7 | ACK and NACK handling (RTN7a–RTN7e) | Yes — `realtime/unit/channels/channel_publish_test.dart` |
| RTN8 | Connection#id attribute (RTN8a–RTN8c) | Yes — `realtime/unit/connection/connection_id_key_test.dart` |
| RTN9 | Connection#key attribute (RTN9a–RTN9c) | Yes — `realtime/unit/connection/connection_id_key_test.dart` |
| RTN11 | Connect function (RTN11a–RTN11f) | Partial — `realtime/integration/connection_lifecycle_test.dart`, `realtime/unit/connection/error_reason_test.dart` |
| RTN12 | Close function (RTN12a–RTN12f) | Partial — `realtime/integration/connection_lifecycle_test.dart` |
| RTN13 | Ping function (RTN13a–RTN13e) | Yes — `realtime/unit/connection/connection_ping_test.dart` |
| RTN14 | Connection opening failures (RTN14a–RTN14g) | Yes — `realtime/unit/connection/connection_open_failures_test.dart`, `realtime/integration/proxy/connection_open_failures_test.dart` |
| RTN15 | Connection failures when CONNECTED (RTN15a–RTN15j) | Yes — `realtime/unit/connection/connection_failures_test.dart`, `realtime/integration/proxy/connection_resume_test.dart` |
| RTN16 | Connection recovery (RTN16a–RTN16m1) | Yes — `realtime/unit/connection/connection_recovery_test.dart`, `realtime/integration/proxy/connection_resume_test.dart` |
| RTN17 | Domain selection and fallback (RTN17a–RTN17j) | Yes — `realtime/unit/connection/fallback_hosts_test.dart` |
| RTN19 | Transport state side effects (RTN19a–RTN19b) | Yes — `realtime/unit/channels/channel_publish_test.dart` |
| RTN20 | OS network change handling (RTN20a–RTN20c) | Yes — `realtime/unit/connection/network_change_test.dart` |
| RTN21 | ConnectionDetails override defaults | Partial — `realtime/unit/connection/update_events_test.dart`, `realtime/integration/connection_lifecycle_test.dart` |
| RTN22 | Re-authentication request handling (RTN22a) | Yes — `realtime/unit/connection/server_initiated_reauth_test.dart` |
| RTN23 | Heartbeats (RTN23a–RTN23b) | Yes — `realtime/unit/connection/heartbeat_test.dart`, `realtime/integration/proxy/heartbeat_test.dart` |
| RTN24 | UPDATE event on CONNECTED while connected | Yes — `realtime/unit/connection/update_events_test.dart` |
| RTN25 | Connection#errorReason attribute | Yes — `realtime/unit/connection/error_reason_test.dart` |
| RTN26 | Connection#whenState function (RTN26a–RTN26b) | Yes — `realtime/unit/connection/when_state_test.dart` |
| RTN27 | Connection state machine (RTN27a–RTN27h) | Partial — `realtime/unit/auth/connection_auth_test.dart` covers RTN27b |

### Channels (Realtime)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTS1 | Channels collection accessible via PubSubClient | Yes — `realtime/unit/channels/channels_collection_test.dart` |
| RTS2 | Methods to check existence and iterate | Yes — `realtime/unit/channels/channels_collection_test.dart` |
| RTS3 | Get function (RTS3a–RTS3c1) | Yes — `realtime/unit/channels/channels_collection_test.dart`, `realtime/unit/channels/channel_options_test.dart` |
| RTS4 | Release function (RTS4a) | Yes — `realtime/unit/channels/channels_collection_test.dart` |
| RTS5 | GetDerived function (RTS5a–RTS5a2) | Yes — `realtime/unit/channels/channel_options_test.dart` |

### RealtimeChannel

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTL1 | Message and presence processing | Information only |
| RTL2 | Channel event emission (RTL2a–RTL2i) | Yes — `realtime/unit/channels/channel_state_events_test.dart` |
| RTL3 | Connection state side effects (RTL3a–RTL3e) | Yes — `realtime/unit/channels/channel_connection_state_test.dart` |
| RTL4 | Attach function (RTL4a–RTL4m) | Yes — `realtime/unit/channels/channel_attach_test.dart`, `realtime/integration/proxy/channel_faults_test.dart` |
| RTL5 | Detach function (RTL5a–RTL5l) | Yes — `realtime/unit/channels/channel_detach_test.dart`, `realtime/integration/proxy/channel_faults_test.dart` |
| RTL6 | Publish function (RTL6a–RTL6k) | Yes — `realtime/unit/channels/channel_publish_test.dart` |
| RTL7 | Subscribe function (RTL7a–RTL7h) | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |
| RTL8 | Unsubscribe function (RTL8a–RTL8c) | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |
| RTL9 | Presence attribute (RTL9a) | Yes — `realtime/unit/presence/realtime_presence_channel_state_test.dart` |
| RTL10 | History function (RTL10a–RTL10d) | Yes — `realtime/unit/channels/channel_history_test.dart`, `realtime/integration/channel_history_test.dart` |
| RTL11 | Channel state effect on presence (RTL11a) | Yes — `realtime/unit/presence/realtime_presence_channel_state_test.dart` |
| RTL12 | Additional ATTACHED message handling | Yes — `realtime/unit/channels/channel_additional_attached_test.dart` |
| RTL13 | Server-initiated DETACHED handling (RTL13a–RTL13c) | Yes — `realtime/unit/channels/channel_server_initiated_detach_test.dart`, `realtime/integration/proxy/channel_faults_test.dart` |
| RTL14 | ERROR message handling | Yes — `realtime/unit/channels/channel_error_test.dart`, `realtime/integration/proxy/channel_faults_test.dart` |
| RTL15 | Channel#properties attribute (RTL15a–RTL15b1) | Yes — `realtime/unit/channels/channel_properties_test.dart` |
| RTL16 | SetOptions function (RTL16a) | Yes — `realtime/unit/channels/channel_options_test.dart` |
| RTL17 | No messages outside ATTACHED state | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |
| RTL18 | Vcdiff decoding failure recovery (RTL18a–RTL18c) | Yes — `realtime/unit/channels/channel_delta_decoding_test.dart`, `realtime/integration/delta_decoding_test.dart` |
| RTL19 | Base payload storage for vcdiff (RTL19a–RTL19c) | Yes — `realtime/unit/channels/channel_delta_decoding_test.dart`, `realtime/integration/delta_decoding_test.dart` |
| RTL20 | Last message ID storage | Yes — `realtime/unit/channels/channel_delta_decoding_test.dart`, `realtime/integration/delta_decoding_test.dart` |
| RTL21 | Message ordering in arrays | Yes — `realtime/unit/channels/channel_delta_decoding_test.dart` |
| RTL22 | Message filtering (RTL22a–RTL22d) | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |
| RTL23 | Name attribute | Yes — `realtime/unit/channels/channel_attributes_test.dart` |
| RTL24 | ErrorReason attribute | Yes — `realtime/unit/channels/channel_attributes_test.dart` |
| RTL25 | WhenState function (RTL25a–RTL25b) | Yes — `realtime/unit/channels/channel_when_state_test.dart` |
| RTL26 | Annotations attribute | Yes — `realtime/unit/channels/channel_annotations_test.dart` |
| RTL27 | Objects attribute (RTL27a–RTL27b) | |
| RTL28 | GetMessage function | Yes — `realtime/unit/channels/channel_get_message_test.dart`, `realtime/integration/mutable_messages_test.dart` |
| RTL31 | GetMessageVersions function | Yes — `realtime/unit/channels/channel_message_versions_test.dart`, `realtime/integration/mutable_messages_test.dart` |
| RTL32 | UpdateMessage/DeleteMessage/AppendMessage (RTL32a–RTL32e) | Yes — `realtime/unit/channels/channel_update_delete_message_test.dart`, `realtime/integration/mutable_messages_test.dart` |

### RealtimePresence

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTP1 | HAS_PRESENCE flag and SYNC | Yes — `realtime/unit/presence/realtime_presence_channel_state_test.dart` |
| RTP2 | PresenceMap maintenance (RTP2a–RTP2h2) | Yes — `realtime/unit/presence/presence_map_test.dart` |
| RTP4 | Large member count test | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP5 | Channel state side effects (RTP5a–RTP5f) | Yes — `realtime/unit/presence/realtime_presence_channel_state_test.dart` |
| RTP6 | Subscribe function (RTP6a–RTP6e) | Yes — `realtime/unit/presence/realtime_presence_subscribe_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP7 | Unsubscribe function (RTP7a–RTP7c) | Yes — `realtime/unit/presence/realtime_presence_subscribe_test.dart` |
| RTP8 | Enter function (RTP8a–RTP8j) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP9 | Update function (RTP9a–RTP9e) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP10 | Leave function (RTP10a–RTP10e) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP11 | Get function (RTP11a–RTP11d) | Yes — `realtime/unit/presence/realtime_presence_get_test.dart`, `realtime/integration/presence_lifecycle_test.dart` |
| RTP12 | History function (RTP12a–RTP12d) | Yes — `realtime/unit/presence/realtime_presence_history_test.dart` |
| RTP13 | SyncComplete attribute | Yes — `realtime/unit/presence/realtime_presence_channel_state_test.dart` |
| RTP14 | EnterClient function (RTP14a–RTP14d) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart` |
| RTP15 | EnterClient/UpdateClient/LeaveClient (RTP15a–RTP15f) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart` |
| RTP16 | Connection state conditions (RTP16a–RTP16c) | Yes — `realtime/unit/presence/realtime_presence_enter_test.dart` |
| RTP17 | Internal PresenceMap (RTP17a–RTP17j) | Partial — `realtime/unit/presence/local_presence_map_test.dart`, `realtime/unit/presence/realtime_presence_reentry_test.dart` |
| RTP18 | Server-initiated sync (RTP18a–RTP18c) | Yes — `realtime/unit/presence/presence_sync_test.dart` |
| RTP19 | PresenceMap cleanup on sync (RTP19a) | Yes — `realtime/unit/presence/presence_sync_test.dart`, `realtime/unit/presence/realtime_presence_channel_state_test.dart` |

### RealtimeAnnotations

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTAN1–RTAN5 | Annotations publish/delete/get/subscribe/unsubscribe | Yes — `realtime/unit/channels/channel_annotations_test.dart`, `realtime/integration/mutable_messages_test.dart` |

### LiveObjects

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTO1–RTO19 | LiveObjects internal data structures | |
| RTLO3–RTLO5 | Object-level operations and subscriptions | |
| RTLC1–RTLC14 | LiveCounter | |
| RTLM1–RTLM25 | LiveMap | |
| PO1–PO11 | Path Objects API | |

### EventEmitter

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTE1–RTE6 | EventEmitter interface (on/once/off/emit) | |

### Incremental Backoff and Jitter

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTB1 | Retry timeout calculation (RTB1a–RTB1b) | Yes — `realtime/unit/connection/backoff_jitter_test.dart` |

### Forwards Compatibility (Realtime)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTF1 | Robustness principle | Yes — `realtime/unit/connection/forwards_compatibility_test.dart` |

### Wrapper SDK Proxy Client

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| WP1–WP7 | Wrapper SDK proxy client | |

---

## Push Notifications

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSH1 | Push#admin object (RSH1a–RSH1c5) | |
| RSH2 | Platform-specific push operations (RSH2a–RSH2e) | |
| RSH3 | Activation state machine (RSH3a–RSH3g3) | |
| RSH4–RSH5 | Event queueing and sequential handling | |
| RSH6 | Push device authentication (RSH6a–RSH6b) | |
| RSH7 | Push channels (RSH7a–RSH7e) | |
| RSH8 | LocalDevice (RSH8a–RSH8k2) | |

---

## Types

### Data Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| TM1–TM8 | Message (TM1–TM8a1) | Partial — `realtime/unit/channels/message_field_population_test.dart` |
| DE1–DE2 | DeltaExtras | |
| TP1–TP5 | PresenceMessage | Partial — `realtime/unit/presence/presence_map_test.dart` |
| OM1–OM5 | ObjectMessage | |
| TAN1–TAN3 | Annotation | Partial — `realtime/unit/channels/channel_annotations_test.dart` |
| TR1–TR4 | ProtocolMessage | |
| TG1–TG7 | PaginatedResult | Partial — `realtime/unit/channels/channel_history_test.dart` |
| HP1–HP8 | HttpPaginatedResponse | |
| TE1–TE6 | TokenRequest | |
| TD1–TD7 | TokenDetails | Partial — `realtime/unit/auth/connection_auth_test.dart` |
| TN1–TN3 | Token string | |
| AD1–AD2 | AuthDetails | |
| TS1–TS14 | Stats | |
| TI1–TI5 | ErrorInfo | Partial — `realtime/unit/connection/connection_failures_test.dart` |
| TA1–TA5 | ConnectionStateChange | |
| TH1–TH6 | ChannelStateChange | Yes — `realtime/unit/channels/channel_state_events_test.dart` |
| TC1–TC2 | Capability | |
| CD1–CD2 | ConnectionDetails | |
| CP1–CP2 | ChannelProperties | |
| CHD1–CHD2, CHS1–CHS2, CHO1–CHO2, CHM1–CHM2 | Channel status types | Partial — `realtime/unit/channels/channel_history_test.dart` (RSL8) |
| BAR1–BAR2 | BatchResult | N/A — REST-only type, not implemented |
| PBR1–PBR2 | PublishResult | Yes — `realtime/unit/channels/channel_publish_test.dart` |
| UDR1–UDR2 | UpdateDeleteResult | Yes — `realtime/unit/channels/channel_update_delete_message_test.dart` (RTL32d) |
| TRT1–TRT2, TRS1–TRS2, TRF1–TRF2 | TokenRevocation types | |
| MFI1–MFI2 | MessageFilter | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |

### Option Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| TO1–TO3 | ClientOptions | Partial — `realtime/unit/client/pubsub_client_test.dart` |
| TK1–TK6 | TokenParams | |
| AO1–AO2 | AuthOptions | |
| TB1–TB4 | ChannelOptions | Yes — `realtime/unit/channels/channel_options_test.dart` |
| DO1–DO2 | DeriveOptions | Yes — `realtime/unit/channels/channel_options_test.dart` |
| TZ1–TZ2 | CipherParams | |
| CO1–CO2 | CipherParamOptions | |

### Push Notification Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| PCS1–PCS5 | PushChannelSubscription | |
| PCD1–PCD7 | DeviceDetails | |
| PCP1–PCP4 | DevicePushDetails | |

### Client Library Introspection

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| CR1–CR3 | ClientInformation | |

### Client Library Defaults

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| DF1 | Default values (DF1a–DF1b) | |

---

## Proxy Integration Tests

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTN14a–RTN14g | Connection open failures via proxy | Yes — `realtime/integration/proxy/connection_open_failures_test.dart` |
| RTN15a–RTN15h3 | Connection resume via proxy | Yes — `realtime/integration/proxy/connection_resume_test.dart` |
| RTN23a | Heartbeat via proxy | Yes — `realtime/integration/proxy/heartbeat_test.dart` |
| RTL4f, RTL4h, RTL5f, RTL13a, RTL14 | Channel faults via proxy | Yes — `realtime/integration/proxy/channel_faults_test.dart` |
| RTL6 | Publish and history through proxy | Yes — `realtime/integration/proxy/publish_history_test.dart` |
| RTN22 | Auth reauth via proxy | Yes — `realtime/integration/proxy/auth_reauth_test.dart` |
| RTP17 | Presence reentry via proxy | Yes — `realtime/integration/proxy/presence_reentry_test.dart` |

---

## Summary

The REST client was removed from this SDK, and with it the test suite that
covered the shared HTTP layer, auth, push admin and the data types. Those spec
items are still implemented — they are reached through the Realtime client —
but they are now only covered incidentally by Realtime tests, which is what the
rows below record.

| Area | Spec groups | With Dart test | Coverage |
|------|-------------|----------------|----------|
| **Endpoint config** (REC) | 3 | 3 | Partial |
| **HTTP client** (RSC) | 18 | 1 | Minimal |
| **Auth** (RSA) | 15 | 5 | Partial |
| **REST channels** (RSN) | 1 | — | N/A — removed |
| **REST channel** (RSL) | 13 | — | N/A — removed |
| **REST presence** (RSP) | 5 | — | N/A — removed |
| **REST encryption** (RSE) | 2 | 0 | None |
| **REST annotations** (RSAN) | 3 | 1 | Partial |
| **Realtime client** (RTC) | 14 | 10 | Mostly |
| **Connection** (RTN) | 23 | 18 | Mostly |
| **Realtime channels** (RTS) | 5 | 5 | Full |
| **Realtime channel** (RTL) | 28 | 26 | Mostly |
| **Realtime presence** (RTP) | 15 | 15 | Full |
| **Realtime annotations** (RTAN) | 5 | 5 | Full |
| **LiveObjects** (RTO/RTLO/RTLC/RTLM/PO) | 53 | 0 | None |
| **EventEmitter** (RTE) | 6 | 0 | None |
| **Backoff/jitter** (RTB) | 1 | 1 | Full |
| **Wrapper SDK** (WP) | 7 | 0 | None |
| **Push notifications** (RSH) | 8 | 0 | None |
| **Plugins** (PC/PT/VD) | 3 | 2 | Partial |
| **Data types** | 30 | 7 | Partial |
| **Option types** | 8 | 1 | Minimal |
| **Push types** | 3 | 0 | None |
| **Introspection** (CR) | 1 | 0 | None |
| **Defaults** (DF) | 1 | 0 | None |
| **Compatibility** (RSF/RTF) | 2 | 2 | Full |

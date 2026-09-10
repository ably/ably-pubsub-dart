# Dart Test Implementation Completion Status

This matrix lists all spec items from the [Ably features spec](https://sdk.ably.com/builds/ably/specification/main/features/) and indicates which have a Dart test implementation.

Each Dart test corresponds to a UTS test spec. Where the UTS spec exists but the Dart test does not, the gap is noted.

**Legend:**
- **Yes** — Dart test exists covering this item
- **Partial** — some sub-items covered, others not
- *blank* — no Dart test exists
- **N/A** — not applicable or deleted spec item

**Test counts:** 1113 passing, 0 failing, 24 skipped (integration tests requiring sandbox/proxy)

---

## Specification and Protocol Versions

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| CSV1–CSV2 | Specification & protocol versions | Information only |

## Client Library Endpoint Configuration

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| REC1 | Primary domain determination (REC1a–REC1b4) | Yes — `rest/unit/client/fallback_test.dart` |
| REC2 | Fallback domains determination (REC2a2–REC2c4) | Yes — `rest/unit/client/fallback_test.dart` |
| REC3 | Connectivity check URL (REC3a–REC3b) | Yes — `rest/unit/client/fallback_test.dart` |

---

## REST Client Library

### RestClient

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSC1 | Constructor options (RSC1a–RSC1c) | Yes — `rest/unit/client/client_options_test.dart` |
| RSC2 | Logger default | Yes — `rest/unit/client/logging_test.dart` |
| RSC3 | Log level configuration | Yes — `rest/unit/client/logging_test.dart` |
| RSC4 | Custom logger | Yes — `rest/unit/client/logging_test.dart` |
| RSC5 | Auth object attribute | Yes — `rest/unit/client/rest_client_test.dart` |
| RSC6 | Stats function (RSC6a–RSC6b4) | Yes — `rest/unit/client/stats_test.dart`, `rest/integration/time_stats_test.dart` |
| RSC7 | HTTP request headers (RSC7a–RSC7d7) | Yes — `rest/unit/client/rest_client_test.dart` |
| RSC8 | Protocol support (RSC8a–RSC8e2) | Yes — `rest/unit/client/rest_client_test.dart` |
| RSC9 | Auth usage for authentication | Information only |
| RSC10 | Token error retry handling | Yes — `rest/unit/auth/token_renewal_rsc10_test.dart`, `rest/unit/auth/token_renewal_test.dart`, `rest/integration/auth_test.dart` |
| RSC13 | Connection and request timeouts | Yes — `rest/unit/client/rest_client_test.dart` |
| RSC15 | Host fallback behaviour (RSC15a–RSC15n) | Yes — `rest/unit/client/fallback_test.dart` |
| RSC16 | Time function | Yes — `rest/unit/client/time_test.dart`, `rest/integration/time_stats_test.dart` |
| RSC17 | ClientId attribute | Yes — `rest/unit/client/rest_client_test.dart` |
| RSC18 | TLS configuration | Yes — `rest/unit/client/rest_client_test.dart`, `rest/unit/client/time_test.dart` |
| RSC19 | Request function (RSC19a–RSC19f1) | Yes — `rest/unit/client/request_test.dart` |
| RSC20 | Deprecated exception reporting (RSC20a–RSC20f) | N/A |
| RSC21 | Push object attribute | Yes — `rest/unit/push/push_admin_publish_test.dart` |
| RSC22 | BatchPublish (RSC22a–RSC22d) | Yes — `rest/unit/client/batch_publish_test.dart` |
| RSC23 | Deleted | N/A |
| RSC24 | BatchPresence | Yes — `rest/unit/batch_presence_test.dart`, `rest/integration/batch_presence_test.dart` |
| RSC25 | Request endpoint | Yes — `rest/unit/client/request_endpoint_test.dart` |
| RSC26 | CreateWrapperSDKProxy (RSC26a–RSC26c) | |

### Auth

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSA1 | Basic Auth requires HTTPS | Yes — `rest/unit/auth/auth_scheme_test.dart` |
| RSA2 | Basic Auth default | Yes — `rest/unit/auth/auth_scheme_test.dart` |
| RSA3 | Token Auth support (RSA3a–RSA3d) | Yes — `rest/unit/auth/auth_scheme_test.dart` |
| RSA4 | Token Auth selection logic (RSA4a–RSA4g) | Yes — `rest/unit/auth/auth_scheme_test.dart`, `rest/unit/auth/token_renewal_test.dart`, `realtime/unit/auth/connection_auth_test.dart`, `realtime/unit/auth/token_expiry_non_renewable_test.dart`, `realtime/unit/auth/auth_callback_errors_test.dart` |
| RSA5 | TTL for tokens | Yes — `rest/unit/auth/token_request_params_test.dart`, `rest/integration/auth_test.dart` |
| RSA6 | Capability JSON | Yes — `rest/unit/auth/token_request_params_test.dart`, `rest/integration/auth_test.dart` |
| RSA7 | ClientId and authenticated clients (RSA7a–RSA7e2) | Partial — `rest/unit/auth/client_id_test.dart`, `realtime/integration/auth_test.dart` |
| RSA8 | RequestToken function (RSA8a–RSA8g) | Partial — `rest/unit/auth/auth_callback_test.dart`, `realtime/unit/auth/connection_auth_test.dart`, `rest/integration/auth_test.dart` |
| RSA9 | CreateTokenRequest (RSA9a–RSA9i) | Partial — `rest/integration/auth_test.dart` |
| RSA10 | Authorize function (RSA10a–RSA10l) | Yes — `rest/unit/auth/authorize_test.dart` |
| RSA11 | Base64 encoded API key | Yes — `rest/unit/auth/auth_scheme_test.dart` |
| RSA12 | Auth#clientId attribute (RSA12a–RSA12b) | Yes — `rest/unit/auth/client_id_test.dart` |
| RSA14 | Error when token auth selected without token | Yes — `rest/unit/auth/token_renewal_test.dart`, `rest/integration/auth_test.dart` |
| RSA15 | ClientId validation (RSA15a–RSA15c) | Yes — `rest/unit/auth/client_id_test.dart`, `realtime/integration/auth_test.dart` |
| RSA16 | TokenDetails attribute (RSA16a–RSA16d) | Yes — `rest/unit/auth/token_details_test.dart` |
| RSA17 | RevokeTokens (RSA17a–RSA17g) | Yes — `rest/unit/auth/revoke_tokens_test.dart`, `rest/integration/revoke_tokens_test.dart` |

### Channels (REST)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSN1–RSN4 | REST channels collection (RSN1–RSN4c) | Yes — `rest/unit/channel/channels_collection_test.dart` |

### RestChannel

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSL1 | Publish function (RSL1a–RSL1n1) | Yes — `rest/unit/channel/publish_test.dart`, `rest/unit/channel/publish_result_test.dart`, `rest/integration/publish_test.dart`, `rest/integration/mutable_messages_test.dart` |
| RSL1k | Idempotent publishing (RSL1k1–RSL1k5) | Yes — `rest/unit/channel/idempotency_test.dart` |
| RSL2 | History function (RSL2a–RSL2b3) | Yes — `rest/unit/channel/history_test.dart`, `rest/integration/history_test.dart` |
| RSL3 | Presence attribute | Yes — `rest/unit/presence/rest_presence_test.dart` |
| RSL4 | Message encoding (RSL4a–RSL4d4) | Yes — `rest/unit/encoding/message_encoding_test.dart` |
| RSL5 | Message encryption (RSL5a–RSL5c) | |
| RSL6 | Message decoding (RSL6a–RSL6b) | Yes — `rest/unit/encoding/message_encoding_test.dart` |
| RSL7 | SetOptions function | Yes — `rest/unit/channel/rest_channel_attributes_test.dart` |
| RSL8 | Status function (RSL8a) | Yes — `rest/unit/channel/rest_channel_attributes_test.dart` |
| RSL9 | Name attribute | Yes — `rest/unit/channel/rest_channel_attributes_test.dart` |
| RSL10 | Annotations attribute | Yes — `rest/unit/channel/annotations_test.dart` |
| RSL11 | GetMessage function (RSL11a–RSL11c) | Yes — `rest/unit/channel/get_message_test.dart`, `rest/integration/mutable_messages_test.dart` |
| RSL14 | GetMessageVersions (RSL14a–RSL14c) | Yes — `rest/unit/channel/message_versions_test.dart`, `rest/integration/mutable_messages_test.dart` |
| RSL15 | UpdateMessage/DeleteMessage/AppendMessage (RSL15a–RSL15f) | Yes — `rest/unit/channel/update_delete_message_test.dart`, `rest/integration/mutable_messages_test.dart` |

### Plugins

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| PC1–PC5 | Plugin architecture, VCDiff, Objects | Partial — `realtime/unit/channels/channel_delta_decoding_test.dart`, `realtime/integration/delta_decoding_test.dart` |
| PT1–PT2 | PluginType enum | |
| VD1–VD2 | VCDiffDecoder | Partial — mock at `test/helpers/mock_vcdiff.dart` |

### RestPresence

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSP1 | Associated with single channel | Yes — `rest/unit/presence/rest_presence_test.dart`, `rest/integration/presence_test.dart` |
| RSP2 | No presence registration via REST | Information only |
| RSP3 | Get function (RSP3a–RSP3a3) | Yes — `rest/unit/presence/rest_presence_test.dart`, `rest/integration/presence_test.dart` |
| RSP4 | History function (RSP4a–RSP4b3) | Yes — `rest/unit/presence/rest_presence_test.dart`, `rest/integration/presence_test.dart` |
| RSP5 | Presence message decoding | Yes — `rest/unit/presence/rest_presence_test.dart`, `rest/integration/presence_test.dart` |

### Encryption

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSE1 | Crypto::getDefaultParams (RSE1a–RSE1e) | |
| RSE2 | Crypto::generateRandomKey (RSE2a–RSE2b) | |

### RestAnnotations

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSAN1–RSAN3 | Annotations publish/delete/get | Yes — `rest/unit/channel/annotations_test.dart`, `rest/integration/mutable_messages_test.dart` |

### Forwards Compatibility (REST)

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RSF1 | Robustness principle | Yes — `realtime/unit/connection/forwards_compatibility_test.dart` |

---

## Realtime Client Library

### RealtimeClient

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| RTC1 | ClientOptions (RTC1a–RTC1f1) | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC2 | Connection object attribute | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC3 | Channels object attribute | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC4 | Auth object attribute (RTC4a) | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC5 | Stats function (RTC5a–RTC5b) | Yes — shared via `rest/unit/client/stats_test.dart` (BaseClientImpl) |
| RTC6 | Time function (RTC6a) | Yes — shared via `rest/unit/client/time_test.dart` (BaseClientImpl) |
| RTC7 | Uses configured timeouts | Yes — `realtime/unit/client/realtime_timeouts_test.dart` |
| RTC8 | Authorize function for realtime (RTC8a–RTC8c) | Yes — `realtime/unit/auth/realtime_authorize_test.dart`, `realtime/integration/auth_test.dart` |
| RTC9 | Request function | Yes — shared via `rest/unit/client/request_test.dart` (BaseClientImpl) |
| RTC10–RTC11 | Deleted | N/A |
| RTC12 | Same constructors as RestClient | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC13 | Push object attribute | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC14 | CreateWrapperSDKProxy (RTC14a–RTC14c) | |
| RTC15 | Connect function (RTC15a) | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC16 | Close function (RTC16a) | Yes — `realtime/unit/client/realtime_client_test.dart` |
| RTC17 | ClientId attribute (RTC17a) | Yes — `realtime/unit/client/realtime_client_test.dart` |

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
| RTS1 | Channels collection accessible via RealtimeClient | Yes — `realtime/unit/channels/channels_collection_test.dart` |
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
| RSH1 | Push#admin object (RSH1a–RSH1c5) | Yes — `rest/unit/push/push_admin_publish_test.dart`, `rest/unit/push/push_device_registrations_test.dart`, `rest/unit/push/push_channel_subscriptions_test.dart`, `rest/integration/push_admin_test.dart` |
| RSH2 | Platform-specific push operations (RSH2a–RSH2f3) | Yes — `rest/unit/push/push_activation_state_machine_test.dart`, `rest/unit/push/push_update_token_test.dart`, `rest/integration/push_activation_test.dart` |
| RSH3 | Activation state machine (RSH3a–RSH3h) | Yes — `rest/unit/push/push_activation_state_machine_test.dart`, `rest/unit/push/push_activation_persistence_test.dart`, `rest/integration/push_activation_test.dart` |
| RSH4–RSH5 | Event queueing and sequential handling | Yes — `rest/unit/push/push_activation_event_queue_test.dart`, `rest/unit/push/push_update_token_test.dart` |
| RSH6 | Push device authentication (RSH6a–RSH6b) | Yes — `rest/unit/push/push_device_auth_test.dart`, `rest/unit/push/push_activation_state_machine_test.dart` |
| RSH7 | Push channels (RSH7a–RSH7e) | Yes — `rest/unit/push/push_channels_test.dart`, `rest/integration/push_channels_test.dart` |
| RSH8 | LocalDevice (RSH8a–RSH8l4) | Yes — `rest/unit/push/local_device_test.dart`, `rest/unit/push/push_activation_persistence_test.dart`, `rest/unit/push/push_update_token_test.dart` |

---

## Types

### Data Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| TM1–TM8 | Message (TM1–TM8a1) | Partial — `rest/unit/types/message_types_test.dart`, `rest/unit/types/mutable_message_types_test.dart`, `realtime/unit/channels/message_field_population_test.dart` |
| DE1–DE2 | DeltaExtras | |
| TP1–TP5 | PresenceMessage | Yes — `rest/unit/types/presence_message_types_test.dart` |
| OM1–OM5 | ObjectMessage | |
| TAN1–TAN3 | Annotation | Yes — `rest/unit/types/mutable_message_types_test.dart` |
| TR1–TR4 | ProtocolMessage | |
| TG1–TG7 | PaginatedResult | Yes — `rest/unit/types/paginated_result_test.dart`, `rest/integration/pagination_test.dart` |
| HP1–HP8 | HttpPaginatedResponse | Yes — `rest/unit/client/request_test.dart` |
| TE1–TE6 | TokenRequest | Yes — `rest/unit/types/token_types_test.dart` |
| TD1–TD7 | TokenDetails | Yes — `rest/unit/types/token_types_test.dart` |
| TN1–TN3 | Token string | |
| AD1–AD2 | AuthDetails | |
| TS1–TS14 | Stats | |
| TI1–TI5 | ErrorInfo | Yes — `rest/unit/types/error_types_test.dart` |
| TA1–TA5 | ConnectionStateChange | |
| TH1–TH6 | ChannelStateChange | Yes — `realtime/unit/channels/channel_state_events_test.dart` |
| TC1–TC2 | Capability | |
| CD1–CD2 | ConnectionDetails | |
| CP1–CP2 | ChannelProperties | |
| CHD1–CHD2, CHS1–CHS2, CHO1–CHO2, CHM1–CHM2 | Channel status types | Yes — `rest/unit/channel/rest_channel_attributes_test.dart` |
| BAR1–BAR2 | BatchResult | Partial — `rest/unit/batch_presence_test.dart` |
| PBR1–PBR2 | PublishResult | Yes — `realtime/unit/channels/channel_publish_test.dart` |
| UDR1–UDR2 | UpdateDeleteResult | Yes — `rest/unit/types/mutable_message_types_test.dart` |
| TRT1–TRT2, TRS1–TRS2, TRF1–TRF2 | TokenRevocation types | Yes — `rest/unit/auth/revoke_tokens_test.dart` |
| MFI1–MFI2 | MessageFilter | Yes — `realtime/unit/channels/channel_subscribe_test.dart` |

### Option Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| TO1–TO3 | ClientOptions | Yes — `rest/unit/types/options_types_test.dart` |
| TK1–TK6 | TokenParams | Yes — `rest/unit/types/token_types_test.dart` |
| AO1–AO2 | AuthOptions | Yes — `rest/unit/types/options_types_test.dart` |
| TB1–TB4 | ChannelOptions | Yes — `realtime/unit/channels/channel_options_test.dart` |
| DO1–DO2 | DeriveOptions | Yes — `realtime/unit/channels/channel_options_test.dart` |
| TZ1–TZ2 | CipherParams | |
| CO1–CO2 | CipherParamOptions | |

### Push Notification Types

| Spec item | Description | Dart test |
|-----------|-------------|-----------|
| PCS1–PCS5 | PushChannelSubscription | Yes — `rest/unit/types/push_types_test.dart` |
| PCD1–PCD7 | DeviceDetails | Yes — `rest/unit/types/push_types_test.dart` |
| PCP1–PCP4 | DevicePushDetails | Partial — `rest/unit/types/push_types_test.dart`, `rest/unit/push/push_update_token_test.dart` (PCP3a token variants) |
| PDT1–PDT4 | PushDeviceToken | Yes — `rest/unit/push/push_update_token_test.dart` |

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
| RSC10, RSC15a | REST faults via proxy | Yes — `realtime/integration/proxy/rest_faults_test.dart` |
| RTN22 | Auth reauth via proxy | Yes — `realtime/integration/proxy/auth_reauth_test.dart` |
| RTP17 | Presence reentry via proxy | Yes — `realtime/integration/proxy/presence_reentry_test.dart` |

---

## Summary

| Area | Spec groups | With Dart test | Coverage |
|------|-------------|----------------|----------|
| **Endpoint config** (REC) | 3 | 3 | Full |
| **REST client** (RSC) | 18 | 16 | Mostly |
| **REST auth** (RSA) | 15 | 15 | Full |
| **REST channels** (RSN) | 1 | 1 | Full |
| **REST channel** (RSL) | 13 | 12 | Mostly |
| **REST presence** (RSP) | 5 | 4 | Mostly |
| **REST encryption** (RSE) | 2 | 0 | None |
| **REST annotations** (RSAN) | 3 | 3 | Full |
| **Realtime client** (RTC) | 14 | 13 | Mostly |
| **Connection** (RTN) | 23 | 18 | Mostly |
| **Realtime channels** (RTS) | 5 | 5 | Full |
| **Realtime channel** (RTL) | 28 | 26 | Mostly |
| **Realtime presence** (RTP) | 15 | 15 | Full |
| **Realtime annotations** (RTAN) | 5 | 5 | Full |
| **LiveObjects** (RTO/RTLO/RTLC/RTLM/PO) | 53 | 0 | None |
| **EventEmitter** (RTE) | 6 | 0 | None |
| **Backoff/jitter** (RTB) | 1 | 1 | Full |
| **Wrapper SDK** (WP) | 7 | 0 | None |
| **Push notifications** (RSH) | 8 | 8 | Full |
| **Plugins** (PC/PT/VD) | 3 | 2 | Partial |
| **Data types** | 30 | 14 | Partial |
| **Option types** | 8 | 5 | Partial |
| **Push types** | 4 | 4 | Full |
| **Introspection** (CR) | 1 | 0 | None |
| **Defaults** (DF) | 1 | 0 | None |
| **Compatibility** (RSF/RTF) | 2 | 2 | Full |

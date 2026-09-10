/// Ably SDK for Dart.
///
/// This library provides a pure Dart implementation of the Ably REST and Realtime APIs.
library ably;

// Authentication
export 'src/auth/auth.dart';
export 'src/auth/auth_options.dart';
export 'src/auth/client_options.dart';
export 'src/auth/token_details.dart';
export 'src/auth/token_params.dart';
export 'src/auth/token_request.dart';
export 'src/auth/token_revocation.dart';

// REST
export 'src/rest/rest_client.dart';

// Realtime
export 'src/realtime/realtime_client.dart';
export 'src/realtime/connection.dart';
export 'src/realtime/connection_state.dart';
export 'src/realtime/connection_event.dart';
export 'src/realtime/connection_state_change.dart';
export 'src/realtime/realtime_channels.dart';
export 'src/realtime/realtime_channel.dart';
export 'src/realtime/realtime_channel_options.dart';
export 'src/realtime/channel_mode.dart';
export 'src/realtime/derive_options.dart';
export 'src/realtime/channel_state.dart';
export 'src/realtime/channel_event.dart';
export 'src/realtime/channel_state_change.dart';
export 'src/realtime/protocol_message.dart';
export 'src/realtime/publish_result.dart';
export 'src/realtime/realtime_annotations.dart';
export 'src/realtime/realtime_presence.dart';

// Channels
export 'src/channels/channel_details.dart';
export 'src/channels/channels.dart';
export 'src/channels/rest_annotations.dart';
export 'src/channels/rest_channel.dart';
export 'src/channels/rest_channel_options.dart';
export 'src/channels/realtime_history_params.dart';
export 'src/channels/rest_history_params.dart';

// Presence
export 'src/presence/rest_presence.dart';
export 'src/presence/rest_presence_params.dart';
export 'src/presence/presence_action.dart';

// Messages
export 'src/message/message.dart';
export 'src/message/message_action.dart';
export 'src/message/message_annotations.dart';
export 'src/message/message_operation.dart';
export 'src/message/message_version.dart';
export 'src/message/presence_message.dart';
export 'src/message/message_extras.dart';
export 'src/message/message_filter.dart';
export 'src/message/delta_extras.dart';
export 'src/message/annotation.dart';
export 'src/message/annotation_action.dart';
export 'src/message/update_delete_result.dart';

// Push
export 'src/push/push.dart';
export 'src/push/push_admin.dart';
export 'src/push/push_channel.dart';
export 'src/push/push_device_registrations.dart';
export 'src/push/push_channel_subscriptions.dart';
export 'src/push/device_details.dart';
export 'src/push/device_push_details.dart';
export 'src/push/local_device.dart';
export 'src/push/push_channel_subscription.dart';
export 'src/push/push_platform.dart';

// Stats
export 'src/stats/stats.dart';

// Batch operations
export 'src/batch/batch_presence_result.dart';
export 'src/batch/batch_publish_spec.dart';
export 'src/batch/batch_result.dart';

// Pagination
export 'src/pagination/paginated_result.dart';
export 'src/pagination/http_paginated_response.dart';

// Errors
export 'src/error/error_info.dart';
export 'src/error/ably_exception.dart';
export 'src/error/error_codes.dart';

// Crypto
export 'src/crypto/crypto.dart';
export 'src/crypto/cipher_params.dart';

// Plugins
export 'src/plugin/vcdiff_decoder.dart';

// Logging
export 'src/logging/log_level.dart';
export 'src/logging/log_handler.dart';
export 'src/logging/logger.dart';

// Internal types exposed for testing
export 'src/impl/presence_map.dart';
export 'src/realtime/timer_manager.dart';
export 'src/realtime/websocket_client.dart';

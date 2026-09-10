import 'dart:convert';
import 'dart:math';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import '../auth/client_options.dart';
import '../channels/channel_details.dart';
import '../channels/rest_annotations.dart';
import '../channels/rest_channel.dart';
import '../channels/rest_channel_options.dart';
import '../channels/rest_history_params.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../logging/logger.dart';
import '../message/message.dart';
import '../message/message_action.dart';
import '../message/message_operation.dart';
import '../message/update_delete_result.dart';
import '../pagination/paginated_result.dart';
import '../presence/rest_presence.dart';
import '../push/local_device.dart';
import '../push/push_channel.dart';
import '../realtime/publish_result.dart';
import 'channel_rest_api.dart';
import 'http/http_client.dart';
import 'push_channel_impl.dart';
import 'rest_annotations_impl.dart';
import 'rest_presence_impl.dart';

/// Implementation of RestChannel.
class RestChannelImpl implements RestChannel {
  RestChannelImpl({
    required String name,
    required AblyHttpClient httpClient,
    required ClientOptions options,
    required Logger logger,
    required LocalDevice? Function() getDevice,
    Future<LocalDevice?> Function()? loadDevice,
    RestChannelOptions? channelOptions,
  })  : _name = name,
        _httpClient = httpClient,
        _options = options,
        _logger = logger,
        _random = Random() {
    _restApi = ChannelRestApi(channelName: name, httpClient: httpClient);
    _presence = RestPresenceImpl(
      channelName: name,
      httpClient: httpClient,
      logger: logger,
    );
    _annotations = RestAnnotationsImpl(
      channelName: name,
      httpClient: httpClient,
      options: options,
      logger: logger,
      restApi: _restApi,
    );
    _push = PushChannelImpl(
      channelName: name,
      httpClient: httpClient,
      getDevice: getDevice,
      loadDevice: loadDevice,
    );
  }

  final String _name;
  final AblyHttpClient _httpClient;
  final ClientOptions _options;
  final Logger _logger;
  late final ChannelRestApi _restApi;
  late final RestPresenceImpl _presence;
  late final RestAnnotationsImpl _annotations;
  late final PushChannelImpl _push;
  final Random _random;

  @override
  String get name => _name;

  @override
  RestPresence get presence => _presence;

  @override
  RestAnnotations get annotations => _annotations;

  @override
  PushChannel get push => _push;

  @override
  Future<PublishResult> publish({
    Message? message,
    List<Message>? messages,
    String? name,
    Object? data,
    Map<String, String>? params,
  }) async {
    // Build the list of messages to publish
    final messagesToPublish = <Message>[];

    if (message != null) {
      messagesToPublish.add(message);
    } else if (messages != null) {
      messagesToPublish.addAll(messages);
    } else {
      // RSL1e: Accept null name and/or null data
      messagesToPublish.add(Message(name: name, data: data));
    }

    _logger.info('publish() called', {
      'channel': _name,
      'messageCount': messagesToPublish.length,
    });

    // Encode messages for publishing
    final encodedMessages = messagesToPublish.map(_encodeMessage).toList();

    // Check message size
    final int wireSize;
    if (_options.useBinaryProtocol) {
      wireSize = msgpack.serialize(encodedMessages).length;
    } else {
      wireSize = json.encode(encodedMessages).length;
    }
    if (wireSize > _options.maxMessageSize) {
      _logger.error('Message exceeds maxMessageSize', {
        'size': wireSize,
        'max': _options.maxMessageSize,
      });
      throw AblyException(
        message: 'Message size exceeds maximum',
        errorInfo: ErrorInfo(
          message:
              'Message size $wireSize exceeds maximum ${_options.maxMessageSize}',
          code: 40009,
          statusCode: 400,
        ),
      );
    }

    // Add idempotency IDs if enabled (RSL1k)
    if (_options.idempotentRestPublishing) {
      _logger.debug('Added idempotent IDs');
      _addIdempotencyIds(encodedMessages);
    }

    // Publish - always send as array (RSL1b/RSL1c)
    final path = '/channels/${Uri.encodeComponent(_name)}/messages';
    final response = await _httpClient.request(
      'POST',
      path,
      queryParams: params,
      body: encodedMessages,
    );

    // RSL1n: Parse and return PublishResult
    if (response.body is Map<String, dynamic>) {
      return PublishResult.fromMap(response.body as Map<String, dynamic>);
    }
    return const PublishResult(serials: []);
  }

  @override
  Future<Message> getMessage(String serial) async {
    _validateSerial(serial);
    _logger.info('getMessage() called', {
      'channel': _name,
      'serial': serial,
    });
    return _restApi.getMessage(serial);
  }

  @override
  Future<PaginatedResult<Message>> getMessageVersions(
    String serial, {
    Map<String, String>? params,
  }) async {
    _validateSerial(serial);
    _logger.info('getMessageVersions() called', {
      'channel': _name,
      'serial': serial,
    });
    return _restApi.getMessageVersions(serial, params);
  }

  @override
  Future<UpdateDeleteResult> updateMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageUpdate,
      operation: operation,
      params: params,
    );
  }

  @override
  Future<UpdateDeleteResult> deleteMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageDelete,
      operation: operation,
      params: params,
    );
  }

  @override
  Future<UpdateDeleteResult> appendMessage(
    Message message, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) {
    return _mutateMessage(
      message,
      MessageAction.messageAppend,
      operation: operation,
      params: params,
    );
  }

  /// Shared implementation for updateMessage, deleteMessage, appendMessage.
  ///
  /// RSL15c: Builds a new wire body — does NOT mutate the user's Message.
  Future<UpdateDeleteResult> _mutateMessage(
    Message message,
    MessageAction action, {
    MessageOperation? operation,
    Map<String, String>? params,
  }) async {
    _validateSerial(message.serial);

    _logger.info('${action.name}() called', {
      'channel': _name,
      'serial': message.serial,
    });

    // RSL15c: Build new map, do not mutate the user's message
    final body = <String, dynamic>{};
    body['action'] = action.toInt();

    if (message.name != null) body['name'] = message.name;
    if (message.clientId != null) body['clientId'] = message.clientId;
    if (message.extras != null) body['extras'] = message.extras!.toMap();

    // RSL15d: Encode data per RSL4
    if (message.data != null) {
      Message.encodeDataInto(
        body,
        message.data!,
        message.encoding,
        useBinaryProtocol: _options.useBinaryProtocol,
      );
    }

    // RSL15b7: Include version only when operation is provided
    if (operation != null) {
      body['version'] = operation.toMap();
    }

    return _restApi.patchMessage(message.serial!, body, params: params);
  }

  /// Validates that a serial is non-null and non-empty.
  ///
  /// Spec: RSL11a, RSL15a
  void _validateSerial(String? serial) {
    if (serial == null || serial.isEmpty) {
      throw const AblyException(
        message: 'Message serial is required',
        errorInfo: ErrorInfo(
          message: 'Message serial is required',
          code: 40003,
          statusCode: 400,
        ),
      );
    }
  }

  Map<String, dynamic> _encodeMessage(Message msg) {
    final encoded = <String, dynamic>{};

    if (msg.id != null) encoded['id'] = msg.id;
    if (msg.name != null) encoded['name'] = msg.name;
    if (msg.clientId != null) encoded['clientId'] = msg.clientId;
    if (msg.extras != null) encoded['extras'] = msg.extras!.toMap();

    if (msg.data != null) {
      Message.encodeDataInto(
        encoded,
        msg.data!,
        msg.encoding,
        useBinaryProtocol: _options.useBinaryProtocol,
      );
    }

    return encoded;
  }

  void _addIdempotencyIds(List<Map<String, dynamic>> messages) {
    // Generate a new base key for each publish call (RSL1k3)
    final baseKey = _generateBaseIdempotencyKey();

    for (var i = 0; i < messages.length; i++) {
      if (messages[i]['id'] == null) {
        // RSL1k1: Use 0-based index within the batch, matching ably-js
        messages[i]['id'] = '$baseKey:$i';
      }
    }
  }

  String _generateBaseIdempotencyKey() {
    // Generate a random base64 string (RSL1k1)
    final bytes = List<int>.generate(9, (_) => _random.nextInt(256));
    return base64.encode(bytes);
  }

  @override
  Future<PaginatedResult<Message>> history([RestHistoryParams? params]) {
    _logger.info('history() called', {'channel': _name});
    return _restApi.history(params);
  }

  @override
  Future<ChannelDetails> status() {
    _logger.info('status() called', {'channel': _name});
    return _restApi.status();
  }

  @override
  Future<void> setOptions(RestChannelOptions options) async {
    _logger.info('setOptions() called', {'channel': _name});
    // Note: Encryption setup would go here if implemented
  }
}

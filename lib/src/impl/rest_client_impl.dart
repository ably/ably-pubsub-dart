import 'dart:math';

import '../batch/batch_presence_result.dart';
import '../batch/batch_publish_spec.dart';
import '../batch/batch_result.dart';
import '../channels/channels.dart';
import '../error/ably_exception.dart';
import '../error/error_info.dart';
import '../push/push.dart';
import '../rest/rest_client.dart';
import 'base_client_impl.dart';
import 'push_admin_impl.dart';
import 'rest_channels_impl.dart';

/// Implementation of the Rest client.
class RestClientImpl extends BaseClientImpl implements RestClient {
  /// Creates a Rest client with the given options.
  RestClientImpl({
    required super.options,
    super.httpClient,
  }) {
    _channels = RestChannelsImpl(
      httpClient: ablyHttpClient,
      options: options,
      logger: logger,
      getDevice: () => device,
      loadDevice: () async =>
          options.pushPlatform != null ? await getDevice() : device,
    );
    _push = PushImpl(
      httpClient: ablyHttpClient,
      logger: logger,
      options: options,
      getActivation: () => pushActivation,
      getDevice: () => device,
    );
  }

  late final RestChannelsImpl _channels;
  late final PushImpl _push;

  @override
  RestChannels get channels => _channels;

  @override
  Push get push => _push;

  @override
  Future<List<BatchResult>> batchPublish(
    Object spec, {
    Map<String, String>? params,
  }) async {
    // Convert spec to list format
    List<Map<String, dynamic>> specList;
    final bool singleSpec;

    if (spec is BatchPublishSpec) {
      singleSpec = true;
      specList = [_prepareBatchSpec(spec)];
    } else if (spec is List<BatchPublishSpec>) {
      singleSpec = false;
      specList = spec.map(_prepareBatchSpec).toList();
    } else {
      throw ArgumentError(
        'spec must be a BatchPublishSpec or List<BatchPublishSpec>',
      );
    }

    // Build request body
    final body = singleSpec ? specList.first : specList;

    // Make the request
    final response = await ablyHttpClient.request(
      'POST',
      '/messages',
      queryParams: params,
      body: body,
    );

    // Parse results
    final responseBody = response.body;
    List<Map<String, dynamic>> resultList;

    if (responseBody is List) {
      resultList = responseBody.cast<Map<String, dynamic>>();
    } else if (responseBody is Map) {
      resultList = [responseBody as Map<String, dynamic>];
    } else {
      return [];
    }

    return resultList.map(BatchResult.fromMap).toList();
  }

  Map<String, dynamic> _prepareBatchSpec(BatchPublishSpec spec) {
    final specMap = spec.toMap();

    // RSC22d: Generate idempotent IDs if enabled
    if (options.idempotentRestPublishing) {
      final messages = specMap['messages'] as List;
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i] as Map<String, dynamic>;
        // Only generate ID if not already set (RSC22d3)
        if (message['id'] == null) {
          message['id'] = _generateIdempotentId(i);
        }
      }
    }

    return specMap;
  }

  String _generateIdempotentId(int index) {
    // Generate a unique base ID for this batch
    final random = Random();
    final bytes = List<int>.generate(9, (_) => random.nextInt(256));
    final base = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$base:$index';
  }

  @override
  Future<BatchPresenceResponse> batchPresence(List<String> channels) async {
    final channelsParam = channels.join(',');

    final response = await ablyHttpClient.request(
      'GET',
      '/presence',
      queryParams: {'channels': channelsParam},
      returnErrorBody: true,
    );

    final responseBody = response.body;

    // With X-Ably-Version >= 3, the server returns a BatchResult envelope:
    // {successCount, failureCount, results: [...]}
    if (responseBody is Map<String, dynamic> &&
        responseBody.containsKey('results')) {
      return BatchPresenceResponse.fromMap(responseBody);
    }

    // Server error — propagate as exception
    if (responseBody is Map<String, dynamic> &&
        responseBody.containsKey('error')) {
      final errorInfo =
          ErrorInfo.fromMap(responseBody['error'] as Map<String, dynamic>);
      throw AblyException.fromErrorInfo(errorInfo);
    }

    throw AblyException(
      message: 'Unexpected batchPresence response format',
      errorInfo: ErrorInfo(
        message: 'Unexpected response body type: ${responseBody.runtimeType}',
        statusCode: response.statusCode,
        code: 50000,
      ),
    );
  }

  @override
  Future<void> close() async {
    ablyHttpClient.close();
  }
}

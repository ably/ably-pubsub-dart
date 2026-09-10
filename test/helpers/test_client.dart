import 'package:ably_pubsub_device/src/impl/base_client_impl.dart';

/// A minimal client for testing shared BaseClientImpl functionality
/// (time, stats, request, etc.) without needing a full Rest or Realtime client.
class TestClient extends BaseClientImpl {
  TestClient({
    required super.options,
    super.httpClient,
  });
}

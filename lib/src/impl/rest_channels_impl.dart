import '../auth/client_options.dart';
import '../channels/channels.dart';
import '../channels/rest_channel.dart';
import '../channels/rest_channel_options.dart';
import '../logging/logger.dart';
import '../push/local_device.dart';
import 'http/http_client.dart';
import 'rest_channel_impl.dart';

/// Implementation of RestChannels.
class RestChannelsImpl extends Iterable<RestChannel> implements RestChannels {
  RestChannelsImpl({
    required AblyHttpClient httpClient,
    required ClientOptions options,
    required Logger logger,
    required LocalDevice? Function() getDevice,
    Future<LocalDevice?> Function()? loadDevice,
  })  : _httpClient = httpClient,
        _options = options,
        _logger = logger,
        _getDevice = getDevice,
        _loadDevice = loadDevice;

  final AblyHttpClient _httpClient;
  final ClientOptions _options;
  final Logger _logger;
  final LocalDevice? Function() _getDevice;
  final Future<LocalDevice?> Function()? _loadDevice;
  final Map<String, RestChannelImpl> _channels = {};

  @override
  RestChannel get(String name, [RestChannelOptions? options]) {
    var channel = _channels[name];
    if (channel == null) {
      channel = RestChannelImpl(
        name: name,
        httpClient: _httpClient,
        options: _options,
        logger: _logger,
        getDevice: _getDevice,
        loadDevice: _loadDevice,
        channelOptions: options,
      );
      _channels[name] = channel;
      _logger.debug('Channel created', {'channel': name});
    } else if (options != null) {
      // Update options on existing channel
      channel.setOptions(options);
    }
    return channel;
  }

  @override
  RestChannel operator [](String name) => get(name);

  @override
  bool exists(String name) => _channels.containsKey(name);

  @override
  void release(String name) {
    _channels.remove(name);
  }

  @override
  Iterator<RestChannel> get iterator => _channels.values.iterator;
}

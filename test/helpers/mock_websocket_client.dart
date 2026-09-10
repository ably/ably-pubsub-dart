import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ably_pubsub_device/src/error/error_info.dart';
import 'package:ably_pubsub_device/src/realtime/protocol_message.dart';
import 'package:ably_pubsub_device/src/realtime/websocket_client.dart';

/// Callback for handling connection attempts in the mock WebSocket client.
typedef ConnectionAttemptHandler = void Function(
  PendingWebSocketConnection connection,
);

/// Callback for handling messages from client.
typedef MessageFromClientHandler = void Function(ProtocolMessage message);

/// Callback for handling raw text WebSocket data frames.
///
/// Called with the JSON string that would be sent over the wire.
/// This is called in addition to [MessageFromClientHandler].
typedef TextDataFrameHandler = void Function(String text);

/// Mock WebSocket client that implements the UTS specification pattern.
///
/// This mock supports both handler-based and awaitable patterns for maximum
/// test flexibility. It provides complete control over connection outcomes
/// and message flow.
///
/// Example with handlers:
/// ```dart
/// final mock = MockWebSocketClient(
///   onConnectionAttempt: (conn) {
///     if (shouldFail) {
///       conn.respondWithRefused();
///     } else {
///       conn.respondWithSuccess(CONNECTED_MESSAGE);
///     }
///   },
/// );
/// ```
///
/// Example with await pattern:
/// ```dart
/// final mock = MockWebSocketClient();
/// final connFuture = mock.awaitConnectionAttempt();
///
/// // Trigger connection in background
/// client.connect();
///
/// // Wait for and respond to connection
/// final conn = await connFuture;
/// expect(conn.url.host, 'main.realtime.ably.net');
/// conn.respondWithSuccess(CONNECTED_MESSAGE);
/// ```
class MockWebSocketClient implements WebSocketClient {
  MockWebSocketClient({
    this.onConnectionAttempt,
    this.onMessageFromClient,
    this.onTextDataFrame,
  });

  /// Handler called for each connection attempt.
  final ConnectionAttemptHandler? onConnectionAttempt;

  /// Handler called for each message from client.
  final MessageFromClientHandler? onMessageFromClient;

  /// Handler called with raw JSON text for each message sent by client.
  ///
  /// This simulates access to the raw WebSocket text data frame before
  /// decoding. Called in addition to [onMessageFromClient].
  final TextDataFrameHandler? onTextDataFrame;

  /// Event timeline (UTS requirement) - chronological sequence of all events.
  final List<MockEvent> events = [];

  /// The currently active connection (null if not connected).
  MockWebSocketConnection? activeConnection;

  /// Streams for awaitable patterns.
  final StreamController<PendingWebSocketConnection> _connectionAttempts =
      StreamController<PendingWebSocketConnection>.broadcast();
  final StreamController<ProtocolMessage> _messagesFromClient =
      StreamController<ProtocolMessage>.broadcast();
  final StreamController<ClientCloseEvent> _clientCloses =
      StreamController<ClientCloseEvent>.broadcast();

  /// Awaits the next connection attempt (UTS pattern).
  ///
  /// This must be called BEFORE initiating the connection to ensure
  /// the listener is set up.
  Future<PendingWebSocketConnection> awaitConnectionAttempt({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _connectionAttempts.stream.first.timeout(timeout);
  }

  /// Awaits the next message from client (UTS pattern).
  Future<ProtocolMessage> awaitNextMessageFromClient({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _messagesFromClient.stream.first.timeout(timeout);
  }

  /// Awaits client-initiated WebSocket close (UTS pattern).
  ///
  /// Returns a [ClientCloseEvent] containing the close code and reason.
  Future<ClientCloseEvent> awaitClientClose({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _clientCloses.stream.first.timeout(timeout);
  }

  /// Returns all client close events from the event timeline.
  List<MockEvent> get clientCloseEvents =>
      events.where((e) => e.type == MockEventType.clientClose).toList();

  /// Initiates a WebSocket connection.
  ///
  /// The [listener] is stored and will receive all events from the connection.
  /// The returned future completes when the test code responds via
  /// PendingWebSocketConnection methods.
  @override
  Future<MockWebSocketConnection> connect(
    Uri url,
    WebSocketListener listener, {
    bool useBinaryProtocol = false,
  }) async {
    final pendingConnection = PendingWebSocketConnection._(
      url: url,
      protocol: useBinaryProtocol ? 'msgpack' : 'json',
      timestamp: DateTime.now(),
      listener: listener,
      onMessageFromClient: onMessageFromClient,
      onTextDataFrame: onTextDataFrame,
      mockClient: this,
    );

    // Record event
    events.add(
      MockEvent(
        type: MockEventType.connectionAttempt,
        timestamp: DateTime.now(),
        data: pendingConnection,
      ),
    );

    // Emit for awaitable pattern
    if (!_connectionAttempts.isClosed) {
      _connectionAttempts.add(pendingConnection);
    }

    // Call handler if provided
    if (onConnectionAttempt != null) {
      onConnectionAttempt!(pendingConnection);
    }

    // Wait for test to respond
    final connection = await pendingConnection._completer.future;

    // Forward messages from client to stream
    connection._messagesFromClient.stream.listen((msg) {
      if (!_messagesFromClient.isClosed) {
        _messagesFromClient.add(msg);
      }
    });

    // Forward client close events to the parent's stream (for awaitClientClose)
    // Note: The event is already recorded directly in close() method
    connection._clientCloses.stream.listen((closeEvent) {
      // Forward to parent's stream for await pattern
      if (!_clientCloses.isClosed) {
        _clientCloses.add(closeEvent);
      }
    });

    // Store as active connection
    activeConnection = connection;

    return connection;
  }

  /// Disposes resources.
  void dispose() {
    _connectionAttempts.close();
    _messagesFromClient.close();
    _clientCloses.close();
  }
}

/// Represents a pending WebSocket connection attempt (UTS pattern).
///
/// Tests use this to inspect the connection URL and parameters before
/// deciding how to respond (success, refused, timeout, etc).
class PendingWebSocketConnection {
  PendingWebSocketConnection._({
    required this.url,
    required this.protocol,
    required this.timestamp,
    required this.listener,
    this.onMessageFromClient,
    this.onTextDataFrame,
    MockWebSocketClient? mockClient,
  }) : _mockClient = mockClient;

  /// The URL being connected to.
  final Uri url;

  /// The WebSocket protocol (e.g., 'application/json').
  final String protocol;

  /// When the connection was attempted.
  final DateTime timestamp;

  /// The listener that will receive all connection events.
  final WebSocketListener listener;

  /// Optional handler for messages from client.
  final MessageFromClientHandler? onMessageFromClient;

  /// Optional handler for raw text data frames.
  final TextDataFrameHandler? onTextDataFrame;

  /// Reference to the parent mock client.
  final MockWebSocketClient? _mockClient;

  final Completer<MockWebSocketConnection> _completer = Completer();

  /// Responds with successful connection and sends CONNECTED message.
  ///
  /// The connection is established first (completer completes), then the
  /// CONNECTED message is delivered asynchronously. This matches real
  /// WebSocket behavior where the connection opens before messages arrive.
  void respondWithSuccess(ProtocolMessage connectedMessage) {
    if (_completer.isCompleted) return;

    final mockConnection = MockWebSocketConnection._(
      listener: listener,
      onMessageFromClient: onMessageFromClient,
      onTextDataFrame: onTextDataFrame,
      mockClient: _mockClient,
    );

    // Store the connection in the client so tests can access it
    _mockClient?.activeConnection = mockConnection;

    // Complete the connection first - this allows connect() to return
    // and store the connection before the CONNECTED message is processed
    _completer.complete(mockConnection);

    // Send the CONNECTED message asynchronously - this matches real WebSocket
    // behavior where the connection opens before messages arrive
    scheduleMicrotask(() {
      listener.onMessage(connectedMessage);
    });
  }

  /// Responds with successful WebSocket connection but no protocol message.
  ///
  /// Use this to simulate a server that accepts the WebSocket connection
  /// but never sends a CONNECTED message (e.g., unresponsive server).
  /// The connection will hang until timeout.
  void respondWithSilence() {
    if (_completer.isCompleted) return;

    final mockConnection = MockWebSocketConnection._(
      listener: listener,
      onMessageFromClient: onMessageFromClient,
      onTextDataFrame: onTextDataFrame,
      mockClient: _mockClient,
    );

    // Store the connection so tests can access it
    _mockClient?.activeConnection = mockConnection;

    // Complete without sending any message - simulates unresponsive server
    _completer.complete(mockConnection);
  }

  /// Responds with connection refused error.
  void respondWithRefused() {
    if (_completer.isCompleted) return;
    _completer.completeError(
      const SocketException('Connection refused'),
    );
  }

  /// Responds with connection timeout.
  void respondWithTimeout() {
    if (_completer.isCompleted) return;
    _completer.completeError(
      TimeoutException('Connection timed out'),
    );
  }

  /// Responds with DNS resolution error.
  void respondWithDnsError() {
    if (_completer.isCompleted) return;
    _completer.completeError(
      SocketException('Failed to resolve hostname: ${url.host}'),
    );
  }

  /// WebSocket connects successfully but server sends ERROR message.
  ///
  /// If [thenClose] is true, the connection will be closed after sending
  /// the error message.
  void respondWithError(
    ProtocolMessage errorMessage, {
    bool thenClose = true,
  }) {
    if (_completer.isCompleted) return;

    final mockConnection = MockWebSocketConnection._(
      listener: listener,
      onMessageFromClient: onMessageFromClient,
      onTextDataFrame: onTextDataFrame,
      mockClient: _mockClient,
    );

    // Send the error message to the listener
    listener.onMessage(errorMessage);

    if (thenClose) {
      // Close the connection after sending error
      mockConnection._closed = true;
      listener.onClose();
    }

    _completer.complete(mockConnection);
  }
}

/// Mock WebSocket connection for an established connection.
///
/// This represents a successfully opened WebSocket connection. Tests can
/// inject messages from server and inspect messages from client.
class MockWebSocketConnection implements WebSocketConnection {
  MockWebSocketConnection._({
    required this.listener,
    this.onMessageFromClient,
    this.onTextDataFrame,
    MockWebSocketClient? mockClient,
  }) : _mockClient = mockClient;

  /// The listener receiving all connection events.
  final WebSocketListener listener;

  /// Handler for messages from client.
  final MessageFromClientHandler? onMessageFromClient;

  /// Handler for raw text data frames.
  final TextDataFrameHandler? onTextDataFrame;

  /// Reference to parent mock client for event recording.
  final MockWebSocketClient? _mockClient;

  /// Stream of outgoing messages (client → server).
  final StreamController<ProtocolMessage> _messagesFromClient =
      StreamController.broadcast();

  /// Stream of client-initiated close events.
  final StreamController<ClientCloseEvent> _clientCloses =
      StreamController.broadcast();

  /// All messages sent by client.
  final List<ProtocolMessage> sentMessages = [];

  bool _closed = false;

  /// Sends a message from client to server.
  @override
  void send(ProtocolMessage message) {
    if (_closed) throw StateError('Connection closed');
    sentMessages.add(message);
    _messagesFromClient.add(message);

    // Call raw text frame handler with the JSON that would be sent on the wire
    if (onTextDataFrame != null) {
      onTextDataFrame!(jsonEncode(message.toJson()));
    }

    onMessageFromClient?.call(message);
  }

  /// Test helper: Inject message from server to client.
  void sendToClient(ProtocolMessage message) {
    if (!_closed) {
      listener.onMessage(message);
    }
  }

  /// Test helper: Send a message and then close the connection.
  ///
  /// This simulates the server sending a final message (like DISCONNECTED
  /// or ERROR) and then closing the WebSocket connection.
  void sendToClientAndClose(ProtocolMessage message) {
    sendToClient(message);
    simulateDisconnect();
  }

  /// Test helper: Simulate server-initiated disconnect or transport failure.
  ///
  /// This records a [MockEventType.serverDisconnect] event.
  void simulateDisconnect([ErrorInfo? error]) {
    if (_closed) return;
    _closed = true;
    if (error != null) {
      listener.onError(error);
    }
    listener.onClose();
    _messagesFromClient.close();
    _clientCloses.close();
  }

  /// Closes the connection (client-initiated).
  ///
  /// This records a [MockEventType.clientClose] event with optional
  /// close code and reason.
  ///
  /// Matches the behavior of the real dart:io WebSocket:
  /// - close() is async and returns a Future
  /// - listener.onClose() is called asynchronously (via scheduleMicrotask
  ///   to simulate the stream's onDone behavior)
  @override
  Future<void> close({int? code, String? reason}) async {
    if (_closed) return;
    _closed = true;

    final closeEvent = ClientCloseEvent(code: code, reason: reason);

    // Record directly in parent's event list (synchronous, guaranteed)
    _mockClient?.events.add(
      MockEvent(
        type: MockEventType.clientClose,
        timestamp: DateTime.now(),
        data: closeEvent,
      ),
    );

    // Also emit to stream for await pattern
    _clientCloses.add(closeEvent);

    // Clear active connection in parent
    if (_mockClient?.activeConnection == this) {
      _mockClient?.activeConnection = null;
    }

    // Call onClose asynchronously - matches real WebSocket behavior where
    // onDone fires after the close completes
    scheduleMicrotask(() {
      listener.onClose(closeCode: code, closeReason: reason);
    });

    // Cleanup streams
    await _messagesFromClient.close();
    await _clientCloses.close();
  }

  /// Whether the connection is closed.
  bool get isClosed => _closed;
}

/// Event types for UTS event timeline.
enum MockEventType {
  /// Client attempted to connect.
  connectionAttempt,

  /// Connection established successfully.
  connectionSuccess,

  /// Connection failed (refused, timeout, DNS error, etc.).
  connectionFailure,

  /// Client sent a protocol message.
  messageFromClient,

  /// Server sent a protocol message (test injected).
  messageToClient,

  /// WebSocket ping frame sent to client (test injected).
  pingFrame,

  /// Server closed the connection or transport failure.
  serverDisconnect,

  /// Client initiated WebSocket close.
  clientClose,
}

/// Event record for UTS event timeline.
///
/// Provides chronological tracking of all mock events for debugging.
class MockEvent {
  MockEvent({
    required this.type,
    required this.timestamp,
    this.data,
  });

  final MockEventType type;
  final DateTime timestamp;
  final Object? data;

  @override
  String toString() => 'MockEvent('
      'type: $type, '
      'timestamp: $timestamp, '
      'data: $data'
      ')';
}

/// Event data for client-initiated WebSocket close.
class ClientCloseEvent {
  ClientCloseEvent({
    this.code,
    this.reason,
  });

  /// WebSocket close code (e.g., 1000 for normal closure).
  final int? code;

  /// Optional close reason.
  final String? reason;

  @override
  String toString() => 'ClientCloseEvent(code: $code, reason: $reason)';
}

# MockWebSocketClient - Handler-Based Interface

The `MockWebSocketClient` provides a flexible testing interface for mocking WebSocket connections in the Ably Dart SDK test suite. It follows the same patterns as `MockHttpClient` for consistency.

## Overview

The MockWebSocketClient implements the `WebSocketClient` interface and uses a handler-based pattern where callback functions are invoked for each connection attempt or message. This allows tests to respond dynamically and simulate various connection scenarios.

## Handler-Based Pattern

### Basic Connection Handling

```dart
final mock = MockWebSocketClient(
  onConnectionAttempt: (conn) {
    conn.respondWithSuccess(ProtocolMessageHelpers.connected(
      connectionId: 'test-connection-id',
      connectionKey: 'test-connection-key',
    ));
  },
);

final client = PubSubClient.forTesting(
  options: ClientOptions.fromKey('app.key:secret'),
  webSocketClient: mock,
);

await client.connect();
```

### Message Handling

```dart
final mock = MockWebSocketClient(
  onConnectionAttempt: (conn) {
    conn.respondWithSuccess(ProtocolMessageHelpers.connected());
  },
  onMessageFromClient: (message) {
    // Handle messages sent by client
    if (message.action == ProtocolAction.heartbeat) {
      print('Received heartbeat');
    }
  },
);
```

### Connection Failure Simulation

```dart
final mock = MockWebSocketClient(
  onConnectionAttempt: (conn) {
    if (shouldFail) {
      conn.respondWithRefused();  // Connection refused
      // or conn.respondWithTimeout();
      // or conn.respondWithDnsError();
    } else {
      conn.respondWithSuccess(ProtocolMessageHelpers.connected());
    }
  },
);
```

### Protocol Error Response

```dart
final mock = MockWebSocketClient(
  onConnectionAttempt: (conn) {
    // Connect succeeds but server sends error
    conn.respondWithError(
      ProtocolMessageHelpers.error(
        code: 40140,
        message: 'Token expired',
      ),
      thenClose: true,  // Close connection after error
    );
  },
);
```

### Awaitable Pattern

For tests that need to coordinate responses with test state:

```dart
final mock = MockWebSocketClient();

// Set up listener BEFORE connecting
final awaitFuture = mock.awaitConnectionAttempt();

// Start connection in background
final connectFuture = mock.connect(Uri.parse('wss://realtime.ably.io'));

// Wait for connection attempt and inspect it
final pendingConn = await awaitFuture;
expect(pendingConn.url.host, 'realtime.ably.io');

// Respond based on test state
pendingConn.respondWithSuccess(ProtocolMessageHelpers.connected());

final connection = await connectFuture;
```

**Important:** Call `awaitConnectionAttempt()` BEFORE triggering the connection to ensure the listener is set up.

## API Reference

### Constructor

```dart
MockWebSocketClient({
  ConnectionAttemptHandler? onConnectionAttempt,
  MessageFromClientHandler? onMessageFromClient,
})
```

Unlike MockHttpClient, if no `onConnectionAttempt` handler is provided, the connection will wait indefinitely for a response via the awaitable pattern.

### PendingWebSocketConnection

Represents a connection attempt that can be responded to:

**Properties:**
- `url: Uri` - The WebSocket URL being connected to
- `protocol: String` - The WebSocket protocol (default: 'json')
- `timestamp: DateTime` - When the connection was attempted

**Methods:**
- `respondWithSuccess(ProtocolMessage connectedMessage)` - Connection succeeds, sends CONNECTED message
- `respondWithRefused()` - Connection refused error (SocketException)
- `respondWithTimeout()` - Connection timeout (TimeoutException)
- `respondWithDnsError()` - DNS resolution failure (SocketException)
- `respondWithError(ProtocolMessage errorMessage, {bool thenClose = true})` - Connect succeeds but server sends ERROR

### MockWebSocketConnection

Represents an established WebSocket connection:

**Properties:**
- `messages: Stream<ProtocolMessage>` - Stream of messages from server to client
- `sentMessages: List<ProtocolMessage>` - All messages sent by client (for inspection)
- `isClosed: bool` - Whether the connection is closed

**Methods:**
- `send(ProtocolMessage message)` - Send message from client to server
- `sendToClient(ProtocolMessage message)` - Inject message from server to client (test helper)
- `sendToClientAndClose(ProtocolMessage message)` - Send message then close connection (for DISCONNECTED/ERROR)
- `simulateDisconnect([ErrorInfo? error])` - Simulate unexpected disconnect (no protocol message)
- `close()` - Close the connection

### MockWebSocketClient Properties

- `activeConnection: MockWebSocketConnection?` - Currently active connection (null if not connected)
- `events: List<MockEvent>` - Event timeline for debugging (UTS compliance)

### Awaitable Methods

```dart
Future<PendingWebSocketConnection> awaitConnectionAttempt({
  Duration timeout = const Duration(seconds: 5),
})

Future<ProtocolMessage> awaitNextMessageFromClient({
  Duration timeout = const Duration(seconds: 5),
})

Future<void> awaitCloseRequest({
  Duration timeout = const Duration(seconds: 5),
})
```

### Management

```dart
void dispose()  // Clean up resources (call in tearDown)
```

## Message Injection

After connection is established, inject messages from server:

```dart
final connection = await mock.connect(uri);

// Inject HEARTBEAT from server (connection stays open)
connection.sendToClient(ProtocolMessageHelpers.heartbeat());

// Inject DISCONNECTED with error AND close the connection
// Use this for DISCONNECTED/ERROR messages that terminate the connection
await connection.sendToClientAndClose(ProtocolMessageHelpers.disconnected(
  error: ErrorInfo(code: 80003, message: 'Connection interrupted'),
));

// Simulate unexpected disconnect (no protocol message sent)
await connection.simulateDisconnect();
```

**Important:** When simulating server-initiated disconnection:
- Use `sendToClientAndClose()` for DISCONNECTED or ERROR messages (sends message then closes)
- Use `simulateDisconnect()` for unexpected transport failures (no message, just closes)

## Capturing Client Messages

Inspect messages sent by the client:

```dart
final connection = await mock.connect(uri);

// Client sends messages...
client.connection.ping();

// Inspect captured messages
expect(connection.sentMessages.length, 1);
expect(connection.sentMessages[0].action, ProtocolAction.heartbeat);
```

## Event Timeline (UTS Compliance)

The mock maintains a chronological event timeline for debugging:

```dart
final mock = MockWebSocketClient(...);
await mock.connect(uri);

// Inspect timeline
for (final event in mock.events) {
  print('${event.type} at ${event.timestamp}');
}
```

Event types: `connectionAttempt`, `connectionSuccess`, `connectionFailure`, `messageFromClient`, `messageToClient`, `disconnect`, `closeRequest`

## Protocol Message Helpers

Use `ProtocolMessageHelpers` for creating common protocol messages:

```dart
import 'protocol_message_helpers.dart';

// CONNECTED message
ProtocolMessageHelpers.connected(
  connectionId: 'conn-123',
  connectionKey: 'key-456',
  connectionStateTtl: 120000,
  maxIdleInterval: 15000,
)

// DISCONNECTED message
ProtocolMessageHelpers.disconnected(error: ErrorInfo(...))

// ERROR message
ProtocolMessageHelpers.error(code: 40140, message: 'Token expired')

// HEARTBEAT message
ProtocolMessageHelpers.heartbeat()

// ATTACHED message
ProtocolMessageHelpers.attached(channel: 'my-channel')

// DETACHED message
ProtocolMessageHelpers.detached(channel: 'my-channel')
```

## Examples

See `mock_websocket_client_test.dart` for comprehensive working examples including:

1. Handler-based connection handling
2. Connection failures (refused, timeout, DNS errors)
3. Protocol error responses
4. Awaitable pattern for coordinated testing
5. Message injection and capture
6. Disconnect simulation
7. Event timeline inspection

Run the tests:
```bash
dart test test/helpers/mock_websocket_client_test.dart
```

## Comparison with MockHttpClient

| Aspect | MockHttpClient | MockWebSocketClient |
|--------|----------------|---------------------|
| Default without handler | Auto-succeeds with 200 | Waits for manual response |
| Connection response | `respondWithSuccess()` | `respondWithSuccess(ProtocolMessage)` |
| Message stream | N/A (request/response) | Bidirectional message stream |
| Injection | N/A | `sendToClient()` for server messages |
| Capture | `capturedRequests` | `connection.sentMessages` |

## Design Rationale

The handler-based interface provides several advantages:

1. **Consistency**: Same patterns as MockHttpClient for familiarity
2. **Flexibility**: Responses can be determined dynamically based on connection details
3. **Protocol Simulation**: Full control over protocol message flow
4. **Bidirectional**: Supports both client-to-server and server-to-client messages
5. **UTS Compliance**: Event timeline for debugging and audit trails
6. **Disconnect Simulation**: Test recovery from unexpected disconnects

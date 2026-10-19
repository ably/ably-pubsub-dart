import 'package:ably_pubsub_device/src/error/error_info.dart';
import 'package:ably_pubsub_device/src/realtime/protocol_message.dart';
import 'package:ably_pubsub_device/src/realtime/websocket_client.dart';
import 'package:test/test.dart';
import 'mock_websocket_client.dart';
import 'protocol_message_helpers.dart';

/// Test listener that captures events for verification.
class TestWebSocketListener implements WebSocketListener {
  final List<ProtocolMessage> messages = [];
  final List<Object> errors = [];
  int closeCount = 0;
  int? lastCloseCode;
  String? lastCloseReason;

  @override
  void onMessage(ProtocolMessage message) {
    messages.add(message);
  }

  @override
  void onError(Object error) {
    errors.add(error);
  }

  @override
  void onClose({int? closeCode, String? closeReason}) {
    closeCount++;
    lastCloseCode = closeCode;
    lastCloseReason = closeReason;
  }

  void reset() {
    messages.clear();
    errors.clear();
    closeCount = 0;
    lastCloseCode = null;
    lastCloseReason = null;
  }
}

void main() {
  group('MockWebSocketClient - Handler-based interface', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('successful connection with handler', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          expect(conn.url.host, 'main.realtime.ably.net');
          expect(conn.url.scheme, 'wss');
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      expect(connection, isNotNull);
      expect(mock.activeConnection, equals(connection));
      expect(mock.events.length, 1);
      expect(mock.events[0].type, MockEventType.connectionAttempt);
    });

    test('connection refused with handler', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithRefused();
        },
      );

      expect(
        () => mock.connect(
          Uri.parse('wss://main.realtime.ably.net'),
          TestWebSocketListener(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(mock.activeConnection, isNull);
    });

    test('connection timeout with handler', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithTimeout();
        },
      );

      expect(
        () => mock.connect(
          Uri.parse('wss://main.realtime.ably.net'),
          TestWebSocketListener(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('DNS error with handler', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithDnsError();
        },
      );

      expect(
        () => mock.connect(
          Uri.parse('wss://invalid.host.example'),
          TestWebSocketListener(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('connection with error message', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithError(
            ProtocolMessageHelpers.error(
              code: 40140,
              message: 'Token expired',
            ),
          );
        },
      );

      final listener = TestWebSocketListener();
      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Should receive error message via listener
      expect(listener.messages.length, 1);
      expect(listener.messages[0].error?.code, 40140);
      expect(listener.messages[0].error?.message, 'Token expired');

      // Connection should close after error
      expect(listener.closeCount, 1);
      expect(connection.isClosed, true);
    });

    test('message from client triggers handler', () async {
      final receivedMessages = <ProtocolMessage>[];
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (message) {
          receivedMessages.add(message);
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      connection.send(ProtocolMessageHelpers.heartbeat());

      // Allow microtasks to process (handler is invoked synchronously,
      // but use await to ensure any async scheduling completes)
      await Future.value();
      expect(receivedMessages.length, 1);
      expect(receivedMessages[0].action, ProtocolAction.heartbeat);
    });

    test('multiple connections', () async {
      var connectionCount = 0;
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          connectionCount++;
          if (connectionCount == 1) {
            conn.respondWithRefused();
          } else {
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          }
        },
      );

      // First connection fails
      expect(
        () => mock.connect(
          Uri.parse('wss://main.realtime.ably.net'),
          TestWebSocketListener(),
        ),
        throwsA(isA<Exception>()),
      );

      // Second connection succeeds
      final connection = await mock.connect(
        Uri.parse('wss://a.fallback.ably-realtime.com'),
        TestWebSocketListener(),
      );
      expect(connection, isNotNull);
      expect(mock.events.length, 2);
    });
  });

  group('MockWebSocketClient - Awaitable interface', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('awaitable connection attempt', () async {
      mock = MockWebSocketClient();

      // Await must be set up BEFORE triggering the connection
      final awaitFuture = mock.awaitConnectionAttempt();

      // Start connection in background
      final connectFuture = mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      // Await and inspect connection attempt
      final pendingConn = await awaitFuture;
      expect(pendingConn.url.host, 'main.realtime.ably.net');
      expect(pendingConn.url.scheme, 'wss');
      expect(pendingConn.protocol, 'json');

      // Respond with success
      pendingConn.respondWithSuccess(ProtocolMessageHelpers.connected());

      final connection = await connectFuture;
      expect(connection, isNotNull);
    });

    test('awaitable message from client', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      // Send message in background
      final heartbeat = ProtocolMessageHelpers.heartbeat();
      connection.send(heartbeat);

      // Await the message
      final message = await mock.awaitNextMessageFromClient();
      expect(message.action, ProtocolAction.heartbeat);
    });

    test('awaitable close request', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      // Close in background
      connection.close();

      // Await the close
      await mock.awaitClientClose();
      expect(connection.isClosed, true);
    });

    test('awaitable with connection refusal', () async {
      mock = MockWebSocketClient();

      // Set up await BEFORE connecting
      final awaitFuture = mock.awaitConnectionAttempt();
      final connectFuture = mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      final pendingConn = await awaitFuture;
      pendingConn.respondWithRefused();

      expect(connectFuture, throwsA(isA<Exception>()));
    });
  });

  group('MockWebSocketConnection - Message handling', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('receives CONNECTED message on successful connection', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(
            ProtocolMessageHelpers.connected(
              connectionId: 'conn-123',
              connectionKey: 'key-456',
            ),
          );
        },
      );

      final listener = TestWebSocketListener();
      await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Pump microtask queue so scheduleMicrotask-delivered CONNECTED arrives
      await Future.value();

      // Listener received CONNECTED message
      expect(listener.messages.length, 1);
      expect(listener.messages[0].action, ProtocolAction.connected);
      expect(listener.messages[0].connectionId, 'conn-123');
      expect(listener.messages[0].connectionKey, 'key-456');
    });

    test('sendToClient injects message from server', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final listener = TestWebSocketListener();
      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Pump microtask queue so scheduleMicrotask-delivered CONNECTED arrives
      await Future.value();

      // Listener received CONNECTED
      expect(listener.messages.length, 1);
      expect(listener.messages[0].action, ProtocolAction.connected);

      // Inject HEARTBEAT from server
      connection.sendToClient(ProtocolMessageHelpers.heartbeat());

      // Listener received HEARTBEAT
      expect(listener.messages.length, 2);
      expect(listener.messages[1].action, ProtocolAction.heartbeat);
    });

    test('send captures messages from client', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      connection.send(ProtocolMessageHelpers.heartbeat());
      connection
          .send(ProtocolMessageHelpers.auth(authDetails: {'token': 'abc'}));

      expect(connection.sentMessages.length, 2);
      expect(connection.sentMessages[0].action, ProtocolAction.heartbeat);
      expect(connection.sentMessages[1].action, ProtocolAction.auth);
    });

    test('multiple messages from server', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final listener = TestWebSocketListener();
      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Pump microtask queue so scheduleMicrotask-delivered CONNECTED arrives
      await Future.value();

      // Listener received CONNECTED
      expect(listener.messages.length, 1);

      // Send more messages
      connection.sendToClient(ProtocolMessageHelpers.heartbeat());
      connection.sendToClient(ProtocolMessageHelpers.disconnected());

      // Listener received all messages
      expect(listener.messages.length, 3);
      expect(listener.messages[1].action, ProtocolAction.heartbeat);
      expect(listener.messages[2].action, ProtocolAction.disconnected);
    });

    test('send throws after connection closed', () {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      connection.then((conn) {
        conn.close();
        expect(
          () => conn.send(ProtocolMessageHelpers.heartbeat()),
          throwsStateError,
        );
      });
    });
  });

  group('MockWebSocketConnection - Disconnect simulation', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('simulateDisconnect closes connection', () async {
      final listener = TestWebSocketListener();

      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      expect(connection.isClosed, false);

      connection.simulateDisconnect();

      expect(connection.isClosed, true);
      expect(listener.closeCount, 1);
    });

    test('sendToClientAndClose sends message then closes', () async {
      final listener = TestWebSocketListener();

      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Pump microtask queue so scheduleMicrotask-delivered CONNECTED arrives
      await Future.value();

      // Listener received CONNECTED
      expect(listener.messages.length, 1);
      expect(connection.isClosed, false);

      // Send DISCONNECTED and close
      connection.sendToClientAndClose(
        ProtocolMessageHelpers.disconnected(
          error: const ErrorInfo(code: 80003, message: 'Test disconnect'),
        ),
      );

      // Message was received and connection is closed
      expect(listener.messages.length, 2);
      expect(listener.messages[1].action, ProtocolAction.disconnected);
      expect(connection.isClosed, true);
      expect(listener.closeCount, 1);
    });

    test('simulateDisconnect with error', () async {
      final listener = TestWebSocketListener();

      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        listener,
      );

      // Pump microtask queue so scheduleMicrotask-delivered CONNECTED arrives
      await Future.value();

      // Listener received CONNECTED message
      expect(listener.messages.length, 1);

      const errorInfo = ErrorInfo(
        code: 50000,
        message: 'Connection lost',
      );

      connection.simulateDisconnect(errorInfo);

      // Error and close received by listener
      expect(listener.errors.length, 1);
      expect(listener.errors[0], equals(errorInfo));
      expect(listener.closeCount, 1);
      expect(connection.isClosed, true);
    });

    test('close clears active connection', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      expect(mock.activeConnection, equals(connection));

      await connection.close();

      // Allow microtasks to process the close event
      await Future.value();
      expect(mock.activeConnection, isNull);
    });
  });

  group('MockWebSocketClient - Event timeline (UTS)', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('records connection attempts', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      expect(mock.events.length, 1);
      expect(mock.events[0].type, MockEventType.connectionAttempt);

      final pendingConn = mock.events[0].data as PendingWebSocketConnection;
      expect(pendingConn.url.host, 'main.realtime.ably.net');
    });

    test('timeline includes timestamps', () async {
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final before = DateTime.now();
      await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );
      final after = DateTime.now();

      expect(mock.events.length, 1);
      expect(
        mock.events[0].timestamp
            .isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(
        mock.events[0].timestamp
            .isBefore(after.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('multiple connection attempts in timeline', () async {
      var attemptCount = 0;
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          attemptCount++;
          if (attemptCount == 1) {
            conn.respondWithRefused();
          } else if (attemptCount == 2) {
            conn.respondWithTimeout();
          } else {
            conn.respondWithSuccess(ProtocolMessageHelpers.connected());
          }
        },
      );

      // First attempt fails
      try {
        await mock.connect(
          Uri.parse('wss://main.realtime.ably.net'),
          TestWebSocketListener(),
        );
      } catch (_) {}

      // Second attempt fails
      try {
        await mock.connect(
          Uri.parse('wss://a.fallback.ably-realtime.com'),
          TestWebSocketListener(),
        );
      } catch (_) {}

      // Third attempt succeeds
      await mock.connect(
        Uri.parse('wss://b.fallback.ably-realtime.com'),
        TestWebSocketListener(),
      );

      expect(mock.events.length, 3);
      expect(mock.events[0].type, MockEventType.connectionAttempt);
      expect(mock.events[1].type, MockEventType.connectionAttempt);
      expect(mock.events[2].type, MockEventType.connectionAttempt);

      final conn1 = mock.events[0].data as PendingWebSocketConnection;
      final conn2 = mock.events[1].data as PendingWebSocketConnection;
      final conn3 = mock.events[2].data as PendingWebSocketConnection;

      expect(conn1.url.host, 'main.realtime.ably.net');
      expect(conn2.url.host, 'a.fallback.ably-realtime.com');
      expect(conn3.url.host, 'b.fallback.ably-realtime.com');
    });
  });

  group('MockWebSocketClient - Mixed handler and awaitable', () {
    late MockWebSocketClient mock;

    tearDown(() {
      mock.dispose();
    });

    test('handler and awaitable both receive connection events', () async {
      var handlerCalled = false;
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          handlerCalled = true;
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
      );

      final awaitFuture = mock.awaitConnectionAttempt();
      final connectFuture = mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );
      final pendingConn = await awaitFuture;

      expect(handlerCalled, true);
      expect(pendingConn.url.host, 'main.realtime.ably.net');

      await connectFuture;
    });

    test('handler and awaitable both receive message events', () async {
      final receivedMessages = <ProtocolMessage>[];
      mock = MockWebSocketClient(
        onConnectionAttempt: (conn) {
          conn.respondWithSuccess(ProtocolMessageHelpers.connected());
        },
        onMessageFromClient: (message) {
          receivedMessages.add(message);
        },
      );

      final connection = await mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );

      connection.send(ProtocolMessageHelpers.heartbeat());

      final message = await mock.awaitNextMessageFromClient();
      expect(receivedMessages.length, 1);
      expect(message.action, ProtocolAction.heartbeat);
    });
  });

  group('MockWebSocketClient - Default behavior', () {
    test('no handler requires manual response via await', () async {
      final mock = MockWebSocketClient();

      final awaitFuture = mock.awaitConnectionAttempt();
      final connectFuture = mock.connect(
        Uri.parse('wss://main.realtime.ably.net'),
        TestWebSocketListener(),
      );
      final pendingConn = await awaitFuture;

      // Must manually respond (no auto-success like HTTP mock)
      pendingConn.respondWithSuccess(ProtocolMessageHelpers.connected());

      final connection = await connectFuture;
      expect(connection, isNotNull);

      mock.dispose();
    });
  });
}

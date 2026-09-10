import 'package:ably_pubsub_device/ably_pubsub_device.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Logging Tests
///
/// Spec points: RSC2, RSC3, RSC4, TO3b, TO3c
void main() {
  group('Logging', () {
    late MockHttpClient mockHttp;

    setUp(() {
      mockHttp = MockHttpClient(
        onRequest: (req) {
          req.respondWith(200, [1704067200000]);
        },
      );
    });

    group('RSC2 - Default log level is warn', () {
      // UTS: rest/unit/RSC2/default-log-level-warn-0
      test('only warn and error events emitted at default level', () async {
        final capturedLogs = <({
          LogLevel level,
          String message,
          Map<String, dynamic> context
        })>[];

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            logHandler: (level, message, context) {
              capturedLogs
                  .add((level: level, message: message, context: context));
            },
          ),
          httpClient: mockHttp,
        );

        await client.time();

        // Default level is warn — only error and warn should be captured
        for (final log in capturedLogs) {
          expect(
            log.level.index <= LogLevel.warn.index,
            isTrue,
            reason:
                'Expected only error/warn, got ${log.level.name}: ${log.message}',
          );
        }
      });
    });

    group('TO3b - Log level can be changed (RSC3)', () {
      // UTS: rest/unit/TO3b/log-level-changeable-0
      test('verbose level captures info and debug messages', () async {
        final capturedLogs = <({
          LogLevel level,
          String message,
          Map<String, dynamic> context
        })>[];

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            logLevel: LogLevel.verbose,
            logHandler: (level, message, context) {
              capturedLogs
                  .add((level: level, message: message, context: context));
            },
          ),
          httpClient: mockHttp,
        );

        await client.time();

        // Should have info-level logs
        final infoLogs =
            capturedLogs.where((l) => l.level == LogLevel.info).toList();
        expect(
          infoLogs,
          isNotEmpty,
          reason: 'Expected info-level logs with verbose',
        );

        // Should have debug-level logs for HTTP request
        final debugLogs =
            capturedLogs.where((l) => l.level == LogLevel.debug).toList();
        final httpRequestLogs = debugLogs.where(
          (l) => l.message.contains('HTTP request'),
        );
        expect(
          httpRequestLogs,
          isNotEmpty,
          reason: 'Expected debug log for HTTP request',
        );
      });
    });

    group('TO3c - Custom log handler (RSC4)', () {
      // UTS: rest/unit/TO3c/custom-handler-structured-events-0
      test('custom handler receives structured events', () async {
        final capturedLogs = <({
          LogLevel level,
          String message,
          Map<String, dynamic> context
        })>[];

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            logLevel: LogLevel.info,
            logHandler: (level, message, context) {
              capturedLogs
                  .add((level: level, message: message, context: context));
            },
          ),
          httpClient: mockHttp,
        );

        await client.time();

        // Handler was called
        expect(capturedLogs, isNotEmpty);

        // At least one log has non-empty context
        final logsWithContext = capturedLogs.where(
          (l) => l.context.isNotEmpty,
        );
        expect(
          logsWithContext,
          isNotEmpty,
          reason: 'Expected at least one log with non-empty context',
        );
      });

      // UTS: rest/unit/TO3c2/context-contains-expected-keys-0
      test('structured context contains expected keys for HTTP operations',
          () async {
        final capturedLogs = <({
          LogLevel level,
          String message,
          Map<String, dynamic> context
        })>[];

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            logLevel: LogLevel.debug,
            logHandler: (level, message, context) {
              capturedLogs
                  .add((level: level, message: message, context: context));
            },
          ),
          httpClient: mockHttp,
        );

        await client.time();

        // Find the HTTP request log
        final httpLogs = capturedLogs
            .where(
              (l) => l.message == 'HTTP request' && l.level == LogLevel.debug,
            )
            .toList();
        expect(httpLogs, isNotEmpty);

        final httpContext = httpLogs.first.context;
        expect(httpContext, contains('method'));
        expect(httpContext, contains('host'));
        expect(httpContext, contains('path'));
        expect(httpContext['method'], equals('GET'));
        expect(httpContext['path'], equals('/time'));
      });
    });

    group('RSC2b - LogLevel.none suppresses all output', () {
      // UTS: rest/unit/RSC2b/log-level-none-suppresses-all-0
      test('no log events with level none', () async {
        final capturedLogs = <({
          LogLevel level,
          String message,
          Map<String, dynamic> context
        })>[];

        final client = RestClient.forTesting(
          options: ClientOptions(
            key: 'appId.keyId:keySecret',
            logLevel: LogLevel.none,
            logHandler: (level, message, context) {
              capturedLogs
                  .add((level: level, message: message, context: context));
            },
          ),
          httpClient: mockHttp,
        );

        await client.time();

        expect(
          capturedLogs,
          isEmpty,
          reason: 'No logs should be captured with LogLevel.none',
        );
      });
    });
  });
}

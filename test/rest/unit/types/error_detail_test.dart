import 'package:ably/ably.dart';
import 'package:test/test.dart';

import '../../../helpers/mock_http_client.dart';

/// Unit tests for `ErrorInfo.detail` (TI1, TI6), the field that carries Ably
/// Chat's moderation rejection detail for error codes 42211 and 42213
/// (CHA-M3e).
void main() {
  group('TI1, TI6 - ErrorInfo.detail decodes from the wire error object', () {
    test('TI6 - detail decodes as a map of string keys to string values', () {
      final error = ErrorInfo.fromMap({
        'code': 42211,
        'statusCode': 400,
        'message': 'Message rejected by moderation',
        'detail': {'rejectionReason': 'profanity', 'ruleId': 'r-1'},
      });

      expect(error.code, equals(42211));
      expect(
        error.detail,
        equals({'rejectionReason': 'profanity', 'ruleId': 'r-1'}),
      );
    });

    test('TI6 - detail round-trips through toMap', () {
      const error = ErrorInfo(
        code: 42213,
        statusCode: 400,
        message: 'Message rejected by moderation',
        detail: {'rejectionReason': 'blocked-term'},
      );

      expect(
        error.toMap()['detail'],
        equals({'rejectionReason': 'blocked-term'}),
      );
      expect(error.toString(), contains('detail='));
    });

    test('TI6 - detail is omitted when absent or empty', () {
      final absent = ErrorInfo.fromMap({'code': 40000, 'statusCode': 400});
      expect(absent.detail, isNull);
      expect(absent.toMap().containsKey('detail'), isFalse);

      final empty = ErrorInfo.fromMap({
        'code': 40000,
        'statusCode': 400,
        'detail': <String, dynamic>{},
      });
      expect(empty.detail, isNull);
      expect(empty.toMap().containsKey('detail'), isFalse);

      const constructedEmpty = ErrorInfo(code: 40000, detail: {});
      expect(constructedEmpty.toMap().containsKey('detail'), isFalse);
      expect(constructedEmpty.toString(), isNot(contains('detail=')));
    });

    test('two errors differing only in detail are not equal', () {
      const a = ErrorInfo(code: 42211, detail: {'rejectionReason': 'a'});
      const b = ErrorInfo(code: 42211, detail: {'rejectionReason': 'b'});
      // Built from a non-const map literal, so this is a genuinely distinct
      // object from `a`'s detail map even though the two are structurally
      // equal. Dart canonicalizes structurally-identical *const* map
      // literals to the same instance, so a `const c` here would make
      // `a.detail` and `c.detail` `identical` - which would let a naive
      // identity-based `==`/`hashCode` (`other.detail == detail`) pass this
      // test even without value comparison via `MapEquality`.
      // ignore: prefer_const_constructors
      final c = ErrorInfo(code: 42211, detail: {'rejectionReason': 'a'});
      expect(identical(a.detail, c.detail), isFalse);

      expect(a, isNot(equals(b)));
      expect(a, equals(c));
      expect(a.hashCode, equals(c.hashCode));
    });
  });

  group('TI6 - fromMap tolerates malformed wire detail', () {
    test('detail as a list is treated as absent', () {
      final error = ErrorInfo.fromMap({
        'code': 40000,
        'detail': ['not', 'a', 'map'],
      });

      expect(error.detail, isNull);
    });

    test('detail as a number is treated as absent', () {
      final error = ErrorInfo.fromMap({
        'code': 40000,
        'detail': 42,
      });

      expect(error.detail, isNull);
    });

    test('detail with non-string values is stringified', () {
      final error = ErrorInfo.fromMap({
        'code': 40000,
        'detail': {'count': 5, 'active': true},
      });

      expect(error.detail, equals({'count': '5', 'active': 'true'}));
    });
  });

  group('TI1, TI6 - REST error mapping carries detail end-to-end', () {
    test('a rejected publish throws an ErrorInfo carrying detail', () async {
      final mockHttp = MockHttpClient(
        onRequest: (request) {
          request.respondWith(400, {
            'error': {
              'code': 42211,
              'statusCode': 400,
              'message': 'Message rejected by moderation',
              'detail': {'rejectionReason': 'profanity'},
            },
          });
        },
      );

      final client = RestClient.forTesting(
        options: ClientOptions.fromKey('appId.keyId:keySecret'),
        httpClient: mockHttp,
      );

      final channel = client.channels.get('test-error-detail');

      try {
        await channel.publish(name: 'chat.message', data: 'oops');
        fail('Expected AblyException');
      } on AblyException catch (e) {
        expect(e.errorInfo!.code, equals(42211));
        expect(e.errorInfo!.detail, equals({'rejectionReason': 'profanity'}));
      }

      mockHttp.dispose();
    });
  });
}

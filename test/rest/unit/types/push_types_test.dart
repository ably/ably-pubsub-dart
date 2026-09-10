import 'package:ably/ably.dart';
import 'package:test/test.dart';

/// Push Type Tests
///
/// Pure type construction and serialization tests for [DeviceDetails],
/// [DevicePushDetails], and [PushChannelSubscription] — no HTTP mock needed.
///
/// Adaptations from the UTS spec (recorded per the spec's Notes):
/// - The UTS `fromJson`/`toJson` map to this repo's `fromMap`/`toMap`.
/// - ably-dart exposes `platform`, `formFactor`, and `push.state` as raw
///   wire strings rather than enums (`DevicePlatform`, `DeviceFormFactor`,
///   `DevicePushState` do not exist), so enum-member assertions are adapted
///   to wire-string equality (deviation permitted by the spec Notes for
///   PCP4, and by extension PCD4/PCD6).
/// - `PushChannelSubscription.forDevice`/`forClientId` are named
///   constructors with named parameters rather than the IDL's positional
///   factories.
/// - For the PCS5 both-identifiers wire parse, ably-dart takes the
///   as-received branch (like ably-js): `fromMap` copies fields without
///   validation.
///
/// Spec points: PCD1–PCD7, PCP1–PCP4, PCS1–PCS5
///
/// Spec: specification/uts/rest/unit/types/push_types.md
void main() {
  group('PCD - DeviceDetails', () {
    // UTS: rest/unit/PCD1/device-details-round-trip-0
    test('PCD1 - DeviceDetails round-trips all attributes through wire JSON',
        () {
      final wire = <String, dynamic>{
        'id': 'device-001',
        'clientId': 'client-abc',
        'platform': 'android',
        'formFactor': 'phone',
        'metadata': {'environment': 'test'},
        'push': {
          'recipient': {
            'transportType': 'fcm',
            'registrationToken': 'reg-token-1',
          },
          'state': 'ACTIVE',
          'errorReason': {
            'code': 40000,
            'statusCode': 400,
            'message': 'example error',
          },
        },
      };

      final device = DeviceDetails.fromMap(wire);

      expect(device.id, equals('device-001')); // PCD2
      expect(device.clientId, equals('client-abc')); // PCD3
      expect(device.formFactor, equals('phone')); // PCD4
      expect(device.metadata, equals({'environment': 'test'})); // PCD5
      expect(device.platform, equals('android')); // PCD6

      // PCD7 — push is a DevicePushDetails (PCP1)
      expect(device.push, isA<DevicePushDetails>());
      expect(
        device.push!.recipient, // PCP3
        equals({
          'transportType': 'fcm',
          'registrationToken': 'reg-token-1',
        }),
      );
      expect(device.push!.state, equals('ACTIVE')); // PCP4
      expect(device.push!.errorReason, isA<ErrorInfo>()); // PCP2
      expect(device.push!.errorReason!.code, equals(40000));
      expect(device.push!.errorReason!.statusCode, equals(400));
      expect(device.push!.errorReason!.message, equals('example error'));

      // Round trip — serialization reproduces the wire fields
      final jsonData = device.toMap();
      expect(jsonData['id'], equals('device-001'));
      expect(jsonData['clientId'], equals('client-abc'));
      expect(jsonData['platform'], equals('android'));
      expect(jsonData['formFactor'], equals('phone'));
      expect(jsonData['metadata'], equals({'environment': 'test'}));
      final pushJson = jsonData['push'] as Map<String, dynamic>;
      expect(
        pushJson['recipient'],
        equals({
          'transportType': 'fcm',
          'registrationToken': 'reg-token-1',
        }),
      );
      expect(pushJson['state'], equals('ACTIVE'));
      expect(
        (pushJson['errorReason'] as Map<String, dynamic>)['code'],
        equals(40000),
      );
    });

    // UTS: rest/unit/PCD4/form-factor-values-0
    test('PCD4 - all DeviceFormFactor values are accepted', () {
      const formFactors = [
        'phone',
        'tablet',
        'desktop',
        'tv',
        'watch',
        'car',
        'embedded',
        'other',
      ];

      for (final formFactor in formFactors) {
        final device = DeviceDetails.fromMap({
          'id': 'device-001',
          'platform': 'android',
          'formFactor': formFactor,
        });

        expect(device.formFactor, equals(formFactor));
        expect(device.toMap()['formFactor'], equals(formFactor));
      }
    });

    // UTS: rest/unit/PCD6/platform-values-0
    test('PCD6 - all DevicePlatform values are accepted', () {
      const platforms = ['android', 'ios', 'browser'];

      for (final platform in platforms) {
        final device = DeviceDetails.fromMap({
          'id': 'device-001',
          'platform': platform,
          'formFactor': 'phone',
        });

        expect(device.platform, equals(platform));
        expect(device.toMap()['platform'], equals(platform));
      }
    });
  });

  group('PCP - DevicePushDetails', () {
    // UTS: rest/unit/PCP4/device-push-state-values-0
    test(
        'PCP2, PCP3, PCP4 - DevicePushDetails state values, errorReason, and '
        'recipient parse from wire JSON', () {
      // Wire state values are uppercase, per ably-js's type declarations
      // (see the UTS spec Notes). ably-dart exposes the raw wire string.
      const wireStates = ['ACTIVE', 'FAILING', 'FAILED'];

      for (final wireState in wireStates) {
        final device = DeviceDetails.fromMap({
          'id': 'device-001',
          'platform': 'ios',
          'formFactor': 'phone',
          'push': {
            'recipient': {
              'transportType': 'apns',
              'deviceToken': 'apns-token-1',
            },
            'state': wireState,
            'errorReason': {
              'code': 71103,
              'statusCode': 500,
              'message': 'upstream failure',
            },
          },
        });

        // PCP4 — state parses to the corresponding value
        expect(device.push!.state, equals(wireState));

        // PCP2 — errorReason parses as ErrorInfo
        expect(device.push!.errorReason, isA<ErrorInfo>());
        expect(device.push!.errorReason!.code, equals(71103));

        // PCP3 — recipient is an opaque string map, preserved as-received
        expect(
          device.push!.recipient,
          equals({
            'transportType': 'apns',
            'deviceToken': 'apns-token-1',
          }),
        );
      }
    });
  });

  group('PCS - PushChannelSubscription', () {
    // UTS: rest/unit/PCS5/push-channel-subscription-for-device-0
    test('PCS5 - forDevice sets channel and deviceId, leaving clientId null',
        () {
      final subscription = PushChannelSubscription.forDevice(
        channel: 'push-test-channel',
        deviceId: 'device-001',
      );

      expect(subscription.channel, equals('push-test-channel')); // PCS4
      expect(subscription.deviceId, equals('device-001')); // PCS2
      // PCS5 — the other identifier stays null
      expect(subscription.clientId, isNull);

      final jsonData = subscription.toMap();
      expect(jsonData['channel'], equals('push-test-channel'));
      expect(jsonData['deviceId'], equals('device-001'));
      // "clientId" NOT IN json_data OR json_data["clientId"] IS null
      expect(jsonData['clientId'], isNull);
    });

    // UTS: rest/unit/PCS5/push-channel-subscription-for-client-1
    test('PCS5 - forClientId sets channel and clientId, leaving deviceId null',
        () {
      final subscription = PushChannelSubscription.forClientId(
        channel: 'push-test-channel',
        clientId: 'client-abc',
      );

      expect(subscription.channel, equals('push-test-channel')); // PCS4
      expect(subscription.clientId, equals('client-abc')); // PCS3
      // PCS5 — the other identifier stays null
      expect(subscription.deviceId, isNull);

      final jsonData = subscription.toMap();
      expect(jsonData['channel'], equals('push-test-channel'));
      expect(jsonData['clientId'], equals('client-abc'));
      // "deviceId" NOT IN json_data OR json_data["deviceId"] IS null
      expect(jsonData['deviceId'], isNull);
    });

    // UTS: rest/unit/PCS5/exactly-one-of-device-client-2
    test('PCS5 - precisely one of deviceId or clientId is non-null', () {
      // 1. Construction — each factory populates exactly one identifier
      // (PCS5). In Dart this is additionally a compile-time property: each
      // named constructor takes exactly one identifier.
      expect(
        PushChannelSubscription.forDevice(
          channel: 'ch',
          deviceId: 'device-001',
        ).clientId,
        isNull,
      );
      expect(
        PushChannelSubscription.forClientId(
          channel: 'ch',
          clientId: 'client-abc',
        ).deviceId,
        isNull,
      );

      // 2. Wire parsing — both identifiers present. ably-dart takes the
      // as-received branch (like ably-js): fromMap copies fields without
      // validation.
      final wire = <String, dynamic>{
        'channel': 'ch',
        'deviceId': 'device-001',
        'clientId': 'client-abc',
      };

      final subscription = PushChannelSubscription.fromMap(wire);
      expect(subscription.channel, equals('ch'));
      expect(subscription.deviceId, equals('device-001'));
      expect(subscription.clientId, equals('client-abc'));
    });
  });
}

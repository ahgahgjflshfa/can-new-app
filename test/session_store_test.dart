import 'dart:convert';

import 'package:can_new_app/models/app_session.dart';
import 'package:can_new_app/models/can_session.dart';
import 'package:can_new_app/models/can_user_profile.dart';
import 'package:can_new_app/models/charge_session.dart';
import 'package:can_new_app/models/charge_user_profile.dart';
import 'package:can_new_app/models/user_profile.dart';
import 'package:can_new_app/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements SecureStorageAdapter {
  final values = <String, String>{};
  final failWrites = <String>{};
  final failDeletes = <String>{};
  final deleteAttempts = <String>[];

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrites.contains(key)) throw StateError('write failed');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    deleteAttempts.add(key);
    if (failDeletes.contains(key)) throw StateError('delete failed');
    values.remove(key);
  }
}

const _session = AppSession(
  token: 'token-1',
  user: UserProfile(
    name: 'Staff',
    stationId: 'A01',
    sectionId: null,
    role: 'staff',
  ),
  deviceId: 'device-1',
);

void main() {
  test('tombstone takes precedence over legacy credentials', () async {
    final storage = _MemoryStorage()
      ..values['limabang.token'] = 'legacy'
      ..values['limabang.user'] = jsonEncode(_session.user.toJson())
      ..values['limabang.session.v1'] = '{"version":1,"status":"loggedOut"}';

    expect(await SecureSessionStore(adapter: storage).loadSession(), isNull);
  });

  test(
    'active save replaces a tombstone with one authoritative payload',
    () async {
      final storage = _MemoryStorage()
        ..values['limabang.session.v1'] = '{"version":1,"status":"loggedOut"}';
      final store = SecureSessionStore(adapter: storage);

      await store.saveSession(_session);

      expect(
        (jsonDecode(storage.values['limabang.session.v1']!) as Map)['status'],
        'active',
      );
      expect((await store.loadSession())!.token, 'token-1');
    },
  );

  test('tombstone write failure does not attempt legacy cleanup', () async {
    final storage = _MemoryStorage()
      ..values['limabang.token'] = 'legacy'
      ..values['limabang.user'] = jsonEncode(_session.user.toJson())
      ..failWrites.add('limabang.session.v1');

    await expectLater(
      SecureSessionStore(adapter: storage).clearSession(),
      throwsStateError,
    );
    expect(storage.deleteAttempts, isEmpty);
    expect(storage.values['limabang.token'], 'legacy');
  });

  test(
    'legacy session load without an envelope migrates to active envelope',
    () async {
      final storage = _MemoryStorage()
        ..values['limabang.token'] = _session.token
        ..values['limabang.user'] = jsonEncode(_session.user.toJson())
        ..values['session.deviceId'] = _session.deviceId;

      expect(
        (await SecureSessionStore(adapter: storage).loadSession())!.token,
        _session.token,
      );
      expect(
        (jsonDecode(storage.values['limabang.session.v1']!) as Map)['status'],
        'active',
      );
    },
  );

  test('cleanup deletion faults do not undo a committed tombstone', () async {
    final storage = _MemoryStorage()
      ..values['limabang.token'] = 'legacy'
      ..values['limabang.user'] = jsonEncode(_session.user.toJson())
      ..failDeletes.add('limabang.token');
    final store = SecureSessionStore(adapter: storage);

    await store.clearSession();

    expect(
      (jsonDecode(storage.values['limabang.session.v1']!) as Map)['status'],
      'loggedOut',
    );
    expect(await store.loadSession(), isNull);
    expect(storage.values['session.deviceId'], isNull);
  });

  test('malformed envelope fails closed without legacy fallback', () async {
    final storage = _MemoryStorage()
      ..values['limabang.session.v1'] = '{not-json'
      ..values['limabang.token'] = 'legacy'
      ..values['limabang.user'] = jsonEncode(_session.user.toJson());

    expect(await SecureSessionStore(adapter: storage).loadSession(), isNull);
  });

  test('clearing one system leaves the other two sessions valid', () async {
    final storage = _MemoryStorage();
    final store = SecureSessionStore(adapter: storage);
    await store.saveSession(_session);
    await store.saveCanSession(
      const CanSession(
        token: 'can-token',
        user: CanUserProfile(account: 'can', station: 'A01', topic: 'can_A01'),
        deviceId: 'can-device',
      ),
    );
    await store.saveChargeSession(
      const ChargeSession(
        token: 'charge-token',
        user: ChargeUserProfile(account: 'charge', station: 'A02'),
        deviceId: 'charge-device',
      ),
    );

    await store.clearCanSession();

    expect((await store.loadSession())!.token, _session.token);
    expect((await store.loadChargeSession())!.token, 'charge-token');
    expect(await store.loadCanSession(), isNull);
  });

  test(
    'CAN and Charge tombstones are isolated and Charge retains device ID',
    () async {
      final storage = _MemoryStorage()
        ..values['charge.deviceId'] = 'charge-device';
      final store = SecureSessionStore(adapter: storage);
      await store.saveCanSession(
        const CanSession(
          token: 'can-token',
          user: CanUserProfile(
            account: 'can',
            station: 'A01',
            topic: 'can_A01',
          ),
          deviceId: 'can-device',
        ),
      );
      await store.saveChargeSession(
        const ChargeSession(
          token: 'charge-token',
          user: ChargeUserProfile(account: 'charge', station: 'A02'),
          deviceId: 'charge-device',
        ),
      );

      await store.clearCanSession();
      await store.clearChargeSession();

      expect(await store.loadCanSession(), isNull);
      expect(await store.loadChargeSession(), isNull);
      expect(storage.values['charge.deviceId'], 'charge-device');
      expect(
        (jsonDecode(storage.values['can.session.v1']!) as Map)['status'],
        'loggedOut',
      );
      expect(
        (jsonDecode(storage.values['charge.session.v1']!) as Map)['status'],
        'loggedOut',
      );
    },
  );
}

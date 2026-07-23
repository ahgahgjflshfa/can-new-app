import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_session.dart';
import '../models/can_session.dart';
import '../models/can_user_profile.dart';
import '../models/charge_session.dart';
import '../models/charge_user_profile.dart';
import '../models/user_profile.dart';
import 'app_logger.dart';

abstract class SessionStore {
  Future<String> getOrCreateDeviceId();
  Future<AppSession?> loadSession();
  Future<void> saveSession(AppSession session);
  Future<void> clearSession();
  Future<CanSession?> loadCanSession();
  Future<void> saveCanSession(CanSession session);
  Future<void> clearCanSession();
  Future<ChargeSession?> loadChargeSession();
  Future<void> saveChargeSession(ChargeSession session);
  Future<void> clearChargeSession();
}

abstract interface class SecureStorageAdapter {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class _FlutterSecureStorageAdapter implements SecureStorageAdapter {
  _FlutterSecureStorageAdapter(this.storage);
  final FlutterSecureStorage storage;

  @override
  Future<String?> read({required String key}) => storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => storage.delete(key: key);
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({
    FlutterSecureStorage? storage,
    SecureStorageAdapter? adapter,
  }) : _storage =
           adapter ??
           _FlutterSecureStorageAdapter(
             storage ?? const FlutterSecureStorage(),
           );

  static const _limabangTokenKey = 'limabang.token';
  static const _limabangUserKey = 'limabang.user';
  static const _canTokenKey = 'can.token';
  static const _canUserKey = 'can.user';
  static const _chargeTokenKey = 'charge.token';
  static const _chargeUserKey = 'charge.user';
  static const _chargeDeviceIdKey = 'charge.deviceId';
  static const _deviceIdKey = 'session.deviceId';
  static const _limabangEnvelopeKey = 'limabang.session.v1';
  static const _canEnvelopeKey = 'can.session.v1';
  static const _chargeEnvelopeKey = 'charge.session.v1';

  static const Map<String, Object?> _loggedOutPayload = {
    'version': 1,
    'status': 'loggedOut',
  };

  final SecureStorageAdapter _storage;

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final next = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
    await _storage.write(key: _deviceIdKey, value: next);
    return next;
  }

  @override
  Future<AppSession?> loadSession() async {
    final envelope = await _readEnvelope(_limabangEnvelopeKey);
    if (envelope != null) {
      if (_isLoggedOut(envelope)) return null;
      return _activeSession(
        envelope,
        (token, user, deviceId) => AppSession(
          token: token,
          user: UserProfile.fromJson(user),
          deviceId: deviceId,
        ),
      );
    }
    final token = await _storage.read(key: _limabangTokenKey);
    final userJson = await _storage.read(key: _limabangUserKey);
    final deviceId = await getOrCreateDeviceId();
    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, Object?>) return null;
      final session = AppSession(
        token: token,
        user: UserProfile.fromJson(decoded),
        deviceId: deviceId,
      );
      await _migrate(_limabangEnvelopeKey, _activePayload(session));
      return session;
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'failed to restore limabang session error=$error',
      );
      return null;
    }
  }

  @override
  Future<void> saveSession(AppSession session) =>
      _writeEnvelope(_limabangEnvelopeKey, _activePayload(session));

  @override
  Future<void> clearSession() async {
    await _writeEnvelope(_limabangEnvelopeKey, _loggedOutPayload);
    unawaited(_bestEffortDelete([_limabangTokenKey, _limabangUserKey]));
  }

  @override
  Future<CanSession?> loadCanSession() async {
    final envelope = await _readEnvelope(_canEnvelopeKey);
    if (envelope != null) {
      if (_isLoggedOut(envelope)) return null;
      return _activeSession(
        envelope,
        (token, user, deviceId) => CanSession(
          token: token,
          user: CanUserProfile.fromJson(user),
          deviceId: deviceId,
        ),
      );
    }
    final token = await _storage.read(key: _canTokenKey);
    final userJson = await _storage.read(key: _canUserKey);
    final deviceId = await getOrCreateDeviceId();
    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, Object?>) return null;
      final session = CanSession(
        token: token,
        user: CanUserProfile.fromJson(decoded),
        deviceId: deviceId,
      );
      await _migrate(_canEnvelopeKey, _activePayload(session));
      return session;
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'failed to restore can session error=$error',
      );
      return null;
    }
  }

  @override
  Future<void> saveCanSession(CanSession session) =>
      _writeEnvelope(_canEnvelopeKey, _activePayload(session));

  @override
  Future<void> clearCanSession() async {
    await _writeEnvelope(_canEnvelopeKey, _loggedOutPayload);
    unawaited(_bestEffortDelete([_canTokenKey, _canUserKey]));
  }

  @override
  Future<ChargeSession?> loadChargeSession() async {
    final envelope = await _readEnvelope(_chargeEnvelopeKey);
    if (envelope != null) {
      if (_isLoggedOut(envelope)) return null;
      return _activeSession(
        envelope,
        (token, user, deviceId) => ChargeSession(
          token: token,
          user: ChargeUserProfile.fromJson(user),
          deviceId: deviceId,
        ),
      );
    }
    final token = await _storage.read(key: _chargeTokenKey);
    final userJson = await _storage.read(key: _chargeUserKey);
    final deviceId = await _storage.read(key: _chargeDeviceIdKey);
    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty ||
        deviceId == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, Object?>) return null;
      final session = ChargeSession(
        token: token,
        user: ChargeUserProfile.fromJson(decoded),
        deviceId: deviceId,
      );
      await _migrate(_chargeEnvelopeKey, _activePayload(session));
      return session;
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'failed to restore charge session error=$error',
      );
      return null;
    }
  }

  @override
  Future<void> saveChargeSession(ChargeSession session) =>
      _writeEnvelope(_chargeEnvelopeKey, _activePayload(session));

  @override
  Future<void> clearChargeSession() async {
    await _writeEnvelope(_chargeEnvelopeKey, _loggedOutPayload);
    unawaited(_bestEffortDelete([_chargeTokenKey, _chargeUserKey]));
  }

  Map<String, Object?> _activePayload(Object session) {
    if (session is AppSession) {
      return _payload(session.token, session.user.toJson(), session.deviceId);
    }
    if (session is CanSession) {
      return _payload(session.token, session.user.toJson(), session.deviceId);
    }
    if (session is ChargeSession) {
      return _payload(session.token, session.user.toJson(), session.deviceId);
    }
    throw ArgumentError.value(session, 'session');
  }

  Map<String, Object?> _payload(
    String token,
    Map<String, Object?> user,
    String deviceId,
  ) => <String, Object?>{
    'version': 1,
    'status': 'active',
    'token': token,
    'user': user,
    'deviceId': deviceId,
  };

  Future<Map<String, Object?>?> _readEnvelope(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Object?>{};
      final envelope = Map<String, Object?>.from(decoded);
      if (envelope['version'] != 1 ||
          (envelope['status'] != 'active' &&
              envelope['status'] != 'loggedOut')) {
        return <String, Object?>{};
      }
      if (envelope['status'] == 'loggedOut') return envelope;
      if (envelope['token'] is! String ||
          (envelope['token'] as String).isEmpty ||
          envelope['user'] is! Map ||
          envelope['deviceId'] is! String ||
          (envelope['deviceId'] as String).isEmpty) {
        return <String, Object?>{};
      }
      return envelope;
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'invalid session envelope key=$key error=$error',
      );
      return <String, Object?>{};
    }
  }

  T? _activeSession<T>(
    Map<String, Object?> envelope,
    T Function(String token, Map<String, Object?> user, String deviceId) build,
  ) {
    try {
      if (envelope['status'] != 'active' ||
          envelope['token'] is! String ||
          envelope['user'] is! Map ||
          envelope['deviceId'] is! String) {
        return null;
      }
      return build(
        envelope['token'] as String,
        Map<String, Object?>.from(envelope['user'] as Map),
        envelope['deviceId'] as String,
      );
    } on Object catch (error) {
      AppLogger.log('SessionStore', 'invalid active session error=$error');
      return null;
    }
  }

  bool _isLoggedOut(Map<String, Object?> envelope) =>
      envelope['status'] == 'loggedOut';

  Future<void> _writeEnvelope(String key, Map<String, Object?> payload) =>
      _storage.write(key: key, value: jsonEncode(payload));

  Future<void> _migrate(String key, Map<String, Object?> payload) async {
    try {
      await _writeEnvelope(key, payload);
    } catch (error) {
      AppLogger.log(
        'SessionStore',
        'legacy session migration failed key=$key error=$error',
      );
    }
  }

  Future<void> _bestEffortDelete(List<String> keys) async {
    for (final key in keys) {
      try {
        await _storage.delete(key: key);
      } catch (error) {
        AppLogger.log(
          'SessionStore',
          'legacy session cleanup failed key=$key error=$error',
        );
      }
    }
  }
}

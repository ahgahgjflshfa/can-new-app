import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_session.dart';
import '../models/can_session.dart';
import '../models/can_user_profile.dart';
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
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _limabangTokenKey = 'limabang.token';
  static const _limabangUserKey = 'limabang.user';
  static const _canTokenKey = 'can.token';
  static const _canUserKey = 'can.user';
  static const _deviceIdKey = 'session.deviceId';

  final FlutterSecureStorage _storage;

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final next = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
    await _storage.write(key: _deviceIdKey, value: next);
    return next;
  }

  @override
  Future<AppSession?> loadSession() async {
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
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return AppSession(
        token: token,
        user: UserProfile.fromJson(decoded),
        deviceId: deviceId,
      );
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'failed to restore limabang session error=$error',
      );
      await clearSession();
      return null;
    }
  }

  @override
  Future<void> saveSession(AppSession session) async {
    await _storage.write(key: _limabangTokenKey, value: session.token);
    await _storage.write(
      key: _limabangUserKey,
      value: jsonEncode(session.user.toJson()),
    );
    await _storage.write(key: _deviceIdKey, value: session.deviceId);
  }

  @override
  Future<void> clearSession() async {
    await _storage.delete(key: _limabangTokenKey);
    await _storage.delete(key: _limabangUserKey);
  }

  @override
  Future<CanSession?> loadCanSession() async {
    final token = await _storage.read(key: _canTokenKey);
    final userJson = await _storage.read(key: _canUserKey);
    final deviceId = await getOrCreateDeviceId();
    AppLogger.log(
      'SessionStore',
      'loadCanSession token=${token != null ? 'exists' : 'null'} userJson=${userJson != null ? 'exists' : 'null'}',
    );
    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, Object?>) {
        AppLogger.log(
          'SessionStore',
          'loadCanSession decoded type=${decoded.runtimeType}',
        );
        return null;
      }
      final session = CanSession(
        token: token,
        user: CanUserProfile.fromJson(decoded),
        deviceId: deviceId,
      );
      AppLogger.log(
        'SessionStore',
        'loadCanSession restored account=${session.user.account}',
      );
      return session;
    } on Object catch (error) {
      AppLogger.log(
        'SessionStore',
        'failed to restore can session error=$error',
      );
      await clearCanSession();
      return null;
    }
  }

  @override
  Future<void> saveCanSession(CanSession session) async {
    await _storage.write(key: _canTokenKey, value: session.token);
    await _storage.write(
      key: _canUserKey,
      value: jsonEncode(session.user.toJson()),
    );
    await _storage.write(key: _deviceIdKey, value: session.deviceId);
    AppLogger.log(
      'SessionStore',
      'saveCanSession account=${session.user.account} token_length=${session.token.length}',
    );
  }

  @override
  Future<void> clearCanSession() async {
    await _storage.delete(key: _canTokenKey);
    await _storage.delete(key: _canUserKey);
  }
}

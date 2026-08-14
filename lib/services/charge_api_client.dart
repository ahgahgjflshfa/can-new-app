import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/charge_task.dart';
import '../models/charge_user_profile.dart';
import 'api_exception.dart';
import 'app_logger.dart';
import 'charge_api.dart';

const chargeBaseUrl = 'https://www.tymetro.com.tw/can_api/api';
const chargeApiTimeout = Duration(seconds: 12);

class ChargeApiClient implements ChargeApi {
  ChargeApiClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = chargeApiTimeout;
  }

  final HttpClient _httpClient;
  String? _token;

  @override
  String? get token => _token;

  @override
  void restoreToken(String token) => _token = token;

  @override
  void invalidateToken({String? token}) {
    if (token == null || _token == token) _token = null;
  }

  @override
  Future<ChargeUserProfile> login({
    required String account,
    required String password,
  }) async {
    final data = _asMap(
      await _send(
        'POST',
        '/auth/login',
        body: {'account': account, 'password': password},
        includeAuth: false,
      ),
    );
    if (data['system'] != 'charge') {
      throw const ApiException('登入系統不符，這不是 Charge 帳號');
    }
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException('登入成功但未取得 Token');
    }
    final profile = ChargeUserProfile.fromJson(data);
    _token = accessToken;
    return profile;
  }

  @override
  Future<void> logout({String? token}) async {
    if (token == null || _token == token) _token = null;
  }

  @override
  Future<List<ChargeTask>> fetchTasks() async {
    final payload = await _send('GET', '/charge/task');
    if (payload is! List) throw const ApiException('Charge 任務資料格式錯誤');
    return payload
        .map((item) => ChargeTask.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  @override
  Future<ChargeTask> fetchTask(int serialNumber) async {
    final payload = await _send('GET', '/charge/task/$serialNumber');
    return ChargeTask.fromJson(_asMap(payload));
  }

  @override
  Future<void> updateTask(int serialNumber, {required bool isDone}) async {
    await _send(
      'PATCH',
      '/charge/task/$serialNumber',
      body: {'isDone': isDone},
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool includeAuth = true,
  }) async {
    if (includeAuth && (_token == null || _token!.isEmpty)) {
      throw const ApiException('尚未登入，請重新登入');
    }
    final uri = Uri.parse('$chargeBaseUrl$path');
    try {
      final request = await _httpClient
          .openUrl(method, uri)
          .timeout(chargeApiTimeout);
      request.headers.contentType = ContentType.json;
      if (includeAuth) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.contentLength = bytes.length;
        request.add(bytes);
      } else {
        request.contentLength = 0;
      }
      final response = await request.close().timeout(chargeApiTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(chargeApiTimeout);
      final decoded = responseBody.isEmpty
          ? <String, Object?>{}
          : jsonDecode(responseBody);
      if (response.statusCode >= 400 ||
          (decoded is Map && decoded['status'] == 'error')) {
        final message = decoded is Map ? decoded['message'] as String? : null;
        throw ApiException(message ?? '操作失敗');
      }
      if (decoded is! Map && decoded is! List) {
        throw const ApiException('伺服器回應格式錯誤');
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('連線逾時，請確認網路或稍後再試');
    } on SocketException catch (error) {
      AppLogger.log(
        'ChargeApi',
        'network error=$error method=$method path=$path',
      );
      rethrow;
    } on FormatException catch (error) {
      throw ApiException('伺服器回應不是有效 JSON: $error');
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  throw const ApiException('Charge 資料格式錯誤');
}

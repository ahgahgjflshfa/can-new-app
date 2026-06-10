import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/assist_task.dart';
import '../models/completion_result.dart';
import '../models/user_profile.dart';
import 'api_exception.dart';
import 'api_log_store.dart';
import 'app_logger.dart';
import 'limabang_api.dart';

const limabangBaseUrl = 'https://www-u.tymetro.com.tw/station_services/api';
const limabangApiTimeout = Duration(seconds: 12);

class LimabangApiClient implements LimabangApi {
  LimabangApiClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = limabangApiTimeout;
  }

  final HttpClient _httpClient;
  String? _token;

  @override
  String? get token => _token;

  @override
  void restoreToken(String token) {
    _token = token;
  }

  @override
  Future<UserProfile> login({
    required String account,
    required String password,
    required String deviceType,
    required String deviceId,
    String? fcmToken,
  }) async {
    final body = <String, Object?>{
      'account': account,
      'password': password,
      'device_type': deviceType,
      'device_id': deviceId,
    };
    if (fcmToken != null && fcmToken.isNotEmpty) {
      body['fcm_token'] = fcmToken;
    }
    final payload = await _send(
      'POST',
      '/auth/login',
      body: body,
      includeAuth: false,
    );
    final data = _readMap(payload['data'], 'data');
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException('登入成功但未取得 Token');
    }
    _token = token;
    return UserProfile.fromJson(_readMap(data['user'], 'user'));
  }

  @override
  Future<void> logout() async {
    if (_token == null) {
      return;
    }
    try {
      await _send('POST', '/auth/logout');
    } finally {
      _token = null;
    }
  }

  @override
  Future<List<AssistTask>> fetchTasks() async {
    final payload = await _send('GET', '/tasks');
    final data = payload['data'];
    if (data is! List) {
      throw const ApiException('任務資料格式錯誤');
    }
    return data
        .map((item) => AssistTask.fromJson(_readMap(item, 'task')))
        .toList(growable: false);
  }

  @override
  Future<void> replyTask(int id) async {
    await _send('POST', '/tasks/$id/reply', body: <String, Object?>{});
  }

  @override
  Future<void> completeTask(int id, CompletionResult result) async {
    await _send('POST', '/tasks/$id/complete', body: {'result': result.value});
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool includeAuth = true,
  }) async {
    final token = _token;
    if (includeAuth && (token == null || token.isEmpty)) {
      throw const ApiException('尚未登入，請重新登入');
    }

    final requestUri = Uri.parse('$limabangBaseUrl$path');
    final stopwatch = Stopwatch()..start();
    final safeBody = _redactBody(body);
    final apiLog = ApiLogStore.start(
      method: method,
      path: path,
      fullUrl: requestUri.toString(),
      requestBody: safeBody,
    );
    _log(
      'START $method $requestUri auth=$includeAuth body=${_safeBodyKeys(body)}',
    );

    try {
      _log('OPEN  $method $path');
      final request = await _httpClient
          .openUrl(method, requestUri)
          .timeout(limabangApiTimeout);
      _log('OPENED ${stopwatch.elapsedMilliseconds}ms $method $path');
      request.headers.contentType = ContentType.json;
      if (includeAuth) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        final bodyBytes = utf8.encode(jsonEncode(body));
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
        _log('BODY_OUT ${bodyBytes.length} bytes $method $path');
      } else {
        request.contentLength = 0;
      }

      _log('SEND  $method $path');
      final response = await request.close().timeout(limabangApiTimeout);
      _log(
        'HEAD  ${response.statusCode} ${stopwatch.elapsedMilliseconds}ms $method $path',
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(limabangApiTimeout);
      _log(
        'BODY  ${responseBody.length} bytes ${stopwatch.elapsedMilliseconds}ms $method $path',
      );
      final decoded = responseBody.isEmpty
          ? <String, Object?>{}
          : jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        ApiLogStore.fail(
          apiLog,
          error: '伺服器回應格式錯誤',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
        throw const ApiException('伺服器回應格式錯誤');
      }
      final status = decoded['status'];
      if (status == 'error' || response.statusCode >= 400) {
        final message = decoded['message'] as String? ?? '操作失敗';
        _log('ERROR api_status=$status message=$message $method $path');
        ApiLogStore.fail(
          apiLog,
          error: message,
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
        throw ApiException(message);
      }
      _log('DONE  ${stopwatch.elapsedMilliseconds}ms $method $path');
      ApiLogStore.complete(
        apiLog,
        statusCode: response.statusCode,
        responseBody: responseBody,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return decoded;
    } on ApiException {
      if (apiLog.durationMs == null) {
        ApiLogStore.fail(
          apiLog,
          error: 'API 錯誤',
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }
      rethrow;
    } on FormatException catch (error) {
      _log(
        'FAIL  invalid_json ${stopwatch.elapsedMilliseconds}ms $method $path error=$error',
      );
      ApiLogStore.fail(
        apiLog,
        error: '伺服器回應不是有效 JSON: $error',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      throw const ApiException('伺服器回應不是有效 JSON');
    } on TimeoutException catch (error) {
      _log(
        'FAIL  timeout ${stopwatch.elapsedMilliseconds}ms $method $path error=$error',
      );
      ApiLogStore.fail(
        apiLog,
        error: '連線逾時',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      throw const ApiException('連線逾時，請確認網路或稍後再試');
    } on HandshakeException catch (error) {
      _log(
        'FAIL  tls ${stopwatch.elapsedMilliseconds}ms $method $path error=$error',
      );
      ApiLogStore.fail(
        apiLog,
        error: 'TLS/憑證連線失敗: $error',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      throw const ApiException('TLS/憑證連線失敗');
    } on SocketException catch (error) {
      _log(
        'FAIL  socket ${stopwatch.elapsedMilliseconds}ms $method $path error=$error',
      );
      ApiLogStore.fail(
        apiLog,
        error: '網路連線失敗: $error',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }
}

String _safeBodyKeys(Map<String, Object?>? body) {
  if (body == null || body.isEmpty) {
    return 'none';
  }
  return body.keys
      .map((key) => key == 'password' ? 'password:redacted' : key)
      .join(',');
}

String? _redactBody(Map<String, Object?>? body) {
  if (body == null || body.isEmpty) {
    return null;
  }
  final safe = body.map((key, value) {
    if (key == 'password') {
      return MapEntry(key, '***');
    }
    return MapEntry(key, value);
  });
  return jsonEncode(safe);
}

void _log(String message) {
  AppLogger.log('LimabangApi', message);
}

Map<String, Object?> _readMap(Object? value, String name) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  throw ApiException('$name 資料格式錯誤');
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/can_task.dart';
import '../models/can_user_profile.dart';
import 'api_exception.dart';
import 'api_log_store.dart';
import 'app_logger.dart';
import 'can_api.dart';

const canBaseUrl = 'https://www-u.tymetro.com.tw/can_api/api';
const canApiTimeout = Duration(seconds: 12);

class CanHttpResponse {
  const CanHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

typedef CanHttpTransport =
    Future<CanHttpResponse> Function(
      String method,
      Uri uri,
      String? token,
      Map<String, Object?>? body,
    );

class CanApiClient implements CanApi {
  CanApiClient({HttpClient? httpClient, CanHttpTransport? transport})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = canApiTimeout;
    _transport = transport;
  }

  final HttpClient _httpClient;
  late final CanHttpTransport? _transport;
  String? _token;

  @override
  String? get token => _token;

  @override
  void restoreToken(String token) {
    _token = token;
  }

  @override
  void invalidateToken({String? token}) {
    if (token == null || _token == token) _token = null;
  }

  @override
  Future<CanUserProfile> login({
    required String account,
    required String password,
  }) async {
    final payload = await _send(
      'POST',
      '/auth/login',
      body: <String, Object?>{'account': account, 'password': password},
      includeAuth: false,
    );
    final data = _readMap(payload, 'login response');
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException('登入成功但未取得 Token');
    }
    _token = accessToken;

    // Backend now returns account/station/topic directly in login response.
    return CanUserProfile.fromJson(data);
  }

  @override
  Future<void> logout({String? token}) async {
    if (token == null || _token == token) _token = null;
  }

  @override
  Future<List<CanTask>> fetchTasks() async {
    final payload = await _send('GET', '/task');
    if (payload is! List) {
      throw const ApiException('任務資料格式錯誤');
    }
    return payload
        .map((item) => CanTask.fromJson(_readMap(item, 'task')))
        .toList(growable: false);
  }

  @override
  Future<List<CanTask>> fetchTasksByStation(String stationCode) async {
    final payload = await _send('GET', '/task/station/$stationCode');
    if (payload is! List) {
      throw const ApiException('任務資料格式錯誤');
    }
    return payload
        .map((item) => CanTask.fromJson(_readMap(item, 'task')))
        .toList(growable: false);
  }

  @override
  Future<void> updateTask(
    int serialNumber, {
    required bool isDone,
    required int resolutionType,
  }) async {
    await _send(
      'PATCH',
      '/task/$serialNumber',
      body: <String, Object?>{
        'isDone': isDone,
        'resolutionType': resolutionType,
      },
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool includeAuth = true,
  }) async {
    final token = _token;
    if (includeAuth && (token == null || token.isEmpty)) {
      throw const ApiException('尚未登入，請重新登入');
    }

    final requestUri = Uri.parse('$canBaseUrl$path');
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

    String responseBody = '';
    int statusCode = 0;
    try {
      _log('OPEN  $method $path');
      if (_transport case final transport?) {
        final response = await transport(method, requestUri, token, body);
        statusCode = response.statusCode;
        responseBody = response.body;
      } else {
        final request = await _httpClient
            .openUrl(method, requestUri)
            .timeout(canApiTimeout);
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
        final response = await request.close().timeout(canApiTimeout);
        statusCode = response.statusCode;
        responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(canApiTimeout);
      }
      _log(
        'BODY  ${responseBody.length} bytes ${stopwatch.elapsedMilliseconds}ms $method $path',
      );
      if (statusCode == HttpStatus.badGateway ||
          statusCode == HttpStatus.serviceUnavailable ||
          statusCode == HttpStatus.gatewayTimeout) {
        ApiLogStore.fail(
          apiLog,
          error: '伺服器無回應',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: statusCode,
          responseBody: responseBody,
        );
        throw const ApiException('伺服器無回應，請確認網路或稍後再試');
      }
      if (statusCode >= HttpStatus.internalServerError) {
        ApiLogStore.fail(
          apiLog,
          error: '伺服器暫時異常',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: statusCode,
          responseBody: responseBody,
        );
        throw const ApiException('伺服器暫時異常，請稍後再試');
      }
      if (statusCode == HttpStatus.unauthorized && includeAuth) {
        throw const SessionExpiredException();
      }
      final decoded = responseBody.isEmpty
          ? <String, Object?>{}
          : jsonDecode(responseBody);
      if (decoded is Map<String, Object?>) {
        final status = decoded['status'];
        if (status == 'error' || statusCode >= 400) {
          final message = decoded['message'] as String? ?? '操作失敗';
          _log('ERROR api_status=$status message=$message $method $path');
          ApiLogStore.fail(
            apiLog,
            error: message,
            durationMs: stopwatch.elapsedMilliseconds,
            statusCode: statusCode,
            responseBody: responseBody,
          );
          throw ApiException(message);
        }
      } else if (decoded is! List) {
        ApiLogStore.fail(
          apiLog,
          error: '伺服器回應格式錯誤',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: statusCode,
          responseBody: responseBody,
        );
        throw ApiException('伺服器回應格式錯誤: $responseBody');
      }
      _log('DONE  ${stopwatch.elapsedMilliseconds}ms $method $path');
      ApiLogStore.complete(
        apiLog,
        statusCode: statusCode,
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
      if (statusCode >= HttpStatus.internalServerError) {
        ApiLogStore.fail(
          apiLog,
          error: '伺服器無回應',
          durationMs: stopwatch.elapsedMilliseconds,
          statusCode: statusCode,
          responseBody: responseBody,
        );
        throw const ApiException('伺服器無回應，請確認網路或稍後再試');
      }
      final preview = responseBody.length > 500
          ? '${responseBody.substring(0, 500)}...'
          : responseBody;
      _log(
        'FAIL  invalid_json ${stopwatch.elapsedMilliseconds}ms $method $path error=$error body_preview=${preview.substring(0, preview.length > 200 ? 200 : preview.length)}',
      );
      ApiLogStore.fail(
        apiLog,
        error: '伺服器回應不是有效 JSON: $error',
        durationMs: stopwatch.elapsedMilliseconds,
        responseBody: responseBody,
      );
      throw ApiException('伺服器回應不是有效 JSON: $error\n原始回應:\n$preview');
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
  AppLogger.log('CanApi', message);
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

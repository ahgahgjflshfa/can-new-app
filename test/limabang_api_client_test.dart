import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:can_new_app/services/api_exception.dart';
import 'package:can_new_app/services/api_log_store.dart';
import 'package:can_new_app/services/limabang_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated 401 is typed, clears token, and logs once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var requestCount = 0;
    server.listen((request) {
      requestCount++;
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(requestCount == 1 ? '{bad' : '{}');
      request.response.close();
    });
    final client = LimabangApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    client.restoreToken('old-token');
    ApiLogStore.clear();

    await expectLater(
      client.fetchTasks(),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(client.token, isNull);
    expect(ApiLogStore.entries.value, hasLength(1));

    client.restoreToken('new-token');
    await expectLater(
      client.fetchTasks(),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(client.token, isNull);
  });

  test('login 401 remains an ordinary ApiException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'status': 'error', 'message': '帳密錯誤'}),
      );
      request.response.close();
    });
    final client = LimabangApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
    );

    await expectLater(
      client.login(
        account: 'staff01',
        password: 'bad',
        deviceType: 'test',
        deviceId: 'device',
      ),
      throwsA(
        isA<ApiException>().having((error) => error.message, 'message', '帳密錯誤'),
      ),
    );
    expect(client.token, isNull);
  });

  test('stale authenticated 401 cannot clear a newer token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requestSeen = Completer<void>();
    server.listen((request) async {
      requestSeen.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.close();
    });
    final client = LimabangApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..restoreToken('old-token');

    final request = client.fetchTasks();
    await requestSeen.future;
    client.restoreToken('new-token');

    await expectLater(request, throwsA(isA<SessionExpiredException>()));
    expect(client.token, 'new-token');
  });

  test('delayed remote logout cannot clear a newly logged-in token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requestSeen = Completer<void>();
    server.listen((request) async {
      requestSeen.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response.statusCode = HttpStatus.ok;
      request.response.write('{}');
      await request.response.close();
    });
    final client = LimabangApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..restoreToken('old-token');

    final logout = client.logout(token: 'old-token');
    await requestSeen.future;
    client.restoreToken('new-token');
    await logout;

    expect(client.token, 'new-token');
  });

  test('authenticated 403 remains ordinary and preserves token', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'status': 'error', 'message': '禁止存取'}),
      );
      request.response.close();
    });
    final client = LimabangApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..restoreToken('valid-token');

    await expectLater(
      client.fetchTasks(),
      throwsA(
        isA<ApiException>().having((error) => error.message, 'message', '禁止存取'),
      ),
    );
    expect(client.token, 'valid-token');
  });
}

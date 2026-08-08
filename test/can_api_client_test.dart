import 'dart:convert';

import 'package:can_new_app/services/can_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'login preserves regional fields and task loading uses GET /task',
    () async {
      final requests = <({String method, String path, String? token})>[];
      final client = CanApiClient(
        transport: (method, uri, token, body) async {
          requests.add((method: method, path: uri.path, token: token));
          if (uri.path.endsWith('/auth/login')) {
            return CanHttpResponse(
              200,
              jsonEncode({
                'access_token': 'token',
                'account': 'North',
                'station': null,
                'accessScope': 'region',
                'region': 'north',
                'topic': 'can_region_north',
                'system': 'can',
              }),
            );
          }
          return CanHttpResponse(
            200,
            jsonEncode([
              {
                'serialNumber': 1,
                'station': 'A01',
                'trashBin': 'A01-B1',
                'isDone': false,
                'informTime': 0,
                'resolutionType': 0,
                'isDisable': false,
                'createdAt': '',
                'updatedAt': '',
              },
            ]),
          );
        },
      );

      final user = await client.login(account: 'North', password: 'password');
      final tasks = await client.fetchTasks();

      expect(user.station, isNull);
      expect(user.accessScope, 'region');
      expect(user.region, 'north');
      expect(user.topic, 'can_region_north');
      expect(user.system, 'can');
      expect(tasks, hasLength(1));
      expect(requests, [
        (method: 'POST', path: '/can_api/api/auth/login', token: null),
        (method: 'GET', path: '/can_api/api/task', token: 'token'),
      ]);
    },
  );
}

import 'package:can_new_app/models/charge_task.dart';
import 'package:can_new_app/services/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'scoped refresh events remain distinct for repeated same-system pushes',
    () {
      const first = PushRefreshEvent(sequence: 1, system: PushSystem.can);
      const second = PushRefreshEvent(sequence: 2, system: PushSystem.can);

      expect(first.system, PushSystem.can);
      expect(second.system, PushSystem.can);
      expect(second.sequence, isNot(first.sequence));
    },
  );

  test('Charge task parses the current boolean completion contract', () {
    final task = ChargeTask.fromJson(const {
      'serialNumber': 1,
      'deviceCode': 'CH-1',
      'station': 'A1',
      'isDone': true,
      'cleanAt': '2026-08-08T00:00:00.000Z',
      'informTime': 1,
      'isDisable': false,
    });

    expect(task.isDone, isTrue);
    expect(task.cleanAt, '2026-08-08T00:00:00.000Z');
    expect(task.informTime, 1);
    expect(task.isPending, isFalse);
    expect(task.toJson()['isDone'], isTrue);
    expect(task.toJson().containsKey('faultType'), isFalse);
  });
}

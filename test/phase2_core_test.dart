import 'package:can_new_app/models/charge_task.dart';
import 'package:can_new_app/models/charge_task_status.dart';
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

  test('Charge status parsing and serialization fail closed explicitly', () {
    final task = ChargeTask.fromJson(const {
      'serialNumber': 1,
      'deviceCode': 'CH-1',
      'station': 'A1',
      'status': 'not-a-real-status',
      'resolutionType': 0,
      'isDisable': false,
    });

    expect(task.status, ChargeTaskStatus.unknown);
    expect(task.toJson()['status'], ChargeTaskStatus.unknown.value);
    expect(
      ChargeTaskStatus.fromValue('processing'),
      ChargeTaskStatus.processing,
    );
  });
}

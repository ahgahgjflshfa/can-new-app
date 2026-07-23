import '../models/charge_task.dart';
import '../models/charge_task_status.dart';
import '../models/charge_resolution_type.dart';
import '../models/charge_user_profile.dart';

abstract class ChargeApi {
  String? get token;
  void restoreToken(String token);

  void invalidateToken({String? token});

  Future<ChargeUserProfile> login({
    required String account,
    required String password,
  });

  Future<void> logout({String? token});
  Future<List<ChargeTask>> fetchTasks();
  Future<ChargeTask> fetchTask(int serialNumber);
  Future<void> updateTask(
    int serialNumber, {
    required ChargeTaskStatus status,
    required ChargeResolutionType resolutionType,
  });
}

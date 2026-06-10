import '../models/can_task.dart';
import '../models/can_user_profile.dart';

abstract class CanApi {
  String? get token;

  void restoreToken(String token);

  Future<CanUserProfile> login({
    required String account,
    required String password,
  });

  Future<void> logout();

  Future<List<CanTask>> fetchTasks();

  Future<List<CanTask>> fetchTasksByStation(String stationCode);

  Future<void> updateTask(
    int serialNumber, {
    required bool isDone,
    required int resolutionType,
  });
}

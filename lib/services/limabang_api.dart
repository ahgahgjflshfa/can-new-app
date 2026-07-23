import '../models/assist_task.dart';
import '../models/completion_result.dart';
import '../models/user_profile.dart';

abstract class LimabangApi {
  String? get token;

  void restoreToken(String token);

  void invalidateToken({String? token});

  Future<UserProfile> login({
    required String account,
    required String password,
    required String deviceType,
    required String deviceId,
    String? fcmToken,
  });

  Future<void> logout({String? token});

  Future<List<AssistTask>> fetchTasks();

  Future<void> replyTask(int id);

  Future<void> completeTask(int id, CompletionResult result);
}

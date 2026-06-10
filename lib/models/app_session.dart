import 'user_profile.dart';

class AppSession {
  const AppSession({
    required this.token,
    required this.user,
    required this.deviceId,
  });

  final String token;
  final UserProfile user;
  final String deviceId;
}

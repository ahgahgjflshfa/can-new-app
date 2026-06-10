import 'can_user_profile.dart';

class CanSession {
  const CanSession({
    required this.token,
    required this.user,
    required this.deviceId,
  });

  final String token;
  final CanUserProfile user;
  final String deviceId;
}

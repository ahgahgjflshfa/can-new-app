import 'charge_user_profile.dart';

class ChargeSession {
  const ChargeSession({
    required this.token,
    required this.user,
    required this.deviceId,
  });

  final String token;
  final ChargeUserProfile user;
  final String deviceId;
}

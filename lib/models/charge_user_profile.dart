class ChargeUserProfile {
  const ChargeUserProfile({
    required this.account,
    required this.station,
    this.system = 'charge',
    String? topic,
  }) : topic = 'charge_$station';

  factory ChargeUserProfile.fromJson(Map<String, Object?> json) {
    return ChargeUserProfile(
      account: json['account'] as String? ?? '',
      station: json['station'] as String? ?? '',
      system: json['system'] as String? ?? 'charge',
    );
  }

  Map<String, Object?> toJson() => {
    'account': account,
    'station': station,
    'system': system,
    'topic': topic,
  };

  final String account;
  final String station;
  final String system;
  final String topic;

  /// Charge topics are intentionally derived, not taken from the login response.
  String get chargeTopic => topic;
}

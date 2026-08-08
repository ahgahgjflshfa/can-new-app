class CanUserProfile {
  const CanUserProfile({
    required this.account,
    this.station,
    this.accessScope = 'station',
    this.region,
    this.topic,
    this.system = 'can',
  });

  factory CanUserProfile.fromJson(Map<String, Object?> json) {
    return CanUserProfile(
      account: json['account'] as String? ?? '',
      station: json['station'] as String?,
      accessScope: json['accessScope'] as String? ?? 'station',
      region: json['region'] as String?,
      topic: json['topic'] as String?,
      system: json['system'] as String? ?? 'can',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'account': account,
      'station': station,
      'accessScope': accessScope,
      'region': region,
      'topic': topic,
      'system': system,
    };
  }

  final String account;
  final String? station;
  final String accessScope;
  final String? region;

  /// Backend-provided FCM topic (already includes `can_` prefix).
  final String? topic;
  final String system;
}

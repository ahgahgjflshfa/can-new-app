class CanUserProfile {
  const CanUserProfile({
    required this.account,
    this.station,
    this.topic,
  });

  factory CanUserProfile.fromJson(Map<String, Object?> json) {
    return CanUserProfile(
      account: json['account'] as String? ?? '',
      station: json['station'] as String?,
      topic: json['topic'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'account': account,
      'station': station,
      'topic': topic,
    };
  }

  final String account;
  final String? station;

  /// Backend-provided FCM topic (already includes `can_` prefix, e.g. `can_A12`).
  final String? topic;
}

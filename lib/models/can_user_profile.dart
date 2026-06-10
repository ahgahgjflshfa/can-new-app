class CanUserProfile {
  const CanUserProfile({
    required this.account,
    this.station,
  });

  factory CanUserProfile.fromJson(Map<String, Object?> json) {
    return CanUserProfile(
      account: json['account'] as String? ?? '',
      station: json['station'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'account': account,
      'station': station,
    };
  }

  final String account;
  final String? station;
}

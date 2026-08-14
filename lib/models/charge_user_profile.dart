class ChargeUserProfile {
  const ChargeUserProfile({
    required this.account,
    this.station,
    this.accessScope = 'station',
    this.region,
    this.topic,
    this.system = 'charge',
  });

  factory ChargeUserProfile.fromJson(Map<String, Object?> json) {
    return ChargeUserProfile(
      account: json['account'] as String? ?? '',
      station: json['station'] as String?,
      accessScope: json['accessScope'] as String? ?? 'station',
      region: json['region'] as String?,
      topic: json['topic'] as String?,
      system: json['system'] as String? ?? 'charge',
    );
  }

  Map<String, Object?> toJson() => {
    'account': account,
    'station': station,
    'accessScope': accessScope,
    'region': region,
    'topic': topic,
    'system': system,
  };

  final String account;
  final String? station;
  final String accessScope;
  final String? region;
  final String? topic;
  final String system;

  /// Uses the backend topic when supplied; legacy station sessions fall back
  /// to the historical `charge_<station>` topic.
  String get chargeTopic {
    final backendTopic = topic?.trim();
    if (backendTopic != null && backendTopic.isNotEmpty) return backendTopic;
    final stationCode = station?.trim();
    return stationCode == null || stationCode.isEmpty
        ? ''
        : 'charge_$stationCode';
  }
}

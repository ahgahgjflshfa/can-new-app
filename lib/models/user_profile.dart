class UserProfile {
  const UserProfile({
    required this.name,
    required this.stationId,
    required this.sectionId,
    required this.role,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      stationId: json['station_id'] as String?,
      sectionId: json['section_id'] as String?,
      role: json['role'] as String? ?? 'staff',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'station_id': stationId,
      'section_id': sectionId,
      'role': role,
    };
  }

  final String name;
  final String? stationId;
  final String? sectionId;
  final String role;
}

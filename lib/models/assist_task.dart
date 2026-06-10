import 'task_status.dart';

class AssistTask {
  const AssistTask({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.locationName,
    required this.locationCode,
    required this.status,
    required this.createdAt,
    required this.repliedAt,
    required this.doneAt,
  });

  factory AssistTask.fromJson(Map<String, Object?> json) {
    return AssistTask(
      id: (json['id'] as num).toInt(),
      stationId: json['station_id'] as String? ?? '',
      stationName: json['station_name'] as String? ?? '',
      locationName: json['location_name'] as String? ?? '',
      locationCode: json['location_code'] as String? ?? '',
      status: TaskStatus.fromValue(json['status'] as String? ?? 'pending'),
      createdAt: _readTimestamp(json['created_at']),
      repliedAt: _readTimestamp(json['replied_at']),
      doneAt: _readTimestamp(json['done_at']),
    );
  }

  final int id;
  final String stationId;
  final String stationName;
  final String locationName;
  final String locationCode;
  final TaskStatus status;
  final DateTime? createdAt;
  final DateTime? repliedAt;
  final DateTime? doneAt;
}

DateTime? _readTimestamp(Object? value) {
  if (value == null || value == 0) {
    return null;
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String && value.isNotEmpty) {
    final numeric = int.tryParse(value);
    if (numeric != null) {
      return DateTime.fromMillisecondsSinceEpoch(numeric);
    }
    return DateTime.tryParse(value);
  }
  return null;
}

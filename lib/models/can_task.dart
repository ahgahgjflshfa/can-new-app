class CanTask {
  const CanTask({
    required this.serialNumber,
    required this.station,
    required this.trashBin,
    required this.isDone,
    this.cleanAt,
    required this.informTime,
    required this.resolutionType,
    this.visitorID,
    required this.isDisable,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CanTask.fromJson(Map<String, Object?> json) {
    return CanTask(
      serialNumber: json['serialNumber'] as int? ?? 0,
      station: json['station'] as String? ?? '',
      trashBin: json['trashBin'] as String? ?? '',
      isDone: _parseBool(json['isDone']) ?? false,
      cleanAt: json['cleanAt'] as String?,
      informTime: json['informTime'] as int? ?? 0,
      resolutionType: json['resolutionType'] as int? ?? 0,
      visitorID: json['visitorID'] as String?,
      isDisable: _parseBool(json['isDisable']) ?? false,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'serialNumber': serialNumber,
      'station': station,
      'trashBin': trashBin,
      'isDone': isDone,
      'cleanAt': cleanAt,
      'informTime': informTime,
      'resolutionType': resolutionType,
      'visitorID': visitorID,
      'isDisable': isDisable,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  final int serialNumber;
  final String station;
  final String trashBin;
  final bool isDone;
  final String? cleanAt;
  final int informTime;
  final int resolutionType;
  final String? visitorID;
  final bool isDisable;
  final String createdAt;
  final String updatedAt;

  bool get isPending => !isDone && !isDisable;
}

bool? _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return null;
}

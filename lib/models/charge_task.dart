class ChargeTask {
  const ChargeTask({
    required this.serialNumber,
    required this.deviceCode,
    required this.station,
    required this.isDone,
    this.cleanAt,
    required this.informTime,
    required this.isDisable,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChargeTask.fromJson(Map<String, Object?> json) {
    return ChargeTask(
      serialNumber: _asInt(json['serialNumber']),
      deviceCode: json['deviceCode'] as String? ?? '',
      station: json['station'] as String? ?? '',
      isDone: _parseBool(json['isDone']),
      cleanAt: json['cleanAt'] as String?,
      informTime: _asInt(json['informTime']),
      isDisable: _parseBool(json['isDisable']),
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'serialNumber': serialNumber,
    'deviceCode': deviceCode,
    'station': station,
    'isDone': isDone,
    'cleanAt': cleanAt,
    'informTime': informTime,
    'isDisable': isDisable,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  final int serialNumber;
  final String deviceCode;
  final String station;
  final bool isDone;
  final String? cleanAt;
  final int informTime;
  final bool isDisable;
  final String createdAt;
  final String updatedAt;

  bool get isPending => !isDone && !isDisable;
}

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

bool _parseBool(Object? value) =>
    value is bool ? value : value is int && value != 0;

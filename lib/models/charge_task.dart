import 'charge_task_status.dart';

class ChargeTask {
  const ChargeTask({
    required this.serialNumber,
    required this.deviceCode,
    required this.station,
    required this.status,
    required this.faultDescription,
    required this.faultType,
    required this.resolutionType,
    required this.isDisable,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChargeTask.fromJson(Map<String, Object?> json) {
    return ChargeTask(
      serialNumber: _asInt(json['serialNumber']),
      deviceCode: json['deviceCode'] as String? ?? '',
      station: json['station'] as String? ?? '',
      status: _parseStatus(json['status']),
      faultDescription: json['faultDescription'] as String? ?? '',
      faultType: json['faultType'] as String? ?? '',
      resolutionType: _asInt(json['resolutionType']),
      isDisable: _parseBool(json['isDisable']),
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() => {
    'serialNumber': serialNumber,
    'deviceCode': deviceCode,
    'station': station,
    'status': status.value,
    'faultDescription': faultDescription,
    'faultType': faultType,
    'resolutionType': resolutionType,
    'isDisable': isDisable,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  final int serialNumber;
  final String deviceCode;
  final String station;
  final ChargeTaskStatus status;
  final String faultDescription;
  final String faultType;
  final int resolutionType;
  final bool isDisable;
  final String createdAt;
  final String updatedAt;
}

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

bool _parseBool(Object? value) =>
    value is bool ? value : value is int && value != 0;

ChargeTaskStatus _parseStatus(Object? value) =>
    ChargeTaskStatus.fromValue(value);

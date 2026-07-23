enum ChargeTaskStatus {
  unknown('unknown'),
  pending('pending'),
  processing('processing'),
  done('done'),
  cancelled('cancelled');

  const ChargeTaskStatus(this.value);

  final String value;

  static ChargeTaskStatus fromValue(Object? value) {
    return ChargeTaskStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => ChargeTaskStatus.unknown,
    );
  }
}

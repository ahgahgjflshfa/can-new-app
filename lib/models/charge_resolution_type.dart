enum ChargeResolutionType {
  unknown(0),
  cleaned(1),
  repaired(2),
  other(3);

  const ChargeResolutionType(this.value);

  final int value;
}

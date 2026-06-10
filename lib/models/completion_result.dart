enum CompletionResult {
  normal('normal', '正常完成'),
  noPassenger('no_passenger', '現場無人 / 誤報');

  const CompletionResult(this.value, this.label);

  final String value;
  final String label;
}

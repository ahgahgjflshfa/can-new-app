enum CanResolutionType {
  pending(0, '待處理'),
  completed(1, '已完成'),
  noIssue(2, '無髒污'),
  systemClosed(3, '系統自動結案'),
  blacklistClosed(4, '黑名單自動結案');

  const CanResolutionType(this.value, this.label);

  final int value;
  final String label;

  static CanResolutionType fromValue(int value) {
    return CanResolutionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => CanResolutionType.pending,
    );
  }
}

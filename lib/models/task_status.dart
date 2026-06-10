enum TaskStatus {
  pending('pending', '待處理'),
  replied('replied', '處理中'),
  completed('completed', '已完成'),
  ignored('ignored', '已忽略');

  const TaskStatus(this.value, this.label);

  final String value;
  final String label;

  static TaskStatus fromValue(String value) {
    return TaskStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => TaskStatus.pending,
    );
  }
}

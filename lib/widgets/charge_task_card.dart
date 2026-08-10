import 'package:flutter/material.dart';

import '../models/charge_task.dart';
import '../theme/app_colors.dart';
import 'task_status_chip.dart';

class ChargeTaskCard extends StatelessWidget {
  const ChargeTaskCard({
    required this.task,
    required this.busy,
    required this.locked,
    this.onComplete,
    this.onReopen,
    super.key,
  });

  final ChargeTask task;
  final bool busy;
  final bool locked;
  final VoidCallback? onComplete;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    final status = task.isDisable
        ? 'disabled'
        : task.isDone
        ? 'done'
        : 'pending';
    final done = task.isDone && !task.isDisable;
    final surface = done
        ? AppColors.taskCompletedSurface
        : task.isDisable
        ? AppColors.taskDisabledSurface
        : AppColors.taskPendingSurface;
    final border = done
        ? AppColors.taskCompletedBorder
        : task.isDisable
        ? AppColors.taskDisabledBorder
        : AppColors.taskPendingBorder;
    final iconColor = done
        ? AppColors.taskCompleted
        : task.isDisable
        ? AppColors.taskDisabled
        : AppColors.taskPending;

    return Card(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.ev_station_outlined, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.deviceCode,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TaskStatusChip(
                label: _statusLabel(status),
                status: status,
              ),
            ),
            const SizedBox(height: 10),
            Text('站點: ${task.station}'),
            const SizedBox(height: 4),
            Text('通知次數: ${task.informTime}'),
            if (task.cleanAt != null) ...[
              const SizedBox(height: 4),
              Text('完成時間: ${task.cleanAt}'),
            ],
            if (!task.isDisable) ...[
              const SizedBox(height: 12),
              if (task.isDone)
                OutlinedButton.icon(
                  onPressed: locked ? null : onReopen,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重新開啟'),
                )
              else
                FilledButton.icon(
                  onPressed: locked ? null : onComplete,
                  icon: const Icon(Icons.check),
                  label: const Text('標記完成'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'done' => '已完成',
    'disabled' => '停用',
    _ => '待處理',
  };
}

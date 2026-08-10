import 'package:flutter/material.dart';

import '../models/assist_task.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import 'task_status_chip.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.busy,
    required this.locked,
    required this.onReply,
    required this.onCompleteNormal,
    required this.onCompleteNoPassenger,
    super.key,
  });

  final AssistTask task;
  final bool busy;
  final bool locked;
  final VoidCallback? onReply;
  final VoidCallback? onCompleteNormal;
  final VoidCallback? onCompleteNoPassenger;

  @override
  Widget build(BuildContext context) {
    final cardColor = switch (task.status) {
      TaskStatus.pending => AppColors.taskPendingSurface,
      TaskStatus.replied => AppColors.taskConfirmedSurface,
      TaskStatus.completed => AppColors.taskCompletedSurface,
      TaskStatus.ignored => AppColors.taskDisabledSurface,
    };
    final cardBorder = switch (task.status) {
      TaskStatus.pending => AppColors.taskPendingBorder,
      TaskStatus.replied => AppColors.taskConfirmedBorder,
      TaskStatus.completed => AppColors.taskCompletedBorder,
      TaskStatus.ignored => AppColors.taskDisabledBorder,
    };
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${task.stationName} ${task.locationName}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${task.stationId} · ${task.locationCode} · #${task.id}',
                      ),
                    ],
                  ),
                ),
                TaskStatusChip(
                  label: task.status.label,
                  status: task.status.value,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _TimeLabel(
                  icon: Icons.schedule,
                  label: '建立',
                  value: _formatTime(task.createdAt),
                ),
                _TimeLabel(
                  icon: Icons.directions_walk,
                  label: '協助',
                  value: _formatTime(task.repliedAt),
                ),
                _TimeLabel(
                  icon: Icons.check_circle_outline,
                  label: '完成',
                  value: _formatTime(task.doneAt),
                ),
              ],
            ),
            if (onReply != null || onCompleteNormal != null) ...[
              const SizedBox(height: 16),
              Stack(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onReply != null)
                        FilledButton.icon(
                          key: Key('reply-${task.id}'),
                          onPressed: locked ? null : onReply,
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('前往協助'),
                        ),
                      if (onCompleteNormal != null)
                        FilledButton.icon(
                          key: Key('complete-normal-${task.id}'),
                          onPressed: locked ? null : onCompleteNormal,
                          icon: const Icon(Icons.done),
                          label: const Text('協助完成'),
                        ),
                      if (onCompleteNoPassenger != null)
                        OutlinedButton.icon(
                          key: Key('complete-empty-${task.id}'),
                          onPressed: locked ? null : onCompleteNoPassenger,
                          icon: const Icon(Icons.person_off_outlined),
                          label: const Text('現場無人'),
                        ),
                    ],
                  ),
                  if (busy)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text('$label：$value'),
      ],
    );
  }
}

String _formatTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${value.year}/${twoDigits(value.month)}/${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

import 'package:flutter/material.dart';

import '../models/assist_task.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';

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
    return Card(
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
                _StatusChip(status: task.status),
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
                  label: '確認',
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
                          label: const Text('確認接案'),
                        ),
                      if (onCompleteNormal != null)
                        FilledButton.icon(
                          key: Key('complete-normal-${task.id}'),
                          onPressed: locked ? null : onCompleteNormal,
                          icon: const Icon(Icons.done),
                          label: const Text('正常完成並結案'),
                        ),
                      if (onCompleteNoPassenger != null)
                        OutlinedButton.icon(
                          key: Key('complete-empty-${task.id}'),
                          onPressed: locked ? null : onCompleteNoPassenger,
                          icon: const Icon(Icons.person_off_outlined),
                          label: const Text('現場無人（結案）'),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TaskStatus.pending => const Color(0xFFE0A458),
      TaskStatus.replied => AppColors.primary,
      TaskStatus.completed => const Color(0xFF4F772D),
      TaskStatus.ignored => const Color(0xFF767676),
    };
    return Chip(
      label: Text(status.label),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: color,
      side: BorderSide.none,
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

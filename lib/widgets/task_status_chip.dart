import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared status chip for all task systems.
class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({required this.label, required this.status, super.key});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final appearance = _appearanceFor(status.toLowerCase());
    return Chip(
      avatar: Icon(appearance.icon, size: 16, color: appearance.color),
      label: Text(label),
      labelStyle: TextStyle(
        color: appearance.color,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: appearance.color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }

  _StatusAppearance _appearanceFor(String status) {
    return switch (status) {
      'done' || 'completed' => const _StatusAppearance(
        color: AppColors.taskCompleted,
        icon: Icons.check_circle_outline,
      ),
      'confirmed' || 'replied' || 'processing' => const _StatusAppearance(
        color: AppColors.taskConfirmed,
        icon: Icons.pending_actions_outlined,
      ),
      'disabled' || 'offline' || 'ignored' => const _StatusAppearance(
        color: AppColors.taskDisabled,
        icon: Icons.warning_amber_outlined,
      ),
      _ => const _StatusAppearance(
        color: AppColors.taskPending,
        icon: Icons.priority_high_outlined,
      ),
    };
  }
}

class _StatusAppearance {
  const _StatusAppearance({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

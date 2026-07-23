import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ChargeStatusChip extends StatelessWidget {
  const ChargeStatusChip({
    required this.label,
    required this.status,
    super.key,
  });

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final done = normalized == 'done' || normalized == 'completed';
    final disabled = normalized == 'disabled' || normalized == 'offline';
    final color = done
        ? AppColors.chargeCompletedIcon
        : disabled
        ? AppColors.chargeDisabledIcon
        : AppColors.chargePrimary;
    return Chip(
      avatar: Icon(
        done
            ? Icons.check_circle_outline
            : disabled
            ? Icons.warning_amber_outlined
            : Icons.bolt,
        size: 16,
        color: color,
      ),
      label: Text(label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

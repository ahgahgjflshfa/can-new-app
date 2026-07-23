import 'package:flutter/material.dart';

import '../models/charge_task.dart';
import '../models/charge_task_status.dart';
import '../theme/app_colors.dart';
import 'charge_status_chip.dart';

class ChargeTaskCard extends StatelessWidget {
  const ChargeTaskCard({required this.task, required this.onTap, super.key});

  final ChargeTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = task.isDisable ? 'disabled' : task.status.value;
    final done = task.status == ChargeTaskStatus.done && !task.isDisable;
    return Card(
      color: done ? AppColors.chargeCompletedSurface : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: done
              ? AppColors.chargeCompletedBorder
              : AppColors.chargePrimary.withValues(alpha: 0.16),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.ev_station_outlined,
                        color: done
                            ? AppColors.chargeCompletedIcon
                            : AppColors.chargePrimary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          task.deviceCode,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ChargeStatusChip(
                      label: _statusLabel(status),
                      status: status,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('站點: ${task.station}'),
              const SizedBox(height: 4),
              Text('設備編號: ${task.deviceCode}'),
              if (task.faultDescription.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('故障: ${task.faultDescription}'),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '查看故障詳情',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.chargePrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.chargePrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status.toLowerCase()) {
    'done' || 'completed' => '已完成',
    'disabled' || 'offline' => '停用',
    'processing' => '處理中',
    'cancelled' => '已取消',
    'unknown' => '狀態不明',
    _ => '待處理',
  };
}

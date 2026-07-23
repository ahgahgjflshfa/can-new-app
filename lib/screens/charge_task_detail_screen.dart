import 'dart:io';

import 'package:flutter/material.dart';

import '../models/charge_task.dart';
import '../models/charge_task_status.dart';
import '../models/charge_resolution_type.dart';
import '../services/api_exception.dart';
import '../services/charge_api.dart';
import '../theme/app_colors.dart';
import '../widgets/charge_status_chip.dart';
import '../widgets/snack_bar_message.dart';

class ChargeTaskDetailScreen extends StatefulWidget {
  const ChargeTaskDetailScreen({
    required this.api,
    required this.task,
    this.onCompleted,
    super.key,
  });

  final ChargeApi api;
  final ChargeTask task;
  final VoidCallback? onCompleted;

  @override
  State<ChargeTaskDetailScreen> createState() => _ChargeTaskDetailScreenState();
}

class _ChargeTaskDetailScreenState extends State<ChargeTaskDetailScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final status = task.isDisable ? 'disabled' : task.status.value;
    final canComplete =
        !task.isDisable &&
        (task.status == ChargeTaskStatus.pending ||
            task.status == ChargeTaskStatus.processing);
    return Scaffold(
      appBar: AppBar(title: const Text('故障詳情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.chargeSurface,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bolt,
                        size: 36,
                        color: AppColors.chargePrimary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          task.deviceCode,
                          style: Theme.of(context).textTheme.titleLarge
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
            ),
          ),
          const SizedBox(height: 16),
          _DetailSection(
            title: '設備資訊',
            children: [
              _DetailRow('站點', task.station),
              _DetailRow('設備編號', task.deviceCode),
              _DetailRow('故障類型', task.faultType),
              _DetailRow('故障描述', task.faultDescription),
            ],
          ),
          const SizedBox(height: 16),
          _DetailSection(
            title: '任務資訊',
            children: [
              _DetailRow('狀態', _statusLabel(status)),
              _DetailRow('建立時間', task.createdAt.isEmpty ? '-' : task.createdAt),
              _DetailRow('更新時間', task.updatedAt.isEmpty ? '-' : task.updatedAt),
            ],
          ),
          if (canComplete) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _confirmComplete,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_busy ? '處理中...' : '標記完成'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.chargePrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmComplete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認標記完成？'),
        content: const Text('完成後任務將不再顯示為待處理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認完成'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _complete();
  }

  String _statusLabel(String status) => switch (status.toLowerCase()) {
    'done' || 'completed' => '已完成',
    'disabled' || 'offline' => '停用',
    'processing' => '處理中',
    'cancelled' => '已取消',
    'unknown' => '狀態不明',
    _ => '待處理',
  };

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await widget.api.updateTask(
        widget.task.serialNumber,
        status: ChargeTaskStatus.done,
        resolutionType: ChargeResolutionType.cleaned,
      );
      if (!mounted) return;
      widget.onCompleted?.call();
      showSnackBarMessage(context, '已標記完成');
      Navigator.of(context).pop();
    } on ApiException {
      showSnackBarMessage(context, '任務處理失敗，請稍後重試');
    } on SocketException {
      showSnackBarMessage(context, '網路連線中斷，請稍後重試');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.chargePrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(value),
      ],
    ),
  );
}

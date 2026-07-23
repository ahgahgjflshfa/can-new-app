import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';

class NotificationPermissionCard extends StatelessWidget {
  const NotificationPermissionCard({
    required this.state,
    required this.onOpenSettings,
    super.key,
  });

  final PushNotificationState state;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final denied = state.permissionLabel == '已拒絕';
    if (!denied) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '通知未開啟',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('未開啟通知可能錯過新的站務任務。請到系統設定允許通知。'),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => onOpenSettings(),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('開啟通知設定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

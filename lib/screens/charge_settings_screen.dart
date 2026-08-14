import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import '../models/charge_user_profile.dart';
import '../services/charge_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/snack_bar_message.dart';
import '../widgets/notification_permission_card.dart';
import '../widgets/notification_settings.dart';
import 'charge_login_screen.dart';
import 'charge_advanced_settings_screen.dart';

class ChargeSettingsScreen extends StatelessWidget {
  const ChargeSettingsScreen({
    required this.api,
    required this.user,
    required this.deviceId,
    required this.pushService,
    required this.sessionStore,
    super.key,
  });

  final ChargeApi api;
  final ChargeUserProfile user;
  final String deviceId;
  final PushNotificationService pushService;
  final SessionStore sessionStore;

  @override
  Widget build(BuildContext context) {
    final topic = user.chargeTopic;
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          if (kDebugMode)
            IconButton(
              key: const Key('chargeAdvancedSettingsButton'),
              tooltip: '進階設定',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChargeAdvancedSettingsScreen(
                    api: api,
                    user: user,
                    deviceId: deviceId,
                    pushService: pushService,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.chargePrimary,
                    child: Icon(Icons.bolt, color: Colors.white),
                  ),
                  title: Text(
                    user.account,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('站點: ${user.station ?? '未設定站點'}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Charge 推播 topic'),
                  subtitle: Text(topic.isEmpty ? '未設定' : topic),
                ),
                ValueListenableBuilder<PushNotificationState>(
                  valueListenable: pushService.state,
                  builder: (_, state, _) => Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.circle,
                          size: 14,
                          color: AppColors.chargePrimary,
                        ),
                        title: const Text('推播狀態'),
                        subtitle: Text(state.statusMessage),
                      ),
                      NotificationPermissionCard(
                        state: state,
                        onOpenSettings: () =>
                            _openNotificationSettings(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('chargeSettingsLogoutButton'),
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '登出',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () => _logout(context, topic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, String topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認登出？'),
        content: const Text('登出後需要重新輸入帳號密碼才能處理任務。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認登出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final capturedToken = api.token;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('登出中...'),
          ],
        ),
      ),
    );
    try {
      await sessionStore.clearChargeSession();
    } catch (_) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        showSnackBarMessage(context, '登出失敗，工作階段仍保留；請確認儲存空間後重試');
      }
      return;
    }
    if (!context.mounted) return;
    api.invalidateToken(token: capturedToken);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChargeLoginScreen(
          api: api,
          pushService: pushService,
          sessionStore: sessionStore,
          deviceId: deviceId,
        ),
      ),
    );
    messenger.showSnackBar(const SnackBar(content: Text('已登出')));
    unawaited(() async {
      var remoteCleanupFailed = false;
      if (topic.isNotEmpty) {
        try {
          await pushService.unsubscribeFromTopic(topic);
        } catch (_) {
          remoteCleanupFailed = true;
        }
      }
      try {
        await api.logout(token: capturedToken);
      } catch (_) {
        remoteCleanupFailed = true;
      }
      if (remoteCleanupFailed) {
        messenger.showSnackBar(
          const SnackBar(content: Text('伺服器清理失敗，已安全返回登入頁')),
        );
      }
    }());
  }

  Future<void> _openNotificationSettings(BuildContext context) async {
    final result = await openNotificationSettings();
    if (!context.mounted) return;
    showSnackBarMessage(context, switch (result) {
      NotificationSettingsResult.requested => '已開啟通知設定，請確認允許通知',
      NotificationSettingsResult.unsupported => '請到系統設定 > 通知 > 本 App，允許通知',
      NotificationSettingsResult.failed => '無法自動開啟通知設定，請到系統設定 > 通知允許通知',
    });
  }
}

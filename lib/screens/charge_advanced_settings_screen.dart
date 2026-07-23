import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/charge_user_profile.dart';
import '../services/api_log_store.dart';
import '../services/app_logger.dart';
import '../services/charge_api.dart';
import '../services/charge_api_client.dart';
import '../services/push_notification_service.dart';
import '../widgets/snack_bar_message.dart';

/// Charge's diagnostics stay separate from the main settings flow and are
/// reachable only from debug builds. The stores are shared, so this screen
/// shows the same diagnostic history as the rest of the app.
class ChargeAdvancedSettingsScreen extends StatelessWidget {
  const ChargeAdvancedSettingsScreen({
    required this.api,
    required this.user,
    required this.deviceId,
    required this.pushService,
    super.key,
  });

  final ChargeApi api;
  final ChargeUserProfile user;
  final String deviceId;
  final PushNotificationService pushService;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('進階設定')),
      body: ValueListenableBuilder<PushNotificationState>(
        valueListenable: pushService.state,
        builder: (context, pushState, _) =>
            ValueListenableBuilder<List<String>>(
              valueListenable: AppLogger.entries,
              builder: (context, logs, _) =>
                  ValueListenableBuilder<List<ApiLogEntry>>(
                    valueListenable: ApiLogStore.entries,
                    builder: (context, apiLogs, _) =>
                        ValueListenableBuilder<
                          List<PushNotificationHistoryEntry>
                        >(
                          valueListenable: PushNotificationHistory.entries,
                          builder: (context, pushLogs, _) => ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _Section(
                                title: '應用程式資訊',
                                children: [
                                  _Info('版本', '1.0.1'),
                                  _Info('站點', user.station),
                                  _Info('系統', 'Charge'),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _Section(
                                title: '推播狀態',
                                children: [
                                  _Info('Firebase 推播', pushState.statusMessage),
                                  _Info('通知權限', pushState.permissionLabel),
                                  _Info(
                                    'FCM Token',
                                    _tokenPreview(pushState.fcmToken),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _Section(
                                title: '開發工具',
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      16,
                                    ),
                                    child: ElevatedButton.icon(
                                      key: const Key('chargeShareDebugButton'),
                                      onPressed: () =>
                                          _shareDebug(context, pushState),
                                      icon: const Icon(
                                        Icons.bug_report_outlined,
                                      ),
                                      label: const Text('複製診斷資訊（含裝置識別）'),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  _Action(
                                    'API 紀錄',
                                    Icons.api_outlined,
                                    '${apiLogs.length} 筆',
                                    () => _showApiLogs(context, apiLogs),
                                  ),
                                  const Divider(height: 1),
                                  _Action(
                                    '推播紀錄',
                                    Icons.notifications_outlined,
                                    '${pushLogs.length} 筆',
                                    () => _showPushLogs(context, pushLogs),
                                  ),
                                  const Divider(height: 1),
                                  _Action(
                                    'App Logs',
                                    Icons.terminal_outlined,
                                    '${logs.length} 筆',
                                    () => _showLogs(context, logs),
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    title: Text(
                                      '清除所有紀錄',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                    onTap: () => _confirmClearAll(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                  ),
            ),
      ),
    );
  }

  Future<void> _shareDebug(
    BuildContext context,
    PushNotificationState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('複製診斷資訊？'),
        content: const Text('內容含裝置識別資訊。複製後請只提供給授權的支援人員。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('複製'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final text = StringBuffer()
      ..writeln('=== Charge Debug Report ===')
      ..writeln('Timestamp: ${DateTime.now()}')
      ..writeln('\n--- App ---\nVersion: 1.0.1\nBuild: 2')
      ..writeln(
        '\n--- Device ---\nOS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\nDevice ID: 已隱藏',
      )
      ..writeln(
        '\n--- Session ---\nToken: ${api.token == null ? '未登入' : '已取得'}',
      )
      ..writeln(
        '\n--- Push Notification ---\nStatus: ${state.statusMessage}\nPermission: ${state.permissionLabel}\nFCM Token: ${state.fcmToken == null ? '無' : '已隱藏'}',
      )
      ..writeln(
        '\n--- API Base ---\nURL: $chargeBaseUrl\nTimeout: ${chargeApiTimeout.inSeconds}s',
      )
      ..writeln(
        '\n--- API Logs ---\n${_formatApiLogs(ApiLogStore.entries.value)}',
      )
      ..writeln('\n--- App Logs ---\n${AppLogger.exportText()}');
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (context.mounted) showSnackBarMessage(context, 'Debug 資訊已複製到剪貼簿');
  }

  Future<void> _confirmClear(
    BuildContext context,
    String label,
    VoidCallback clear,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除$label？'),
        content: Text('$label 將永久清除，且無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    clear();
    showSnackBarMessage(context, '$label已清除');
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有紀錄？'),
        content: const Text('API、推播與 App 紀錄都會永久清除，且無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    ApiLogStore.clear();
    PushNotificationHistory.clear();
    AppLogger.clear();
    showSnackBarMessage(context, '所有診斷紀錄已清除');
  }

  void _showApiLogs(BuildContext context, List<ApiLogEntry> logs) => _showSheet(
    context,
    'API 紀錄',
    logs.isEmpty
        ? '目前沒有 API 紀錄。'
        : logs.reversed
              .map(
                (e) =>
                    '${e.method} ${e.path}  ${e.statusCode ?? '---'}  ${e.durationMs ?? '-'}ms',
              )
              .join('\n'),
    () => _confirmClear(context, 'API 紀錄', ApiLogStore.clear),
  );

  void _showPushLogs(
    BuildContext context,
    List<PushNotificationHistoryEntry> logs,
  ) => _showSheet(
    context,
    '推播紀錄',
    logs.isEmpty
        ? '目前沒有推播紀錄。'
        : logs.reversed
              .map((e) => '[${e.timestamp}] ${e.source}  ${e.title ?? '(無標題)'}')
              .join('\n'),
    () => _confirmClear(context, '推播紀錄', PushNotificationHistory.clear),
  );

  void _showLogs(BuildContext context, List<String> logs) => _showSheet(
    context,
    'App Logs',
    logs.isEmpty ? '目前沒有 log。' : logs.reversed.join('\n'),
    () => _confirmClear(context, 'App Logs', AppLogger.clear),
  );

  void _showSheet(
    BuildContext context,
    String title,
    String content,
    VoidCallback clear,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .75,
        minChildSize: .35,
        maxChildSize: .95,
        expand: false,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: controller,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', height: 1.35),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _confirmClear(context, title, clear),
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tokenPreview(String? token) => token == null
    ? '尚未取得'
    : '${token.substring(0, token.length > 20 ? 20 : token.length)}...';

String _formatApiLogs(List<ApiLogEntry> logs) => logs.isEmpty
    ? 'No API logs.'
    : logs
          .map(
            (e) =>
                '${e.timestamp} ${e.method} ${e.path} → ${e.statusCode ?? '---'} (${e.durationMs ?? '-'}ms)',
          )
          .join('\n');

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label),
    subtitle: SelectableText(value),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.title, this.icon, this.trailing, this.onTap);
  final String title;
  final IconData icon;
  final String trailing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: Text(trailing),
    onTap: onTap,
  );
}

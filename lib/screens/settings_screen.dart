import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_profile.dart';
import '../services/api_log_store.dart';
import '../services/app_logger.dart';
import '../services/limabang_api.dart';
import '../services/limabang_api_client.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/snack_bar_message.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.api,
    required this.user,
    required this.deviceId,
    required this.pushService,
    required this.sessionStore,
    super.key,
  });

  final LimabangApi api;
  final UserProfile user;
  final String deviceId;
  final PushNotificationService pushService;
  final SessionStore sessionStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          IconButton(
            tooltip: '進階設定',
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdvancedSettingsScreen(
                    api: api,
                    user: user,
                    deviceId: deviceId,
                    pushService: pushService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AccountSection(
            api: api,
            user: user,
            pushService: pushService,
            sessionStore: sessionStore,
            deviceId: deviceId,
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.api,
    required this.user,
    required this.pushService,
    required this.sessionStore,
    required this.deviceId,
  });

  final LimabangApi api;
  final UserProfile user;
  final PushNotificationService pushService;
  final SessionStore sessionStore;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final scope = user.stationId ?? user.sectionId ?? '未設定站別';
    return _SettingsSection(
      title: '帳號',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('$scope · ${user.role}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          key: const Key('settingsLogoutButton'),
          leading: const Icon(Icons.logout),
          title: const Text('登出'),
          textColor: Theme.of(context).colorScheme.error,
          iconColor: Theme.of(context).colorScheme.error,
          onTap: () async {
            if (user.stationId != null) {
              try {
                await pushService.unsubscribeFromTopic(user.stationId!);
              } catch (_) {
                // Topic cleanup is best effort; API logout must continue.
              }
            }
            try {
              await api.logout();
            } catch (_) {
              // Remote cleanup is best effort; local logout must continue.
            }
            try {
              await sessionStore.clearSession();
            } catch (_) {
              if (context.mounted) {
                showSnackBarMessage(context, '登出失敗，請稍後再試');
              }
              return;
            }
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).popUntil((route) => route.isFirst);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoginScreen(
                  api: api,
                  pushService: pushService,
                  sessionStore: sessionStore,
                  deviceId: deviceId,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({
    required this.api,
    required this.user,
    required this.deviceId,
    required this.pushService,
    super.key,
  });

  final LimabangApi api;
  final UserProfile user;
  final String deviceId;
  final PushNotificationService pushService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('進階設定')),
      body: ValueListenableBuilder<PushNotificationState>(
        valueListenable: pushService.state,
        builder: (context, pushState, _) {
          return ValueListenableBuilder<List<String>>(
            valueListenable: AppLogger.entries,
            builder: (context, logs, _) {
              return ValueListenableBuilder<List<ApiLogEntry>>(
                valueListenable: ApiLogStore.entries,
                builder: (context, apiLogs, _) {
                  return ValueListenableBuilder<
                    List<PushNotificationHistoryEntry>
                  >(
                    valueListenable: PushNotificationHistory.entries,
                    builder: (context, pushLogs, _) {
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildAppInfoSection(),
                          const SizedBox(height: 16),
                          _buildPushStateSection(pushState),
                          const SizedBox(height: 16),
                          _buildDevToolsSection(
                            context,
                            pushState,
                            apiLogs,
                            pushLogs,
                            logs,
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAppInfoSection() {
    return _SettingsSection(
      title: '應用程式資訊',
      children: [
        _InfoTile(label: '版本', value: '1.0.0'),
        _InfoTile(label: '站點', value: user.stationId ?? '未設定站別'),
      ],
    );
  }

  Widget _buildPushStateSection(PushNotificationState pushState) {
    final fcmPreview = pushState.fcmToken == null
        ? '尚未取得'
        : '${pushState.fcmToken!.substring(0, pushState.fcmToken!.length > 20 ? 20 : pushState.fcmToken!.length)}...';
    return _SettingsSection(
      title: '推播狀態',
      children: [
        _InfoTile(label: 'Firebase 推播', value: pushState.statusMessage),
        _InfoTile(label: '通知權限', value: pushState.permissionLabel),
        _InfoTile(label: 'FCM Token', value: fcmPreview),
      ],
    );
  }

  Widget _buildDevToolsSection(
    BuildContext context,
    PushNotificationState pushState,
    List<ApiLogEntry> apiLogs,
    List<PushNotificationHistoryEntry> pushLogs,
    List<String> logs,
  ) {
    return _SettingsSection(
      title: '開發工具',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ElevatedButton.icon(
            key: const Key('shareDebugButton'),
            onPressed: () => _onShareDebug(context, pushState),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('一鍵分享 Debug 資訊'),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.api_outlined),
          title: const Text('API 紀錄'),
          trailing: Text('${apiLogs.length} 筆'),
          onTap: () => _showApiInspector(context, apiLogs),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('推播紀錄'),
          trailing: Text('${pushLogs.length} 筆'),
          onTap: () => _showPushHistory(context, pushLogs),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.terminal_outlined),
          title: const Text('App Logs'),
          trailing: Text('${logs.length} 筆'),
          onTap: () => _showAppLogs(context, logs),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '清除所有紀錄',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () {
            ApiLogStore.clear();
            PushNotificationHistory.clear();
            AppLogger.clear();
          },
        ),
      ],
    );
  }

  Future<void> _onShareDebug(
    BuildContext context,
    PushNotificationState pushState,
  ) async {
    final packageInfo = await _getPackageInfo();
    final buffer = StringBuffer();
    buffer.writeln('=== 立碼幫幫忙 Debug Report ===');
    buffer.writeln('Timestamp: ${DateTime.now()}');
    buffer.writeln('');
    buffer.writeln('--- App ---');
    buffer.writeln('Version: ${packageInfo['version'] ?? 'unknown'}');
    buffer.writeln('Build: ${packageInfo['buildNumber'] ?? 'unknown'}');
    buffer.writeln('');
    buffer.writeln('--- Device ---');
    buffer.writeln(
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    buffer.writeln('Device ID: $deviceId');
    buffer.writeln('');
    buffer.writeln('--- Session ---');
    buffer.writeln('Token: ${api.token == null ? '未登入' : '已取得'}');
    buffer.writeln('');
    buffer.writeln('--- Push Notification ---');
    buffer.writeln('Status: ${pushState.statusMessage}');
    buffer.writeln('Permission: ${pushState.permissionLabel}');
    buffer.writeln('FCM Token: ${pushState.fcmToken ?? '無'}');
    buffer.writeln('');
    buffer.writeln('--- API Base ---');
    buffer.writeln('URL: $limabangBaseUrl');
    buffer.writeln('Timeout: ${limabangApiTimeout.inSeconds}s');
    buffer.writeln('');
    buffer.writeln('--- API Logs ---');
    buffer.writeln(
      ApiLogStore.entries.value.isEmpty
          ? 'No API logs.'
          : _formatApiLogsForExport(ApiLogStore.entries.value),
    );
    buffer.writeln('');
    buffer.writeln('--- App Logs ---');
    buffer.writeln(AppLogger.exportText());

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      showSnackBarMessage(context, 'Debug 資訊已複製到剪貼簿');
    }
  }

  void _showApiLogDetail(BuildContext context, ApiLogEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MethodChip(method: entry.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.path,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (entry.statusCode != null)
                    _StatusChip(statusCode: entry.statusCode!),
                  if (entry.durationMs != null)
                    Text(
                      '${entry.durationMs} ms',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (entry.error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Error: ${entry.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                  Text(
                    'URL',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SelectableText(entry.fullUrl),
                  const SizedBox(height: 12),
                  if (entry.requestBody != null) ...[
                    Text(
                      'Request Body',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _CodeBlock(text: entry.requestBody!),
                    const SizedBox(height: 12),
                  ],
                  if (entry.responseBody != null) ...[
                    Text(
                      'Response Body',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _CodeBlock(text: entry.responseBody!),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPushLogDetail(
    BuildContext context,
    PushNotificationHistoryEntry entry,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('推播詳情'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: '來源', value: entry.source),
                _DetailRow(label: '時間', value: entry.timestamp.toString()),
                _DetailRow(label: 'Message ID', value: entry.messageId ?? '-'),
                _DetailRow(label: '標題', value: entry.title ?? '-'),
                _DetailRow(label: '內文', value: entry.body ?? '-'),
                if (entry.data != null && entry.data!.isNotEmpty)
                  _DetailRow(
                    label: 'Data',
                    value: const JsonEncoder.withIndent(
                      '  ',
                    ).convert(entry.data),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  void _showApiInspector(BuildContext context, List<ApiLogEntry> apiLogs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'API 紀錄',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('clearApiLogsButton'),
                        onPressed: ApiLogStore.clear,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (apiLogs.isEmpty)
                    const Text('目前沒有 API 紀錄。')
                  else
                    Column(
                      children: apiLogs.reversed
                          .map((entry) {
                            return _ApiLogTile(
                              entry: entry,
                              onTap: () => _showApiLogDetail(context, entry),
                            );
                          })
                          .toList(growable: false),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPushHistory(
    BuildContext context,
    List<PushNotificationHistoryEntry> pushLogs,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '推播紀錄',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('clearPushLogsButton'),
                        onPressed: PushNotificationHistory.clear,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (pushLogs.isEmpty)
                    const Text('目前沒有推播紀錄。')
                  else
                    Column(
                      children: pushLogs.reversed
                          .map((entry) {
                            return _PushLogTile(
                              entry: entry,
                              onTap: () => _showPushLogDetail(context, entry),
                            );
                          })
                          .toList(growable: false),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAppLogs(BuildContext context, List<String> logs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'App Logs',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('clearLogsButton'),
                        onPressed: AppLogger.clear,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F1E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2D8C8)),
                    ),
                    child: SelectableText(
                      logs.isEmpty ? '目前沒有 log。' : logs.reversed.join('\n'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('exportLogsButton'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: AppLogger.exportText()),
                        );
                        if (context.mounted) {
                          showSnackBarMessage(context, 'Log 已複製到剪貼簿');
                        }
                      },
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Export Log'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>> _getPackageInfo() async {
    // Flutter does not expose package info without package_info_plus.
    // Return a minimal map for now; if the user adds package_info_plus later,
    // this can be wired up.
    return <String, String>{'version': '1.0.0', 'buildNumber': '1'};
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: SelectableText(value),
      dense: true,
      titleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ApiLogTile extends StatelessWidget {
  const _ApiLogTile({required this.entry, this.onTap});

  final ApiLogEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final success = entry.isSuccess;
    final statusText = entry.statusCode != null ? '${entry.statusCode}' : '---';
    final durationText = entry.durationMs != null
        ? '${entry.durationMs}ms'
        : '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _MethodChip(method: entry.method),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.path,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (durationText.isNotEmpty)
                    Text(
                      durationText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: success
                    ? Colors.green.shade50
                    : Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: success
                      ? Colors.green.shade800
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PushLogTile extends StatelessWidget {
  const _PushLogTile({required this.entry, this.onTap});

  final PushNotificationHistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.source,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title ?? '(無標題)',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatShortTime(entry.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      'GET' => Colors.blue,
      'POST' => Colors.orange,
      'PUT' => Colors.purple,
      'DELETE' => Colors.red,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.statusCode});

  final int statusCode;

  @override
  Widget build(BuildContext context) {
    final success = statusCode >= 200 && statusCode < 300;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: success
            ? Colors.green.shade50
            : Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$statusCode',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: success
              ? Colors.green.shade800
              : Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2D8C8)),
      ),
      child: SelectableText(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SelectableText(value),
        ],
      ),
    );
  }
}

String _formatShortTime(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${twoDigits(value.month)}/${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}

String _formatApiLogsForExport(List<ApiLogEntry> logs) {
  final buffer = StringBuffer();
  for (final log in logs) {
    final status = log.statusCode != null ? '${log.statusCode}' : '---';
    final dur = log.durationMs != null ? '${log.durationMs}ms' : '---';
    buffer.writeln(
      '[${_formatShortTime(log.timestamp)}] '
      '${log.method} ${log.path} → $status ($dur)',
    );
    if (log.error != null) {
      buffer.writeln('  ERROR: ${log.error}');
    }
  }
  return buffer.toString();
}

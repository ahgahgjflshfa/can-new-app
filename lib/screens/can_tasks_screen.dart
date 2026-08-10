import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/can_resolution_type.dart';
import '../models/can_task.dart';
import '../models/can_user_profile.dart';
import '../services/api_exception.dart';
import '../services/can_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/error_state.dart';
import '../widgets/snack_bar_message.dart';
import '../widgets/stale_task_banner.dart';
import '../widgets/task_status_chip.dart';
import 'can_settings_screen.dart';
import 'can_login_screen.dart';

class CanTasksScreen extends StatefulWidget {
  const CanTasksScreen({
    required this.api,
    required this.user,
    required this.deviceId,
    required this.pushService,
    required this.sessionStore,
    super.key,
  });

  final CanApi api;
  final CanUserProfile user;
  final String deviceId;
  final PushNotificationService pushService;
  final SessionStore sessionStore;

  @override
  State<CanTasksScreen> createState() => _CanTasksScreenState();
}

class _CanTasksScreenState extends State<CanTasksScreen>
    with WidgetsBindingObserver {
  late Future<List<CanTask>> _tasksFuture;
  String? _loadError;
  List<CanTask>? _lastTasks;
  var _busySerialNumber = 0;
  DateTime? _lastResumeRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tasksFuture = _loadTasks();
    widget.pushService.refreshSignal.addListener(_refreshFromPush);
    final station = widget.user.station?.trim();
    final topic = widget.user.topic?.trim();
    if (topic != null && topic.isNotEmpty) {
      widget.pushService.subscribeToTopic(topic);
    } else if (station != null && station.isNotEmpty) {
      widget.pushService.subscribeToTopic(
        widget.pushService.topicFor(PushSystem.can, station),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pushService.refreshSignal.removeListener(_refreshFromPush);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _returnToSystemSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('任務列表'),
          leading: IconButton(
            tooltip: '返回系統選擇',
            onPressed: _returnToSystemSelection,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: '重新整理',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              key: const Key('canSettingsButton'),
              tooltip: '設定',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<CanTask>>(
            future: _tasksFuture,
            builder: (context, snapshot) {
              if (_loadError != null) {
                return ErrorState(message: _loadError!, onRetry: _refresh);
              }
              final refreshing =
                  snapshot.connectionState == ConnectionState.waiting &&
                  _lastTasks != null;
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _lastTasks == null) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在讀取任務，請稍候...'),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                if (error is SessionExpiredException) {
                  _recoverFromExpiredSession();
                  return ErrorState(
                    message: '登入狀態已失效，正在返回 CAN 登入畫面…',
                    onRetry: _recoverFromExpiredSession,
                  );
                }
                if (_lastTasks == null) {
                  return ErrorState(
                    message: '目前無法取得任務，請稍後重試。',
                    onRetry: _refresh,
                  );
                }
              }
              final tasks = snapshot.data ?? _lastTasks ?? const <CanTask>[];
              if (tasks.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (refreshing || snapshot.hasError)
                      StaleTaskBanner(
                        message: refreshing
                            ? '正在更新，暫時沒有已載入的任務'
                            : '目前無法更新，請重試確認最新任務',
                        onRetry: _refresh,
                      ),
                    SizedBox(height: 120),
                    const Icon(
                      Icons.task_alt,
                      size: 72,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 16),
                    const Center(child: Text('目前沒有待處理任務\n可下拉或按重新整理檢查最新任務')),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount:
                    tasks.length + ((refreshing || snapshot.hasError) ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0 && (refreshing || snapshot.hasError)) {
                    return StaleTaskBanner(
                      message: refreshing
                          ? '正在更新，以下是上次載入的任務'
                          : '目前無法更新，以下是上次載入的任務',
                      onRetry: _refresh,
                    );
                  }
                  final taskIndex =
                      index - ((refreshing || snapshot.hasError) ? 1 : 0);
                  final task = tasks[taskIndex];
                  return _CanTaskCard(
                    task: task,
                    busy: _busySerialNumber == task.serialNumber,
                    locked: _busySerialNumber != 0,
                    onComplete: task.isPending
                        ? () => _confirmTask(task, true)
                        : null,
                    onNoIssue: task.isPending
                        ? () => _confirmTask(task, false)
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _returnToSystemSelection() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _refresh() {
    setState(() {
      _tasksFuture = _loadTasks();
    });
  }

  Future<List<CanTask>> _loadTasks() async {
    _loadError = null;
    final tasks = await widget.api.fetchTasks();
    _lastTasks = tasks;
    return tasks;
  }

  Future<void> _confirmTask(CanTask task, bool completed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確定已完成'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runTaskAction(
      task.serialNumber,
      () => widget.api.updateTask(
        task.serialNumber,
        isDone: true,
        resolutionType: completed
            ? CanResolutionType.completed.value
            : CanResolutionType.noIssue.value,
      ),
      completed ? '已完成清潔' : '已以無髒污結案',
    );
  }

  Future<void> _runTaskAction(
    int serialNumber,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busySerialNumber = serialNumber);
    try {
      await action();
      if (!mounted) {
        return;
      }
      showSnackBarMessage(context, successMessage);
      _refresh();
    } on SessionExpiredException {
      await _recoverFromExpiredSession();
    } on ApiException {
      if (!mounted) {
        return;
      }
      showSnackBarMessage(context, '任務處理失敗，請稍後重試');
    } on SocketException {
      if (!mounted) {
        return;
      }
      showSnackBarMessage(context, '網路連線中斷，請稍後重試');
    } finally {
      if (mounted) {
        setState(() => _busySerialNumber = 0);
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanSettingsScreen(
          api: widget.api,
          user: widget.user,
          deviceId: widget.deviceId,
          pushService: widget.pushService,
          sessionStore: widget.sessionStore,
        ),
      ),
    );
  }

  void _refreshFromPush() {
    if (mounted && widget.pushService.shouldRefreshFor(PushSystem.can)) {
      _refresh();
    }
  }

  void _refreshFromResume() {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastResumeRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastResumeRefreshAt = now;
    _refresh();
  }

  var _sessionRecoveryStarted = false;

  Future<void> _recoverFromExpiredSession() async {
    if (_sessionRecoveryStarted || !mounted) return;
    _sessionRecoveryStarted = true;
    final rejectedToken = widget.api.token;
    try {
      await widget.sessionStore.clearCanSession();
    } catch (_) {
      _sessionRecoveryStarted = false;
      if (mounted) showSnackBarMessage(context, '登入狀態清除失敗，請確認儲存空間後重試');
      return;
    }
    widget.api.invalidateToken(token: rejectedToken);
    final canTopic = widget.user.topic?.trim();
    final canStation = widget.user.station?.trim();
    final topicToDrop = (canTopic != null && canTopic.isNotEmpty)
        ? canTopic
        : (canStation != null && canStation.isNotEmpty)
        ? widget.pushService.topicFor(PushSystem.can, canStation)
        : null;
    if (topicToDrop != null) {
      unawaited(_cleanupCanTopic(topicToDrop));
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanLoginScreen(
          api: widget.api,
          pushService: widget.pushService,
          sessionStore: widget.sessionStore,
          deviceId: widget.deviceId,
        ),
      ),
    );
    showSnackBarMessage(context, 'CAN 登入狀態已失效，請重新登入');
  }

  Future<void> _cleanupCanTopic(String topic) async {
    try {
      await widget.pushService.unsubscribeFromTopic(topic);
    } catch (_) {
      // Topic cleanup is best effort after the local logout commit.
    }
  }
}

class _CanTaskCard extends StatelessWidget {
  const _CanTaskCard({
    required this.task,
    required this.busy,
    required this.locked,
    this.onComplete,
    this.onNoIssue,
  });

  final CanTask task;
  final bool busy;
  final bool locked;
  final VoidCallback? onComplete;
  final VoidCallback? onNoIssue;

  @override
  Widget build(BuildContext context) {
    final statusLabel = CanResolutionType.fromValue(task.resolutionType).label;
    final isPending = task.isPending;
    final status = task.isDone
        ? 'completed'
        : task.isDisable
        ? 'disabled'
        : 'pending';
    final statusSurface = task.isDone
        ? AppColors.taskCompletedSurface
        : task.isDisable
        ? AppColors.taskDisabledSurface
        : AppColors.taskPendingSurface;
    final statusBorder = task.isDone
        ? AppColors.taskCompletedBorder
        : task.isDisable
        ? AppColors.taskDisabledBorder
        : AppColors.taskPendingBorder;
    final statusIconColor = task.isDone
        ? AppColors.taskCompleted
        : task.isDisable
        ? AppColors.taskDisabled
        : AppColors.taskPending;

    return Card(
      color: statusSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusBorder ?? Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.delete_outline, color: statusIconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '垃圾桶: ${task.trashBin}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TaskStatusChip(label: statusLabel, status: status),
            ),
            const SizedBox(height: 10),
            Text('站點: ${task.station}'),
            const SizedBox(height: 4),
            Text('通知次數: ${task.informTime}'),
            const SizedBox(height: 12),
            if (isPending) ...[
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final vertical =
                      constraints.maxWidth < 420 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.15;
                  final complete = FilledButton.icon(
                    onPressed: locked ? null : onComplete,
                    icon: const Icon(Icons.check),
                    label: const Text('完成清潔'),
                  );
                  final noIssue = OutlinedButton.icon(
                    onPressed: locked ? null : onNoIssue,
                    icon: const Icon(Icons.clear),
                    label: const Text('無髒污（結案）'),
                  );
                  if (vertical) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [complete, const SizedBox(height: 8), noIssue],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: complete),
                      const SizedBox(width: 8),
                      Expanded(child: noIssue),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

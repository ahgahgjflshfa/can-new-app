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
import 'can_settings_screen.dart';

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

class _CanTasksScreenState extends State<CanTasksScreen> {
  late Future<List<CanTask>> _tasksFuture;
  String? _loadError;
  var _busySerialNumber = 0;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _loadTasks();
    widget.pushService.refreshSignal.addListener(_refreshFromPush);
    final station = widget.user.station?.trim();
    if (station != null && station.isNotEmpty && widget.user.topic != null) {
      widget.pushService.subscribeToTopic(widget.user.topic!);
    }
  }

  @override
  void dispose() {
    widget.pushService.refreshSignal.removeListener(_refreshFromPush);
    super.dispose();
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
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在讀取任務...'),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                final errorText = error is ApiException
                    ? error.message
                    : error.toString();
                return ErrorState(message: errorText, onRetry: _refresh);
              }
              final tasks = snapshot.data ?? const <CanTask>[];
              if (tasks.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    SizedBox(height: 120),
                    Icon(Icons.task_alt, size: 72, color: AppColors.primary),
                    SizedBox(height: 16),
                    Center(child: Text('目前沒有待處理任務')),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _CanTaskCard(
                    task: task,
                    busy: _busySerialNumber == task.serialNumber,
                    onComplete: task.isPending
                        ? () => _completeTask(task)
                        : null,
                    onNoIssue: task.isPending ? () => _noIssueTask(task) : null,
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
    final station = widget.user.station?.trim();
    if (station == null || station.isEmpty) {
      _loadError = '帳號未設定站點，請至設定登出後重新登入';
      return const <CanTask>[];
    }
    _loadError = null;
    return widget.api.fetchTasksByStation(station);
  }

  Future<void> _completeTask(CanTask task) async {
    await _runTaskAction(
      task.serialNumber,
      () => widget.api.updateTask(
        task.serialNumber,
        isDone: true,
        resolutionType: CanResolutionType.completed.value,
      ),
      '已標記完成',
    );
  }

  Future<void> _noIssueTask(CanTask task) async {
    await _runTaskAction(
      task.serialNumber,
      () => widget.api.updateTask(
        task.serialNumber,
        isDone: true,
        resolutionType: CanResolutionType.noIssue.value,
      ),
      '已標記無髒污',
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
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      showSnackBarMessage(context, error.message);
    } on SocketException {
      if (!mounted) {
        return;
      }
      showSnackBarMessage(context, '無法連線到伺服器，請稍後再試');
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
    if (mounted) {
      _refresh();
    }
  }
}

class _CanTaskCard extends StatelessWidget {
  const _CanTaskCard({
    required this.task,
    required this.busy,
    this.onComplete,
    this.onNoIssue,
  });

  final CanTask task;
  final bool busy;
  final VoidCallback? onComplete;
  final VoidCallback? onNoIssue;

  @override
  Widget build(BuildContext context) {
    final statusLabel = CanResolutionType.fromValue(task.resolutionType).label;
    final isPending = task.isPending;
    final statusSurface = task.isDone
        ? AppColors.canTaskCompletedSurface
        : task.isDisable
        ? AppColors.canTaskDisabledSurface
        : null;
    final statusBorder = task.isDone
        ? AppColors.canTaskCompletedBorder
        : task.isDisable
        ? AppColors.canTaskDisabledBorder
        : null;
    final statusIconColor = task.isDone
        ? AppColors.canTaskCompletedIcon
        : task.isDisable
        ? AppColors.canTaskDisabledIcon
        : Colors.orange;

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
            Text('站點: ${task.station}'),
            const SizedBox(height: 4),
            Text('通知次數: ${task.informTime}'),
            const SizedBox(height: 4),
            Text('狀態: $statusLabel'),
            const SizedBox(height: 12),
            if (isPending && !busy)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onComplete,
                      icon: const Icon(Icons.check),
                      label: const Text('標記完成'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onNoIssue,
                      icon: const Icon(Icons.clear),
                      label: const Text('無髒污'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

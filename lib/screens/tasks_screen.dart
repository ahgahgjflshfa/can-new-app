import 'dart:io';

import 'package:flutter/material.dart';

import '../models/assist_task.dart';
import '../models/completion_result.dart';
import '../models/task_status.dart';
import '../models/user_profile.dart';
import '../services/api_exception.dart';
import '../services/limabang_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/error_state.dart';
import '../widgets/snack_bar_message.dart';
import '../widgets/task_card.dart';
import '../widgets/stale_task_banner.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({
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
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late Future<List<AssistTask>> _tasksFuture;
  List<AssistTask>? _lastTasks;
  var _busyTaskId = 0;
  var _sessionRecoveryStarted = false;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _loadTasks();
    widget.pushService.refreshSignal.addListener(_refreshFromPush);
    if (widget.user.stationId != null) {
      widget.pushService.subscribeToTopic(widget.user.stationId!);
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
              key: const Key('settingsButton'),
              tooltip: '設定',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<AssistTask>>(
            future: _tasksFuture,
            builder: (context, snapshot) {
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
                if (snapshot.error is SessionExpiredException) {
                  _startSessionRecovery();
                  return ErrorState(
                    message: '登入狀態已失效，正在返回登入畫面…',
                    onRetry: _recoverFromExpiredSession,
                  );
                }
                if (_lastTasks == null) {
                  return ErrorState(
                    message: _errorMessage(snapshot.error),
                    onRetry: _refresh,
                  );
                }
              }
              final tasks = snapshot.data ?? _lastTasks ?? const <AssistTask>[];
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
                  return TaskCard(
                    task: task,
                    busy: _busyTaskId == task.id,
                    locked: _busyTaskId != 0,
                    onReply: task.status == TaskStatus.pending
                        ? () => _confirmReply(task)
                        : null,
                    onCompleteNormal: task.status == TaskStatus.replied
                        ? () => _confirmComplete(task, CompletionResult.normal)
                        : null,
                    onCompleteNoPassenger: task.status == TaskStatus.replied
                        ? () => _confirmComplete(
                            task,
                            CompletionResult.noPassenger,
                          )
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

  Future<List<AssistTask>> _loadTasks() async {
    final tasks = await widget.api.fetchTasks();
    _lastTasks = tasks;
    return tasks;
  }

  Future<void> _confirmReply(AssistTask task) async {
    final confirmed = await _confirmAction(
      title: '確認接案？',
      message: '接案後，這筆任務會進入處理中狀態。',
    );
    if (confirmed) {
      await _runTaskAction(
        task.id,
        () => widget.api.replyTask(task.id),
        '已確認接案',
      );
    }
  }

  Future<void> _confirmComplete(
    AssistTask task,
    CompletionResult result,
  ) async {
    final noPassenger = result == CompletionResult.noPassenger;
    final confirmed = await _confirmAction(
      title: noPassenger ? '確認以現場無人結案？' : '確認正常完成並結案？',
      message: noPassenger ? '結案後任務將不再顯示為待處理，請確認現場確實無人。' : '結案後任務將不再顯示為待處理。',
    );
    if (confirmed) {
      await _runTaskAction(
        task.id,
        () => widget.api.completeTask(task.id, result),
        noPassenger ? '已以現場無人結案' : '已正常完成結案',
      );
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('確認'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runTaskAction(
    int taskId,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _busyTaskId = taskId);
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
        setState(() => _busyTaskId = 0);
      }
    }
  }

  void _startSessionRecovery() {
    if (!_sessionRecoveryStarted) {
      _recoverFromExpiredSession();
    }
  }

  Future<void> _recoverFromExpiredSession() async {
    if (_sessionRecoveryStarted || !mounted) {
      return;
    }
    _sessionRecoveryStarted = true;
    try {
      await widget.sessionStore.clearSession();
      if (!mounted) {
        return;
      }
      if (widget.user.stationId != null) {
        try {
          await widget.pushService.unsubscribeFromTopic(widget.user.stationId!);
        } catch (_) {
          // Topic cleanup is best effort.
        }
        if (!mounted) {
          return;
        }
      }
    } catch (_) {
      _sessionRecoveryStarted = false;
      if (mounted) {
        showSnackBarMessage(context, '登入狀態清除失敗，請確認儲存空間後重試');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          api: widget.api,
          pushService: widget.pushService,
          sessionStore: widget.sessionStore,
          deviceId: widget.deviceId,
        ),
      ),
    );
    showSnackBarMessage(context, '登入狀態已失效，請重新登入');
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
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
    if (mounted &&
        widget.pushService.refreshSignal.value?.system == PushSystem.limabang) {
      _refresh();
    }
  }
}

String _errorMessage(Object? error) {
  if (error is SocketException) {
    return '目前無法連線，請檢查網路後重試。';
  }
  if (error is ApiException) {
    return '目前無法取得任務，請稍後重試。';
  }
  return '目前無法取得任務，請稍後重試。';
}

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
  var _busyTaskId = 0;
  var _sessionRecoveryStarted = false;

  @override
  void initState() {
    super.initState();
    _tasksFuture = widget.api.fetchTasks();
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
                if (snapshot.error is SessionExpiredException) {
                  _startSessionRecovery();
                }
                return ErrorState(
                  message: _errorMessage(snapshot.error),
                  onRetry: _refresh,
                );
              }
              final tasks = snapshot.data ?? const <AssistTask>[];
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
                  return TaskCard(
                    task: task,
                    busy: _busyTaskId == task.id,
                    onReply: task.status == TaskStatus.pending
                        ? () => _reply(task)
                        : null,
                    onCompleteNormal: task.status == TaskStatus.replied
                        ? () => _complete(task, CompletionResult.normal)
                        : null,
                    onCompleteNoPassenger: task.status == TaskStatus.replied
                        ? () => _complete(task, CompletionResult.noPassenger)
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
      _tasksFuture = widget.api.fetchTasks();
    });
  }

  Future<void> _reply(AssistTask task) async {
    await _runTaskAction(task.id, () => widget.api.replyTask(task.id), '已確認');
  }

  Future<void> _complete(AssistTask task, CompletionResult result) async {
    await _runTaskAction(
      task.id,
      () => widget.api.completeTask(task.id, result),
      '已完成結案',
    );
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
      await widget.sessionStore.clearSession();
    } catch (_) {
      _sessionRecoveryStarted = false;
      if (mounted) {
        showSnackBarMessage(context, '登出失敗，請稍後再試');
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
    if (mounted) {
      _refresh();
    }
  }
}

String _errorMessage(Object? error) {
  if (error is ApiException) {
    return error.message;
  }
  if (error is SocketException) {
    return '無法連線到伺服器，請檢查網路';
  }
  return '讀取資料失敗';
}

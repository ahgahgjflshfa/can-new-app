import 'dart:io';

import 'package:flutter/material.dart';

import '../models/charge_task.dart';
import '../models/charge_user_profile.dart';
import '../services/api_exception.dart';
import '../services/charge_api.dart';
import '../services/push_notification_service.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../widgets/charge_task_card.dart';
import '../widgets/error_state.dart';
import '../widgets/stale_task_banner.dart';
import 'charge_settings_screen.dart';
import 'charge_task_detail_screen.dart';

class ChargeTasksScreen extends StatefulWidget {
  const ChargeTasksScreen({
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
  State<ChargeTasksScreen> createState() => _ChargeTasksScreenState();
}

class _ChargeTasksScreenState extends State<ChargeTasksScreen> {
  late Future<List<ChargeTask>> _tasksFuture;
  String? _error;
  List<ChargeTask>? _lastTasks;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _loadTasks();
    widget.pushService.refreshSignal.addListener(_refreshFromPush);
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
        if (!didPop) _returnToSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('任務列表'),
          leading: IconButton(
            tooltip: '返回系統選擇',
            onPressed: _returnToSelection,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: '重新整理',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '設定',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<ChargeTask>>(
            future: _tasksFuture,
            builder: (context, snapshot) {
              if (_error != null) {
                return ErrorState(message: _error!, onRetry: _refresh);
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
                if (_lastTasks == null) {
                  return ErrorState(
                    message: _chargeErrorMessage(error),
                    onRetry: _refresh,
                  );
                }
              }
              final tasks = snapshot.data ?? _lastTasks ?? const <ChargeTask>[];
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
                      Icons.bolt,
                      size: 72,
                      color: AppColors.chargePrimary,
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
                itemBuilder: (_, index) {
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
                  return ChargeTaskCard(
                    task: tasks[taskIndex],
                    onTap: () => _openDetail(tasks[taskIndex]),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<ChargeTask>> _loadTasks() async {
    final station = widget.user.station.trim();
    if (station.isEmpty) {
      _error = '帳號未設定站點，請至設定登出後重新登入';
      return const <ChargeTask>[];
    }
    _error = null;
    final tasks = await widget.api.fetchTasks();
    final filtered = tasks
        .where((task) => task.station.trim() == station)
        .toList();
    _lastTasks = filtered;
    return filtered;
  }

  void _refresh() => setState(() => _tasksFuture = _loadTasks());

  void _refreshFromPush() {
    if (mounted &&
        widget.pushService.refreshSignal.value?.system == PushSystem.charge) {
      _refresh();
    }
  }

  void _returnToSelection() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  void _openDetail(ChargeTask task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChargeTaskDetailScreen(
          api: widget.api,
          task: task,
          onCompleted: _refresh,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChargeSettingsScreen(
          api: widget.api,
          user: widget.user,
          deviceId: widget.deviceId,
          pushService: widget.pushService,
          sessionStore: widget.sessionStore,
        ),
      ),
    );
  }
}

String _chargeErrorMessage(Object? error) {
  if (error is SocketException) return '目前無法連線，請檢查網路後重試。';
  if (error is ApiException) return '目前無法取得任務，請稍後重試。';
  return '目前無法取得任務，請稍後重試。';
}

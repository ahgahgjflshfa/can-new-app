import 'dart:async';

import 'package:can_new_app/app.dart';
import 'package:can_new_app/models/app_session.dart';
import 'package:can_new_app/models/assist_task.dart';
import 'package:can_new_app/models/can_session.dart';
import 'package:can_new_app/models/can_task.dart';
import 'package:can_new_app/models/can_user_profile.dart';
import 'package:can_new_app/models/charge_session.dart';
import 'package:can_new_app/models/charge_task.dart';
import 'package:can_new_app/models/charge_user_profile.dart';
import 'package:can_new_app/models/completion_result.dart';
import 'package:can_new_app/models/task_status.dart';
import 'package:can_new_app/models/user_profile.dart';
import 'package:can_new_app/services/api_log_store.dart';
import 'package:can_new_app/services/api_exception.dart';
import 'package:can_new_app/services/app_logger.dart';
import 'package:can_new_app/services/can_api.dart';
import 'package:can_new_app/services/limabang_api.dart';
import 'package:can_new_app/services/charge_api.dart';
import 'package:can_new_app/services/push_notification_service.dart';
import 'package:can_new_app/services/session_store.dart';
import 'package:can_new_app/screens/can_settings_screen.dart';
import 'package:can_new_app/screens/can_tasks_screen.dart';
import 'package:can_new_app/screens/settings_screen.dart';
import 'package:can_new_app/screens/tasks_screen.dart';
import 'package:can_new_app/widgets/notification_permission_card.dart';
import 'package:can_new_app/widgets/charge_task_card.dart';
import 'package:can_new_app/widgets/stale_task_banner.dart';
import 'package:can_new_app/widgets/notification_settings.dart';
import 'package:can_new_app/screens/charge_tasks_screen.dart';
import 'package:can_new_app/theme/app_colors.dart';
import 'package:can_new_app/widgets/task_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notification permission remedy is shown only when denied', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPermissionCard(
          state: const PushNotificationState(
            initialized: true,
            permissionLabel: '已拒絕',
            statusMessage: '已啟用',
          ),
          onOpenSettings: () async => opened = true,
        ),
      ),
    );

    expect(find.text('通知未開啟'), findsOneWidget);
    expect(find.text('未開啟通知可能錯過新的站務任務。請到系統設定允許通知。'), findsOneWidget);
    await tester.tap(find.text('開啟通知設定'));
    expect(opened, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationPermissionCard(
          state: PushNotificationState(
            initialized: true,
            permissionLabel: '已允許',
            statusMessage: '已啟用',
          ),
          onOpenSettings: _noopAsync,
        ),
      ),
    );
    expect(find.text('通知未開啟'), findsNothing);
  });

  testWidgets('stale task banner keeps retry available', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StaleTaskBanner(
          message: '目前無法更新，以下是上次載入的任務',
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('目前無法更新，以下是上次載入的任務'), findsOneWidget);
    await tester.tap(find.text('重試'));
    expect(retries, 1);
  });

  testWidgets('Charge task card exposes an inline completion action', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChargeTaskCard(
          task: const ChargeTask(
            serialNumber: 7,
            deviceCode: 'CH-07',
            station: 'A12',
            isDone: false,
            cleanAt: null,
            informTime: 1,
            isDisable: false,
            createdAt: '',
            updatedAt: '',
          ),
          busy: false,
          locked: false,
          onComplete: () => completed = true,
        ),
      ),
    );

    expect(find.text('待處理'), findsOneWidget);
    expect(find.text('標記完成'), findsOneWidget);
    expect(find.text('查看故障詳情'), findsNothing);
    await tester.tap(find.text('標記完成'));
    expect(completed, isTrue);
  });

  testWidgets('shared task status chips use red, yellow, and green', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TaskStatusChip(label: '待處理', status: 'pending'),
              TaskStatusChip(label: '處理中', status: 'replied'),
              TaskStatusChip(label: '已完成', status: 'completed'),
            ],
          ),
        ),
      ),
    );

    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect((chips[0].labelStyle as TextStyle).color, AppColors.taskPending);
    expect((chips[1].labelStyle as TextStyle).color, AppColors.taskConfirmed);
    expect((chips[2].labelStyle as TextStyle).color, AppColors.taskCompleted);
  });

  testWidgets('Charge empty-state description is centered', (tester) async {
    final api = FakeChargeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ChargeTasksScreen(
          api: api,
          user: const ChargeUserProfile(account: 'charge', station: 'A12'),
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: MemorySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final description = tester.widget<Text>(
      find.text('目前沒有待處理任務\n可下拉或按重新整理檢查最新任務'),
    );
    expect(description.textAlign, TextAlign.center);
  });

  testWidgets('Charge list completion sends isDone after confirmation', (
    tester,
  ) async {
    final api = FakeChargeApi(tasks: [_chargeTask()]);
    await tester.pumpWidget(_chargeTasksApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('標記完成'));
    await tester.pump();
    expect(find.text('確定已完成'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '確定'));
    await tester.pumpAndSettle();

    expect(api.updatedValues, [true]);
  });

  testWidgets('Charge list completed task can be reopened inline', (
    tester,
  ) async {
    final api = FakeChargeApi(
      tasks: [
        _chargeTask(
          serialNumber: 9,
          isDone: true,
          cleanAt: '2026-08-08T00:00:00.000Z',
        ),
      ],
    );
    await tester.pumpWidget(_chargeTasksApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('重新開啟'));
    await tester.pump();
    expect(find.text('確定重新開啟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '確定'));
    await tester.pumpAndSettle();

    expect(api.updatedValues, [false]);
  });

  testWidgets('Charge disabled task cannot be changed inline', (tester) async {
    final api = FakeChargeApi(tasks: [_chargeTask(isDisable: true)]);
    await tester.pumpWidget(_chargeTasksApp(api));
    await tester.pumpAndSettle();

    expect(find.text('停用'), findsOneWidget);
    expect(find.text('標記完成'), findsNothing);
    expect(find.text('重新開啟'), findsNothing);
  });

  testWidgets('Charge global account loads all authorized tasks', (
    tester,
  ) async {
    final api = FakeChargeApi(
      tasks: [
        _chargeTask(serialNumber: 11, station: 'A12'),
        _chargeTask(serialNumber: 12, station: 'B12'),
      ],
    );
    await tester.pumpWidget(
      _chargeTasksApp(
        api,
        user: const ChargeUserProfile(
          account: 'ChargeAdmin',
          station: null,
          accessScope: 'global',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.fetchCalls, 1);
    expect(find.text('CH-11'), findsOneWidget);
    expect(find.text('CH-12'), findsOneWidget);
  });

  testWidgets('local invalidation and routing precede pending remote cleanup', (
    tester,
  ) async {
    final api = FakeApi()..restoreToken('old-token');
    final push = _BlockingPushNotificationService();
    final observer = _RecordingNavigatorObserver();
    final store = MemorySessionStore()
      ..session = const AppSession(
        token: 'old-token',
        user: UserProfile(
          name: 'Staff',
          stationId: 'A17',
          sectionId: null,
          role: 'staff',
        ),
        deviceId: 'device',
      );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: SettingsScreen(
          api: api,
          user: store.session!.user,
          deviceId: 'device',
          pushService: push,
          sessionStore: store,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認登出'));
    await push.started.future;

    expect(api.token, isNull);
    expect(observer.pushCount, greaterThanOrEqualTo(4));

    push.release.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('local logout commit failure does not start remote cleanup', (
    tester,
  ) async {
    final api = FakeApi();
    final store = MemorySessionStore()
      ..session = const AppSession(
        token: 'token',
        user: UserProfile(
          name: 'Staff',
          stationId: 'A17',
          sectionId: null,
          role: 'staff',
        ),
        deviceId: 'device',
      )
      ..clearSessionFails = true;
    final push = RecordingPushNotificationService();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: api,
          user: store.session!.user,
          deviceId: 'device',
          pushService: push,
          sessionStore: store,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認登出'));
    await tester.pumpAndSettle();

    expect(store.session, isNotNull);
    expect(api.logoutCalls, 0);
    expect(push.unsubscribeCalls, 0);
  });

  testWidgets('validates login inputs', (tester) async {
    await tester.pumpWidget(_app(FakeApi()));
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();

    expect(find.text('請輸入帳號'), findsOneWidget);
    expect(find.text('請輸入密碼'), findsOneWidget);
  });

  testWidgets('logs in and shows task actions', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountField')), 'staff01');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(api.loggedInAccount, 'staff01');
    expect(find.text('任務列表'), findsOneWidget);
    expect(find.text('領航站 出入口'), findsOneWidget);
    expect(find.text('待處理'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reply-105')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(api.repliedTaskIds, [105]);
  });

  testWidgets(
    'Limabang locks every task-card action during a confirmed mutation',
    (tester) async {
      final api = FakeApi(
        tasks: [
          _task(id: 201),
          _task(id: 202, status: TaskStatus.replied),
        ],
      );
      api.mutationCompleter = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: TasksScreen(
            api: api,
            user: const UserProfile(
              name: 'Staff',
              stationId: 'A17',
              sectionId: null,
              role: 'staff',
            ),
            deviceId: 'device',
            pushService: PushNotificationService(),
            sessionStore: MemorySessionStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reply-201')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '確認'));
      await tester.pump();

      for (final key in [
        'reply-201',
        'complete-normal-202',
        'complete-empty-202',
      ]) {
        final button = tester.widget(find.byKey(Key(key)));
        expect(
          (button as dynamic).onPressed,
          isNull,
          reason: '$key must be locked',
        );
      }
      api.mutationCompleter!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('returns from task list to system selection', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountField')), 'staff01');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('任務列表'), findsOneWidget);

    await tester.tap(find.byTooltip('返回系統選擇'));
    await tester.pumpAndSettle();

    expect(find.text('站務系統'), findsOneWidget);
    expect(find.text('立碼幫幫忙'), findsOneWidget);
    expect(find.text('Q 潔淨立馬清'), findsOneWidget);
  });

  testWidgets('completes replied task as no passenger', (tester) async {
    final api = FakeApi(tasks: [_task(id: 49, status: TaskStatus.replied)]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountField')), 'staff01');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('complete-empty-49')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確定'));
    await tester.pumpAndSettle();

    expect(api.completedTasks, {49: CompletionResult.noPassenger});
  });

  testWidgets('shows advanced settings and exports logs', (tester) async {
    AppLogger.clear();
    ApiLogStore.clear();
    // Memory-only reset; disk I/O is covered by push_history_test.dart.
    PushNotificationHistory.entries.value = <PushNotificationHistoryEntry>[];
    AppLogger.log('Test', 'sample log line');
    final api = FakeApi();
    final pushService = PushNotificationService();
    pushService.state.value = const PushNotificationState(
      initialized: true,
      permissionLabel: '已允許',
      statusMessage: '已啟用',
      fcmToken: 'test-fcm-token',
    );
    await tester.pumpWidget(
      MyApp(
        limabangApi: api,
        canApi: FakeCanApi(),
        pushService: pushService,
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountField')), 'staff01');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);

    await tester.tap(find.byTooltip('進階設定'));
    await tester.pumpAndSettle();

    expect(find.text('進階設定'), findsOneWidget);
    expect(find.text('Firebase 推播'), findsOneWidget);
    expect(find.text('已啟用'), findsWidgets);
    expect(find.text('test-fcm-token...'), findsOneWidget);

    // Increase viewport so App Logs tile is visible without scrolling.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();

    await tester.tap(find.text('App Logs'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sample log line'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exportLogsButton')));
    await tester.pumpAndSettle();

    expect(AppLogger.exportText(), contains('sample log line'));
  });

  testWidgets('restores saved session to task list', (tester) async {
    final api = FakeApi();
    final sessionStore = MemorySessionStore()
      ..session = AppSession(
        token: 'saved-token',
        user: const UserProfile(
          name: '王小明',
          stationId: 'A17',
          sectionId: null,
          role: 'staff',
        ),
        deviceId: 'saved-device-id',
      );
    api.restoreToken('saved-token');

    await tester.pumpWidget(
      MyApp(
        limabangApi: api,
        canApi: FakeCanApi(),
        pushService: PushNotificationService(),
        sessionStore: sessionStore,
        initialLimabangSession: sessionStore.session,
      ),
    );
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    expect(find.text('任務列表'), findsOneWidget);
    expect(find.byKey(const Key('loginButton')), findsNothing);
    expect(find.text('領航站 出入口'), findsOneWidget);
  });

  testWidgets('selects CAN system and logs in', (tester) async {
    final canApi = FakeCanApi();
    await tester.pumpWidget(
      MyApp(
        limabangApi: FakeApi(),
        canApi: canApi,
        pushService: PushNotificationService(),
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    // 系統選擇畫面
    expect(find.text('站務系統'), findsOneWidget);
    expect(find.text('Q 潔淨立馬清'), findsOneWidget);

    await tester.tap(find.text('Q 潔淨立馬清'));
    await tester.pumpAndSettle();

    // Q 潔淨登入畫面
    expect(find.text('Q 潔淨立馬清'), findsOneWidget);
    expect(find.byKey(const Key('canAccountField')), findsOneWidget);
    expect(find.byKey(const Key('canPasswordField')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('canAccountField')), 'can01');
    await tester.enterText(find.byKey(const Key('canPasswordField')), 'secret');
    await tester.tap(find.byKey(const Key('canLoginButton')));
    await tester.pumpAndSettle();

    expect(canApi.loggedInAccount, 'can01');
    expect(find.text('任務列表'), findsOneWidget);
    expect(find.textContaining('A12-B1-M1-1'), findsOneWidget);
    expect(find.textContaining('A12-B2-M2-2'), findsOneWidget);
  });

  testWidgets('completes CAN task', (tester) async {
    final canApi = FakeCanApi();
    await tester.pumpWidget(
      MyApp(
        limabangApi: FakeApi(),
        canApi: canApi,
        pushService: PushNotificationService(),
        sessionStore: MemorySessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Q 潔淨立馬清'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('canAccountField')), 'can01');
    await tester.enterText(find.byKey(const Key('canPasswordField')), 'secret');
    await tester.tap(find.byKey(const Key('canLoginButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('A12-B1-M1-1'), findsOneWidget);

    await tester.tap(find.text('完成清潔').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確定'));
    await tester.pumpAndSettle();

    expect(canApi.completedSerialNumbers, [1]);
    expect(find.textContaining('A12-B1-M1-1'), findsNothing);
  });

  testWidgets('CAN logout clears only CAN session', (tester) async {
    final sessionStore = MemorySessionStore()
      ..session = AppSession(
        token: 'limabang-token',
        user: const UserProfile(
          name: '王小明',
          stationId: 'A17',
          sectionId: null,
          role: 'staff',
        ),
        deviceId: 'device',
      )
      ..canSession = const CanSession(
        token: 'can-token',
        user: CanUserProfile(
          account: 'can01',
          station: 'A12',
          topic: 'can_A12',
        ),
        deviceId: 'device',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: CanSettingsScreen(
          api: FakeCanApi(),
          user: const CanUserProfile(
            account: 'can01',
            station: 'A12',
            topic: 'can_A12',
          ),
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(sessionStore.session, isNotNull);
    expect(sessionStore.canSession, isNull);
    expect(sessionStore.clearSessionCalls, 0);
    expect(find.byKey(const Key('canAccountField')), findsOneWidget);
  });

  testWidgets('CAN logout navigates when remote cleanup fails', (tester) async {
    final api = FakeCanApi()..logoutFails = true;
    final sessionStore = MemorySessionStore()
      ..canSession = const CanSession(
        token: 'can-token',
        user: CanUserProfile(
          account: 'can01',
          station: 'A12',
          topic: 'can_A12',
        ),
        deviceId: 'device',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: CanSettingsScreen(
          api: api,
          user: const CanUserProfile(
            account: 'can01',
            station: 'A12',
            topic: 'can_A12',
          ),
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(sessionStore.canSession, isNull);
    expect(find.byKey(const Key('canAccountField')), findsOneWidget);
  });

  testWidgets('CAN logout stays on settings when local clear fails', (
    tester,
  ) async {
    final limabangSession = AppSession(
      token: 'limabang-token',
      user: const UserProfile(
        name: '王小明',
        stationId: 'A17',
        sectionId: null,
        role: 'staff',
      ),
      deviceId: 'device',
    );
    final canSession = const CanSession(
      token: 'can-token',
      user: CanUserProfile(account: 'can01', station: 'A12', topic: 'can_A12'),
      deviceId: 'device',
    );
    final sessionStore = MemorySessionStore()
      ..session = limabangSession
      ..canSession = canSession
      ..clearCanFails = true;
    await tester.pumpWidget(
      MaterialApp(
        home: CanSettingsScreen(
          api: FakeCanApi(),
          user: canSession.user,
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('登出失敗，工作階段仍保留；請確認儲存空間後重試'), findsOneWidget);
    expect(find.byKey(const Key('canAccountField')), findsNothing);
    expect(sessionStore.session, same(limabangSession));
    expect(sessionStore.canSession, same(canSession));
  });

  testWidgets('CAN blank station loads tasks through the scoped endpoint', (
    tester,
  ) async {
    final api = FakeCanApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CanTasksScreen(
          api: api,
          user: const CanUserProfile(
            account: 'can01',
            station: '  ',
            topic: 'can_region_north',
            accessScope: 'region',
            region: 'north',
          ),
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: MemorySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.fetchTasksCalls, 1);
    expect(find.text('帳號未設定站點，請至設定登出後重新登入'), findsNothing);
  });

  testWidgets(
    'CAN null station subscribes to its backend topic and loads tasks',
    (tester) async {
      final api = FakeCanApi();
      final pushService = RecordingPushNotificationService();
      await tester.pumpWidget(
        MaterialApp(
          home: CanTasksScreen(
            api: api,
            user: const CanUserProfile(
              account: 'North',
              station: null,
              topic: 'can_region_north',
              accessScope: 'region',
              region: 'north',
            ),
            deviceId: 'device',
            pushService: pushService,
            sessionStore: MemorySessionStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.fetchTasksCalls, 1);
      expect(pushService.subscribeCalls, 1);
    },
  );

  testWidgets('CAN station account uses GET task and station-topic fallback', (
    tester,
  ) async {
    final api = FakeCanApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CanTasksScreen(
          api: api,
          user: const CanUserProfile(
            account: 'can01',
            station: ' A12 ',
            topic: null,
          ),
          deviceId: 'device',
          pushService: PushNotificationService(),
          sessionStore: MemorySessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.fetchTasksCalls, 1);
  });

  testWidgets('Limabang logout clears only Limabang and navigates to login', (
    tester,
  ) async {
    final sessionStore = _sessionStoreWithBothSessions();
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: FakeApi(),
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(sessionStore.session, isNull);
    expect(sessionStore.canSession, same(canSession));
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });

  testWidgets('Limabang logout continues after cleanup failures', (
    tester,
  ) async {
    final api = FakeApi()..logoutFails = true;
    final pushService = RecordingPushNotificationService()
      ..unsubscribeFails = true;
    final sessionStore = _sessionStoreWithBothSessions();
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: pushService,
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(pushService.unsubscribeCalls, 1);
    expect(api.logoutCalls, 1);
    expect(sessionStore.session, isNull);
    expect(sessionStore.canSession, same(canSession));
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });

  testWidgets('Limabang logout stays on settings when local clear fails', (
    tester,
  ) async {
    final sessionStore = _sessionStoreWithBothSessions()
      ..clearSessionFails = true;
    final limabangSession = sessionStore.session;
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: FakeApi(),
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsLogoutButton')));
    await _confirmLogout(tester);
    await tester.pumpAndSettle();

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('登出失敗，工作階段仍保留；請確認儲存空間後重試'), findsOneWidget);
    expect(find.byKey(const Key('loginButton')), findsNothing);
    expect(sessionStore.session, same(limabangSession));
    expect(sessionStore.canSession, same(canSession));
  });

  testWidgets('expired Limabang load recovers without clearing CAN', (
    tester,
  ) async {
    final api = FakeApi()..fetchFailsSessionExpired = true;
    final sessionStore = _sessionStoreWithBothSessions();
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loginButton')), findsOneWidget);
    expect(sessionStore.session, isNull);
    expect(sessionStore.canSession, same(canSession));
    expect(find.text('登入狀態已失效，請重新登入'), findsOneWidget);
  });

  testWidgets('expired Limabang action recovers without clearing CAN', (
    tester,
  ) async {
    final api = FakeApi()..replyFailsSessionExpired = true;
    final sessionStore = _sessionStoreWithBothSessions();
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reply-105')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loginButton')), findsOneWidget);
    expect(sessionStore.session, isNull);
    expect(sessionStore.canSession, same(canSession));
  });

  testWidgets('expired Limabang recovery stays on tasks when clear fails', (
    tester,
  ) async {
    final api = FakeApi()..fetchFailsSessionExpired = true;
    final sessionStore = _sessionStoreWithBothSessions()
      ..clearSessionFails = true;
    final limabangSession = sessionStore.session;
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('任務列表'), findsOneWidget);
    expect(find.text('登入狀態清除失敗，請確認儲存空間後重試'), findsOneWidget);
    expect(find.byKey(const Key('loginButton')), findsNothing);
    expect(sessionStore.session, same(limabangSession));
    expect(sessionStore.canSession, same(canSession));
  });

  testWidgets('expired Limabang recovery can retry after clear failure', (
    tester,
  ) async {
    final api = FakeApi()..replyFailsSessionExpired = true;
    final sessionStore = _sessionStoreWithBothSessions()
      ..clearSessionFails = true;
    final limabangSession = sessionStore.session;
    final canSession = sessionStore.canSession;
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-105')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();
    expect(find.text('任務列表'), findsOneWidget);
    expect(find.text('登入狀態清除失敗，請確認儲存空間後重試'), findsOneWidget);
    expect(find.byKey(const Key('loginButton')), findsNothing);
    expect(sessionStore.session, same(limabangSession));
    expect(sessionStore.canSession, same(canSession));

    sessionStore.clearSessionFails = false;
    await tester.tap(find.byKey(const Key('reply-105')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(sessionStore.clearSessionCalls, 2);
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });

  testWidgets('concurrent expired task failures recover once', (tester) async {
    final api = FakeApi(tasks: [_task(id: 105), _task(id: 106)])
      ..replyFailsSessionExpired = true
      ..replyFailureDelay = const Duration(milliseconds: 30);
    final sessionStore = _sessionStoreWithBothSessions();
    await tester.pumpWidget(
      MaterialApp(
        home: TasksScreen(
          api: api,
          user: _limabangUser,
          deviceId: 'device',
          pushService: RecordingPushNotificationService(),
          sessionStore: sessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reply-105')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();

    expect(sessionStore.clearSessionCalls, 1);
    expect(find.byKey(const Key('loginButton')), findsOneWidget);
  });
}

void _noop() {}

Future<void> _noopAsync() async {}

Future<void> _confirmLogout(WidgetTester tester) async {
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '確認登出'));
}

const _limabangUser = UserProfile(
  name: '王小明',
  stationId: 'A17',
  sectionId: null,
  role: 'staff',
);

MemorySessionStore _sessionStoreWithBothSessions() {
  return MemorySessionStore()
    ..session = const AppSession(
      token: 'limabang-token',
      user: _limabangUser,
      deviceId: 'device',
    )
    ..canSession = const CanSession(
      token: 'can-token',
      user: CanUserProfile(account: 'can01', station: 'A12', topic: 'can_A12'),
      deviceId: 'device',
    );
}

Widget _app(FakeApi api) {
  return MyApp(
    limabangApi: api,
    canApi: FakeCanApi(),
    pushService: PushNotificationService(),
    sessionStore: MemorySessionStore(),
  );
}

ChargeTask _chargeTask({
  int serialNumber = 8,
  String station = 'A12',
  bool isDone = false,
  String? cleanAt,
  bool isDisable = false,
}) {
  return ChargeTask(
    serialNumber: serialNumber,
    deviceCode: 'CH-$serialNumber',
    station: station,
    isDone: isDone,
    cleanAt: cleanAt,
    informTime: 1,
    isDisable: isDisable,
    createdAt: '',
    updatedAt: '',
  );
}

Widget _chargeTasksApp(FakeChargeApi api, {ChargeUserProfile? user}) {
  return MaterialApp(
    home: ChargeTasksScreen(
      api: api,
      user: user ?? const ChargeUserProfile(account: 'charge', station: 'A12'),
      deviceId: 'device',
      pushService: PushNotificationService(),
      sessionStore: MemorySessionStore(),
    ),
  );
}

class FakeChargeApi implements ChargeApi {
  FakeChargeApi({List<ChargeTask>? tasks}) : tasks = tasks ?? const [];

  final List<ChargeTask> tasks;
  var fetchCalls = 0;
  var updateCalls = 0;
  final List<bool> updatedValues = [];
  @override
  String? token;
  @override
  void restoreToken(String token) => this.token = token;
  @override
  void invalidateToken({String? token}) => this.token = null;
  @override
  Future<ChargeUserProfile> login({
    required String account,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> logout({String? token}) async {}
  @override
  Future<List<ChargeTask>> fetchTasks() async {
    fetchCalls++;
    return tasks;
  }

  @override
  Future<ChargeTask> fetchTask(int serialNumber) => throw UnimplementedError();
  @override
  Future<void> updateTask(int serialNumber, {required bool isDone}) async {
    updateCalls++;
    updatedValues.add(isDone);
  }
}

class MemorySessionStore implements SessionStore {
  AppSession? session;
  CanSession? canSession;
  ChargeSession? chargeSession;
  var deviceId = 'test-device-id';
  var clearSessionCalls = 0;
  var clearSessionFails = false;
  var clearCanFails = false;

  @override
  Future<void> clearSession() async {
    clearSessionCalls++;
    if (clearSessionFails) {
      throw StateError('local Limabang clear failed');
    }
    session = null;
  }

  @override
  Future<String> getOrCreateDeviceId() async => deviceId;

  @override
  Future<AppSession?> loadSession() async => session;

  @override
  Future<void> saveSession(AppSession session) async {
    this.session = session;
  }

  @override
  Future<CanSession?> loadCanSession() async => canSession;

  @override
  Future<void> saveCanSession(CanSession session) async {
    canSession = session;
  }

  @override
  Future<void> clearCanSession() async {
    if (clearCanFails) {
      throw StateError('local CAN clear failed');
    }
    canSession = null;
  }

  @override
  Future<ChargeSession?> loadChargeSession() async => chargeSession;

  @override
  Future<void> saveChargeSession(ChargeSession session) async {
    chargeSession = session;
  }

  @override
  Future<void> clearChargeSession() async {
    chargeSession = null;
  }
}

class RecordingPushNotificationService extends PushNotificationService {
  var subscribeCalls = 0;
  var unsubscribeCalls = 0;
  var unsubscribeFails = false;

  @override
  Future<void> subscribeToTopic(String topic) async {
    subscribeCalls++;
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    unsubscribeCalls++;
    if (unsubscribeFails) {
      throw StateError('unsubscribe failed');
    }
  }
}

class _BlockingPushNotificationService
    extends RecordingPushNotificationService {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    started.complete();
    await release.future;
    await super.unsubscribeFromTopic(topic);
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  var pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class FakeApi implements LimabangApi {
  FakeApi({List<AssistTask>? tasks}) : tasks = tasks ?? [_task(id: 105)];

  final List<AssistTask> tasks;
  final List<int> repliedTaskIds = [];
  final Map<int, CompletionResult> completedTasks = {};
  String? loggedInAccount;
  var loggedOut = false;
  var logoutCalls = 0;
  var logoutFails = false;
  var fetchTasksCalls = 0;
  var fetchFailsSessionExpired = false;
  var replyFailsSessionExpired = false;
  var replyFailureDelay = Duration.zero;
  Completer<void>? mutationCompleter;

  @override
  String? token;

  @override
  void restoreToken(String token) {
    this.token = token;
  }

  @override
  void invalidateToken({String? token}) {
    if (token == null || this.token == token) this.token = null;
  }

  @override
  Future<UserProfile> login({
    required String account,
    required String password,
    required String deviceType,
    required String deviceId,
    String? fcmToken,
  }) async {
    loggedInAccount = account;
    token = 'token';
    return const UserProfile(
      name: '王小明',
      stationId: 'A17',
      sectionId: null,
      role: 'staff',
    );
  }

  @override
  Future<void> logout({String? token}) async {
    logoutCalls++;
    loggedOut = true;
    if (logoutFails) {
      throw StateError('remote logout failed');
    }
    if (token == null || this.token == token) this.token = null;
  }

  @override
  Future<List<AssistTask>> fetchTasks() async {
    fetchTasksCalls++;
    if (fetchFailsSessionExpired) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      throw const SessionExpiredException();
    }
    return tasks;
  }

  @override
  Future<void> replyTask(int id) async {
    if (mutationCompleter != null) await mutationCompleter!.future;
    if (replyFailsSessionExpired) {
      await Future<void>.delayed(replyFailureDelay);
      throw const SessionExpiredException();
    }
    repliedTaskIds.add(id);
  }

  @override
  Future<void> completeTask(int id, CompletionResult result) async {
    if (mutationCompleter != null) await mutationCompleter!.future;
    completedTasks[id] = result;
  }
}

class FakeCanApi implements CanApi {
  FakeCanApi({List<CanTask>? tasks}) : _tasks = tasks ?? _defaultTasks();

  final List<CanTask> _tasks;
  final List<int> completedSerialNumbers = [];
  String? loggedInAccount;
  var fetchTasksCalls = 0;
  var logoutFails = false;

  static List<CanTask> _defaultTasks() => [
    CanTask(
      serialNumber: 1,
      station: 'A12',
      trashBin: 'A12-B1-M1-1',
      isDone: false,
      cleanAt: null,
      informTime: 1,
      resolutionType: 0,
      visitorID: 'abc123',
      isDisable: false,
      createdAt: '2024-01-15T08:30:00.000Z',
      updatedAt: '2024-01-15T08:30:00.000Z',
    ),
    CanTask(
      serialNumber: 2,
      station: 'A12',
      trashBin: 'A12-B2-M2-2',
      isDone: false,
      cleanAt: null,
      informTime: 2,
      resolutionType: 0,
      visitorID: 'def456',
      isDisable: false,
      createdAt: '2024-01-15T09:15:00.000Z',
      updatedAt: '2024-01-15T09:15:00.000Z',
    ),
  ];

  @override
  String? token;

  @override
  void restoreToken(String token) {
    this.token = token;
  }

  @override
  void invalidateToken({String? token}) {
    if (token == null || this.token == token) this.token = null;
  }

  @override
  Future<CanUserProfile> login({
    required String account,
    required String password,
  }) async {
    loggedInAccount = account;
    token = 'can-token';
    return CanUserProfile(account: account, station: 'A12', topic: 'can_A12');
  }

  @override
  Future<void> logout({String? token}) async {
    if (logoutFails) {
      throw StateError('remote logout failed');
    }
    if (token == null || this.token == token) this.token = null;
  }

  @override
  Future<List<CanTask>> fetchTasks() async {
    fetchTasksCalls++;
    return _tasks.where((t) => !t.isDone).toList(growable: false);
  }

  @override
  Future<void> updateTask(
    int serialNumber, {
    required bool isDone,
    required int resolutionType,
  }) async {
    completedSerialNumbers.add(serialNumber);
    final index = _tasks.indexWhere((t) => t.serialNumber == serialNumber);
    if (index != -1) {
      final task = _tasks[index];
      _tasks[index] = CanTask(
        serialNumber: task.serialNumber,
        station: task.station,
        trashBin: task.trashBin,
        isDone: isDone,
        cleanAt: isDone ? DateTime.now().toIso8601String() : task.cleanAt,
        informTime: task.informTime,
        resolutionType: resolutionType,
        visitorID: task.visitorID,
        isDisable: task.isDisable,
        createdAt: task.createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
    }
  }
}

AssistTask _task({required int id, TaskStatus status = TaskStatus.pending}) {
  return AssistTask(
    id: id,
    stationId: 'A17',
    stationName: '領航站',
    locationName: '出入口',
    locationCode: 'A17-ASSIST-1',
    status: status,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1770011612000),
    repliedAt: null,
    doneAt: null,
  );
}

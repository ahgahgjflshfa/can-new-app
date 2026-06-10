import 'package:can_new_app/app.dart';
import 'package:can_new_app/models/app_session.dart';
import 'package:can_new_app/models/assist_task.dart';
import 'package:can_new_app/models/can_session.dart';
import 'package:can_new_app/models/can_task.dart';
import 'package:can_new_app/models/can_user_profile.dart';
import 'package:can_new_app/models/completion_result.dart';
import 'package:can_new_app/models/task_status.dart';
import 'package:can_new_app/models/user_profile.dart';
import 'package:can_new_app/services/api_log_store.dart';
import 'package:can_new_app/services/app_logger.dart';
import 'package:can_new_app/services/can_api.dart';
import 'package:can_new_app/services/limabang_api.dart';
import 'package:can_new_app/services/push_notification_service.dart';
import 'package:can_new_app/services/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('validates login inputs', (tester) async {
    await tester.pumpWidget(_app(FakeApi()));
    await tester.pumpAndSettle();

    // 系統選擇畫面 → 點立碼幫幫忙
    await tester.tap(find.text('立碼幫幫忙'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();

    expect(find.text('請輸入員工帳號'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(api.repliedTaskIds, [105]);
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
    await tester.pumpAndSettle();

    expect(api.completedTasks, {49: CompletionResult.noPassenger});
  });

  testWidgets('shows advanced settings and exports logs', (tester) async {
    AppLogger.clear();
    ApiLogStore.clear();
    PushNotificationHistory.clear();
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

    await tester.tap(find.text('標記完成').first);
    await tester.pumpAndSettle();

    expect(canApi.completedSerialNumbers, [1]);
    expect(find.textContaining('A12-B1-M1-1'), findsNothing);
  });
}

Widget _app(FakeApi api) {
  return MyApp(
    limabangApi: api,
    canApi: FakeCanApi(),
    pushService: PushNotificationService(),
    sessionStore: MemorySessionStore(),
  );
}

class MemorySessionStore implements SessionStore {
  AppSession? session;
  CanSession? canSession;
  var deviceId = 'test-device-id';

  @override
  Future<void> clearSession() async {
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
    canSession = null;
  }
}

class FakeApi implements LimabangApi {
  FakeApi({List<AssistTask>? tasks}) : tasks = tasks ?? [_task(id: 105)];

  final List<AssistTask> tasks;
  final List<int> repliedTaskIds = [];
  final Map<int, CompletionResult> completedTasks = {};
  String? loggedInAccount;
  var loggedOut = false;

  @override
  String? token;

  @override
  void restoreToken(String token) {
    this.token = token;
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
  Future<void> logout() async {
    loggedOut = true;
    token = null;
  }

  @override
  Future<List<AssistTask>> fetchTasks() async => tasks;

  @override
  Future<void> replyTask(int id) async {
    repliedTaskIds.add(id);
  }

  @override
  Future<void> completeTask(int id, CompletionResult result) async {
    completedTasks[id] = result;
  }
}

class FakeCanApi implements CanApi {
  FakeCanApi({List<CanTask>? tasks}) : _tasks = tasks ?? _defaultTasks();

  final List<CanTask> _tasks;
  final List<int> completedSerialNumbers = [];
  String? loggedInAccount;

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
  Future<CanUserProfile> login({
    required String account,
    required String password,
  }) async {
    loggedInAccount = account;
    token = 'can-token';
    return CanUserProfile(account: account, station: 'A12');
  }

  @override
  Future<void> logout() async {
    token = null;
  }

  @override
  Future<List<CanTask>> fetchTasks() async =>
      _tasks.where((t) => !t.isDone).toList(growable: false);

  @override
  Future<List<CanTask>> fetchTasksByStation(String stationCode) async =>
      _tasks.where((t) => t.station == stationCode && !t.isDone).toList(growable: false);

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

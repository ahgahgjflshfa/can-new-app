import 'dart:async';

import 'package:can_new_app/models/app_session.dart';
import 'package:can_new_app/models/assist_task.dart';
import 'package:can_new_app/models/can_session.dart';
import 'package:can_new_app/models/can_task.dart';
import 'package:can_new_app/models/can_user_profile.dart';
import 'package:can_new_app/models/charge_session.dart';
import 'package:can_new_app/models/charge_task.dart';
import 'package:can_new_app/models/charge_task_status.dart';
import 'package:can_new_app/models/charge_resolution_type.dart';
import 'package:can_new_app/models/charge_user_profile.dart';
import 'package:can_new_app/models/user_profile.dart';
import 'package:can_new_app/services/api_exception.dart';
import 'package:can_new_app/services/can_api.dart';
import 'package:can_new_app/services/can_api_client.dart';
import 'package:can_new_app/services/charge_api.dart';
import 'package:can_new_app/services/limabang_api.dart';
import 'package:can_new_app/services/push_notification_service.dart';
import 'package:can_new_app/services/session_store.dart';
import 'package:can_new_app/screens/can_tasks_screen.dart';
import 'package:can_new_app/screens/can_login_screen.dart';
import 'package:can_new_app/screens/charge_tasks_screen.dart';
import 'package:can_new_app/screens/system_selection_screen.dart';
import 'package:can_new_app/screens/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push publishes two same-system deliveries and isolates systems', () {
    final service = PushNotificationService();
    final seen = <PushRefreshEvent>[];
    service.refreshSignal.addListener(
      () => seen.add(service.refreshSignal.value!),
    );

    service.publishForTesting(system: PushSystem.can, messageId: null);
    service.publishForTesting(system: PushSystem.can, messageId: null);
    service.publishForTesting(system: PushSystem.charge);

    expect(seen, hasLength(3));
    expect(seen[0].system, PushSystem.can);
    expect(seen[1].system, PushSystem.can);
    expect(seen[1].sequence, isNot(seen[0].sequence));
    expect(seen[2].system, PushSystem.charge);
  });

  test(
    'real task listeners refresh only for their production system scope',
    () {
      final push = PushNotificationService();
      final canApi = _CanApi();
      final chargeApi = _ChargeApi();
      var canRefreshes = 0;
      var chargeRefreshes = 0;
      var limabangRefreshes = 0;

      void listen(PushSystem system, void Function() refresh) {
        push.refreshSignal.addListener(() {
          if (push.shouldRefreshFor(system)) refresh();
        });
      }

      listen(PushSystem.can, () {
        canRefreshes++;
        canApi.refreshCallback();
      });
      listen(PushSystem.charge, () {
        chargeRefreshes++;
        chargeApi.refreshCallback();
      });
      listen(PushSystem.limabang, () => limabangRefreshes++);

      push.publishForTesting(system: PushSystem.can);
      push.publishForTesting(system: PushSystem.can);
      expect(canRefreshes, 2);
      expect(canApi.refreshCalls, 2);
      expect(chargeRefreshes, 0);
      expect(chargeApi.refreshCalls, 0);
      expect(limabangRefreshes, 0);

      push.publishForTesting(system: PushSystem.charge);
      expect(chargeRefreshes, 1);
      expect(chargeApi.refreshCalls, 1);
      expect(canRefreshes, 2);

      // Unknown/missing system refreshes ALL listeners once each.
      push.publishForTesting(system: null);
      expect(canRefreshes, 3);
      expect(canApi.refreshCalls, 3);
      expect(chargeRefreshes, 2);
      expect(chargeApi.refreshCalls, 2);
      expect(limabangRefreshes, 1);
    },
  );

  test('topicFor matches production topic naming per system', () {
    final push = PushNotificationService();
    expect(push.topicFor(PushSystem.limabang, 'A12'), 'A12');
    expect(push.topicFor(PushSystem.can, 'A12'), 'can_A12');
    expect(push.topicFor(PushSystem.charge, 'A12'), 'charge_A12');
  });

  testWidgets(
    'null-id notification sequences route repeatedly and stored sessions select flows',
    (tester) async {
      final push = PushNotificationService();
      final store = _Store()
        ..can = const CanSession(
          token: 'can-token',
          user: CanUserProfile(account: 'can', station: 'A1', topic: 'can_A1'),
          deviceId: 'device',
        );
      // A nullable-ID open already present before mount is the cold-start path.
      push.publishForTesting(
        system: PushSystem.can,
        messageId: null,
        navigation: true,
      );
      final seeded = push.navigationSignal.value!;
      await tester.pumpWidget(_selection(push, store));
      await tester.pumpAndSettle();
      expect(find.byType(CanTasksScreen), findsOneWidget);
      await tester.tap(find.byTooltip('返回系統選擇'));
      await tester.pumpAndSettle();
      // A new object with the same nullable-ID sequence must be ignored.
      push.navigationSignal.value = PushNotificationEvent(
        sequence: seeded.sequence,
        source: seeded.source,
        system: seeded.system,
        messageId: null,
        data: seeded.data,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CanTasksScreen), findsNothing);
      // A different sequence is a new notification and routes once more.
      push.publishForTesting(
        system: PushSystem.can,
        messageId: null,
        navigation: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CanTasksScreen), findsOneWidget);

      final chargeStore = _Store()
        ..charge = const ChargeSession(
          token: 'charge-token',
          user: ChargeUserProfile(account: 'charge', station: 'A1'),
          deviceId: 'device',
        );
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: _selection(PushNotificationService(), chargeStore),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('無線充故障'));
      await tester.pumpAndSettle();
      expect(find.byType(ChargeTasksScreen), findsOneWidget);
    },
  );

  test('authenticated JSON and non-JSON 401 are both session expiry', () async {
    for (final body in ['{"error":"expired"}', '<html>expired</html>']) {
      final client = CanApiClient(
        transport: (_, _, _, _) async => CanHttpResponse(401, body),
      )..restoreToken('still-held');
      expect(client.fetchTasks(), throwsA(isA<SessionExpiredException>()));
      await Future<void>.delayed(Duration.zero);
      expect(client.token, 'still-held');
    }
  });

  testWidgets(
    'CAN expiry commits and routes before cleanup, while commit failure survives',
    (tester) async {
      final api = _CanApi()
        ..token = 'expired-token'
        ..expireOnFetch = true;
      final push = _PushRecorder();
      final store = _Store()
        ..can = const CanSession(
          token: 'expired-token',
          user: CanUserProfile(account: 'can', station: 'A1', topic: 'can_A1'),
          deviceId: 'd',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: CanTasksScreen(
            api: api,
            user: store.can!.user,
            deviceId: 'd',
            pushService: push,
            sessionStore: store,
          ),
        ),
      );
      for (var i = 0; i < 20 && !push.started.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(push.started.isCompleted, isTrue);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(store.can, isNull);
      expect(find.byType(CanLoginScreen), findsOneWidget);
      expect(api.token, isNull);
      expect(push.unsubscribeCalls, 1);
      push.release.complete();
      await tester.pumpAndSettle();
      expect(push.unsubscribeCalls, 1);

      final failedApi = _CanApi()
        ..token = 'kept-token'
        ..expireOnFetch = true;
      final failedPush = _PushRecorder();
      final failedStore = _Store()..canClearFails = true;
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: MaterialApp(
            home: CanTasksScreen(
              api: failedApi,
              user: const CanUserProfile(
                account: 'can',
                station: 'A1',
                topic: 'can_A1',
              ),
              deviceId: 'd',
              pushService: failedPush,
              sessionStore: failedStore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CanTasksScreen), findsOneWidget);
      expect(failedApi.token, 'kept-token');
      expect(failedPush.unsubscribeCalls, 0);
    },
  );

  testWidgets(
    'Limabang empty success then failed refresh retains retry banner',
    (tester) async {
      final api = _LimabangApi()
        ..responses = [<AssistTask>[], ApiException('offline')];
      await tester.pumpWidget(
        MaterialApp(
          home: TasksScreen(
            api: api,
            user: const UserProfile(
              name: 'staff',
              stationId: 'A1',
              sectionId: null,
              role: 'staff',
            ),
            deviceId: 'd',
            pushService: PushNotificationService(),
            sessionStore: _Store(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('目前沒有待處理任務'), findsOneWidget);
      await tester.tap(find.byTooltip('重新整理'));
      await tester.pump();
      api.failure!.completeError(ApiException('offline'));
      await tester.pumpAndSettle();
      expect(find.text('目前無法更新，請重試確認最新任務'), findsOneWidget);
      expect(find.text('重試'), findsOneWidget);
    },
  );

  testWidgets(
    'CAN locks every card action and has no constrained text overflow',
    (tester) async {
      final api = _CanApi()..tasks = [_canTask(1), _canTask(2)];
      final pending = Completer<void>();
      api.updateCompleter = pending;
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: CanTasksScreen(
              api: api,
              user: const CanUserProfile(account: 'a', station: 'A1'),
              deviceId: 'd',
              pushService: PushNotificationService(),
              sessionStore: _Store(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成清潔').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '確認結案'));
      await tester.pump();
      expect(
        find
            .widgetWithText(FilledButton, '完成清潔')
            .evaluate()
            .every((e) => (e.widget as FilledButton).onPressed == null),
        isTrue,
      );
      expect(
        find
            .widgetWithText(OutlinedButton, '無髒污（結案）')
            .evaluate()
            .every((e) => (e.widget as OutlinedButton).onPressed == null),
        isTrue,
      );
      expect(
        errors
            .where((e) => e.exceptionAsString().contains('RenderFlex overflow'))
            .isEmpty,
        isTrue,
      );
      pending.complete();
      await tester.pumpAndSettle();
    },
  );
}

Widget _selection(PushNotificationService push, _Store store) => MaterialApp(
  home: SystemSelectionScreen(
    limabangApi: _LimabangApi(),
    canApi: _CanApi(),
    chargeApi: _ChargeApi(),
    pushService: push,
    sessionStore: store,
  ),
);

CanTask _canTask(int id) => CanTask(
  serialNumber: id,
  station: 'A1',
  trashBin: 'Bin $id',
  isDone: false,
  informTime: 1,
  resolutionType: 0,
  isDisable: false,
  createdAt: '',
  updatedAt: '',
);

class _Store implements SessionStore {
  AppSession? session;
  CanSession? can;
  ChargeSession? charge;
  bool canClearFails = false;
  @override
  Future<String> getOrCreateDeviceId() async => 'd';
  @override
  Future<AppSession?> loadSession() async => session;
  @override
  Future<void> saveSession(AppSession value) async => session = value;
  @override
  Future<void> clearSession() async => session = null;
  @override
  Future<CanSession?> loadCanSession() async => can;
  @override
  Future<void> saveCanSession(CanSession value) async => can = value;
  @override
  Future<void> clearCanSession() async {
    if (canClearFails) throw StateError('storage');
    can = null;
  }

  @override
  Future<ChargeSession?> loadChargeSession() async => charge;
  @override
  Future<void> saveChargeSession(ChargeSession value) async => charge = value;
  @override
  Future<void> clearChargeSession() async => charge = null;
}

class _LimabangApi implements LimabangApi {
  List<Object> responses = [<AssistTask>[]];
  int calls = 0;
  Completer<List<AssistTask>>? failure;
  @override
  String? token;
  @override
  void restoreToken(String value) => token = value;
  @override
  void invalidateToken({String? token}) => this.token = null;
  @override
  Future<UserProfile> login({
    required String account,
    required String password,
    required String deviceType,
    required String deviceId,
    String? fcmToken,
  }) => throw UnimplementedError();
  @override
  Future<void> logout({String? token}) async {}
  @override
  Future<List<AssistTask>> fetchTasks() {
    final value = responses[calls++];
    if (value is ApiException) {
      failure = Completer<List<AssistTask>>();
      failure!.future.catchError((_) => <AssistTask>[]);
      return failure!.future;
    }
    return Future.value(value as List<AssistTask>);
  }

  @override
  Future<void> replyTask(int taskId) async {}
  @override
  Future<void> completeTask(int taskId, result) async {}
}

class _CanApi implements CanApi {
  List<CanTask> tasks = [];
  Completer<void>? updateCompleter;
  bool expireOnFetch = false;
  int refreshCalls = 0;
  void refreshCallback() => refreshCalls++;
  @override
  String? token;
  @override
  void restoreToken(String value) => token = value;
  @override
  void invalidateToken({String? token}) => this.token = null;
  @override
  Future<CanUserProfile> login({
    required String account,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> logout({String? token}) async {}
  @override
  Future<List<CanTask>> fetchTasks() async => tasks;
  @override
  Future<List<CanTask>> fetchTasksByStation(String station) async {
    if (expireOnFetch) throw const SessionExpiredException();
    return tasks;
  }

  @override
  Future<void> updateTask(
    int serialNumber, {
    required bool isDone,
    required int resolutionType,
  }) async => updateCompleter?.future;
}

class _PushRecorder extends PushNotificationService {
  int unsubscribeCalls = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    unsubscribeCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class _ChargeApi implements ChargeApi {
  int refreshCalls = 0;
  void refreshCallback() => refreshCalls++;
  @override
  String? token;
  @override
  void restoreToken(String value) => token = value;
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
  Future<List<ChargeTask>> fetchTasks() async => [];
  @override
  Future<ChargeTask> fetchTask(int serialNumber) => throw UnimplementedError();
  @override
  Future<void> updateTask(
    int serialNumber, {
    required ChargeTaskStatus status,
    required ChargeResolutionType resolutionType,
  }) async {}
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

/// Android high-importance channel used for FCM + local foreground banners.
const String kStationTasksHighChannelId = 'station_tasks_high';
const String kStationTasksHighChannelName = '站務任務通知';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.log(
    'FirebaseMessaging',
    'BACKGROUND messageId=${message.messageId ?? '-'} data=${message.data.keys.join(',')}',
  );
  // Await disk write so the background isolate does not exit early.
  await PushNotificationHistory.record(
    source: 'BACKGROUND',
    system: PushNotificationHistory.systemString(message.data['system']),
    messageId: message.messageId,
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}

class PushNotificationState {
  const PushNotificationState({
    required this.initialized,
    required this.permissionLabel,
    required this.statusMessage,
    this.fcmToken,
  });

  const PushNotificationState.notInitialized()
    : initialized = false,
      permissionLabel = '尚未初始化',
      statusMessage = '尚未啟用',
      fcmToken = null;

  final bool initialized;
  final String permissionLabel;
  final String statusMessage;
  final String? fcmToken;
}

enum PushSystem { limabang, can, charge }

class PushNotificationEvent {
  const PushNotificationEvent({
    required this.sequence,
    required this.source,
    required this.system,
    required this.messageId,
    required this.data,
    this.title,
    this.body,
  });

  final int sequence;
  final String source;
  final PushSystem? system;
  final String? messageId;
  final Map<String, dynamic> data;
  final String? title;
  final String? body;
}

class PushRefreshEvent {
  const PushRefreshEvent({required this.sequence, required this.system});

  final int sequence;
  final PushSystem? system;
}

/// Persists the set of FCM topics this device should stay subscribed to.
///
/// Survives process restarts so [PushNotificationService.resubscribeAllTopics]
/// can re-bind after token rotation (critical on some OEM work phones).
class PushTopicRegistry {
  PushTopicRegistry._();

  static const _fileName = 'push_subscribed_topics.json';

  static final Set<String> _topics = <String>{};

  /// Serializes disk writes so concurrent add/remove/load do not interleave.
  static Future<void> _writeChain = Future<void>.value();

  /// Test-only override for the directory that holds the topics file.
  /// Shares the same override pattern as [PushNotificationHistory].
  @visibleForTesting
  static Directory? debugDirectoryOverride;

  static List<String> get topics {
    final list = _topics.toList()..sort();
    return List<String>.unmodifiable(list);
  }

  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Returns null when disk is unavailable (e.g. widget tests without override).
  static Future<File?> _topicsFile() async {
    try {
      final override =
          debugDirectoryOverride ??
          PushNotificationHistory.debugDirectoryOverride;
      if (override != null) {
        return File('${override.path}/$_fileName');
      }
      // Avoid path_provider in unit/widget tests — it can hang pumpAndSettle.
      if (_isFlutterTest) {
        return null;
      }
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'topic registry file unavailable error=$error',
      );
      return null;
    }
  }

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final gate = Completer<void>();
    final previous = _writeChain;
    _writeChain = gate.future;
    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      if (!gate.isCompleted) gate.complete();
    });
  }

  static Future<void> load() async {
    await _synchronized(() async {
      try {
        final file = await _topicsFile();
        if (file == null || !await file.exists()) {
          return;
        }
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          _topics.clear();
          return;
        }
        final decoded = jsonDecode(raw);
        _topics.clear();
        if (decoded is List) {
          for (final item in decoded) {
            final topic = item?.toString().trim() ?? '';
            if (topic.isNotEmpty) {
              _topics.add(topic);
            }
          }
        }
        AppLogger.log(
          'FirebaseMessaging',
          'topic registry loaded count=${_topics.length}',
        );
      } on Object catch (error) {
        AppLogger.log(
          'FirebaseMessaging',
          'topic registry load failed error=$error',
        );
      }
    });
  }

  static Future<void> add(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) return;
    await _synchronized(() async {
      _topics.add(trimmed);
      await _persist();
    });
  }

  static Future<void> remove(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) return;
    await _synchronized(() async {
      _topics.remove(trimmed);
      await _persist();
    });
  }

  static Future<void> _persist() async {
    try {
      final file = await _topicsFile();
      if (file == null) {
        return;
      }
      final sorted = _topics.toList()..sort();
      await file.writeAsString(jsonEncode(sorted), flush: true);
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'topic registry persist failed error=$error',
      );
    }
  }

  /// Clears in-memory topics and deletes the on-disk file (tests / reset).
  @visibleForTesting
  static Future<void> clear() async {
    await _synchronized(() async {
      _topics.clear();
      try {
        final file = await _topicsFile();
        if (file != null && await file.exists()) {
          await file.delete();
        }
      } on Object catch (error) {
        AppLogger.log(
          'FirebaseMessaging',
          'topic registry clear failed error=$error',
        );
      }
    });
  }
}

class PushNotificationService {
  final ValueNotifier<PushNotificationState> state = ValueNotifier(
    const PushNotificationState.notInitialized(),
  );
  final ValueNotifier<PushRefreshEvent?> refreshSignal = ValueNotifier(null);

  /// Last notification, including its target system and payload.
  final ValueNotifier<PushNotificationEvent?> notificationSignal =
      ValueNotifier(null);

  /// Notifications that were opened/tapped, including cold-start opens.
  final ValueNotifier<PushNotificationEvent?> navigationSignal = ValueNotifier(
    null,
  );

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _localNotifications;
  int _nextEventSequence = 0;
  int _nextLocalNotificationId = 1;
  bool _localNotificationsReady = false;

  /// Sorted list of topics currently tracked for (re)subscription.
  List<String> get subscribedTopics => PushTopicRegistry.topics;

  /// Publishes an event through the same signals used by Firebase listeners.
  /// This is intentionally small so deterministic callers (and tests) can
  /// exercise sequencing without requiring a native Firebase channel.
  @visibleForTesting
  void publishForTesting({
    required PushSystem? system,
    String? messageId,
    bool navigation = false,
  }) {
    final event = PushNotificationEvent(
      sequence: ++_nextEventSequence,
      source: 'TEST',
      system: system,
      messageId: messageId,
      data: const <String, dynamic>{},
    );
    notificationSignal.value = event;
    if (navigation) navigationSignal.value = event;
    refreshSignal.value = PushRefreshEvent(
      sequence: event.sequence,
      system: event.system,
    );
  }

  /// Test helper: track a topic without calling native FCM.
  @visibleForTesting
  Future<void> trackTopicForTesting(String topic) =>
      PushTopicRegistry.add(topic);

  /// Test helper: drop a tracked topic without calling native FCM.
  @visibleForTesting
  Future<void> untrackTopicForTesting(String topic) =>
      PushTopicRegistry.remove(topic);

  String? get fcmToken => state.value.fcmToken;

  static bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      await PushNotificationHistory.load();
      await PushTopicRegistry.load();
      _messaging = FirebaseMessaging.instance;

      await _initLocalNotifications();

      // iOS: show system banner/sound/badge while app is in foreground.
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final settings = await _messaging!.requestPermission();
      final permissionLabel = _permissionLabel(settings.authorizationStatus);
      final denied = settings.authorizationStatus == AuthorizationStatus.denied;

      final token = await _messaging!.getToken();
      state.value = PushNotificationState(
        initialized: true,
        permissionLabel: permissionLabel,
        statusMessage: _statusMessage(token: token, denied: denied),
        fcmToken: token,
      );
      AppLogger.log(
        'FirebaseMessaging',
        'initialized permission=${state.value.permissionLabel} token=${token == null ? 'none' : 'available'}',
      );

      // Critical: after token rotation, FCM topic bindings can drop on some
      // OEM devices (公務機). Always re-subscribe tracked topics.
      _messaging!.onTokenRefresh.listen((nextToken) async {
        state.value = PushNotificationState(
          initialized: true,
          permissionLabel: state.value.permissionLabel,
          statusMessage: _statusMessage(
            token: nextToken,
            denied: state.value.permissionLabel == '已拒絕',
          ),
          fcmToken: nextToken,
        );
        AppLogger.log('FirebaseMessaging', 'token refreshed');
        await resubscribeAllTopics();
      });

      FirebaseMessaging.onMessage.listen((message) {
        AppLogger.log(
          'FirebaseMessaging',
          'FOREGROUND messageId=${message.messageId ?? '-'} title=${message.notification?.title ?? '-'} data=${message.data.keys.join(',')}',
        );
        unawaited(
          PushNotificationHistory.record(
            source: 'FOREGROUND',
            system: PushNotificationHistory.systemString(
              message.data['system'],
            ),
            messageId: message.messageId,
            title: message.notification?.title,
            body: message.notification?.body,
            data: message.data,
          ),
        );
        _publish(message, 'FOREGROUND');
        _publishRefresh();
        unawaited(_showForegroundLocalNotification(message));
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        AppLogger.log(
          'FirebaseMessaging',
          'OPENED messageId=${message.messageId ?? '-'} data=${message.data.keys.join(',')}',
        );
        unawaited(
          PushNotificationHistory.record(
            source: 'OPENED',
            system: PushNotificationHistory.systemString(
              message.data['system'],
            ),
            messageId: message.messageId,
            title: message.notification?.title,
            body: message.notification?.body,
            data: message.data,
          ),
        );
        _publish(message, 'OPENED', navigation: true);
        _publishRefresh();
      });

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        AppLogger.log(
          'FirebaseMessaging',
          'INITIAL messageId=${initialMessage.messageId ?? '-'} data=${initialMessage.data.keys.join(',')}',
        );
        unawaited(
          PushNotificationHistory.record(
            source: 'INITIAL',
            system: PushNotificationHistory.systemString(
              initialMessage.data['system'],
            ),
            messageId: initialMessage.messageId,
            title: initialMessage.notification?.title,
            body: initialMessage.notification?.body,
            data: initialMessage.data,
          ),
        );
        _publish(initialMessage, 'INITIAL', navigation: true);
        _publishRefresh();
      }

      // Re-bind any topics from a previous session once token is available.
      await resubscribeAllTopics();

      // Refresh permission label if settings changed after request.
      try {
        final refreshed = await _messaging!.getNotificationSettings();
        final refreshedLabel = _permissionLabel(refreshed.authorizationStatus);
        final refreshedDenied =
            refreshed.authorizationStatus == AuthorizationStatus.denied;
        if (refreshedLabel != state.value.permissionLabel ||
            refreshedDenied != denied) {
          state.value = PushNotificationState(
            initialized: true,
            permissionLabel: refreshedLabel,
            statusMessage: _statusMessage(
              token: state.value.fcmToken,
              denied: refreshedDenied,
            ),
            fcmToken: state.value.fcmToken,
          );
        }
      } on Object catch (_) {
        // getNotificationSettings is best-effort.
      }
    } on Object catch (error) {
      state.value = const PushNotificationState(
        initialized: false,
        permissionLabel: '不可用',
        statusMessage: 'Firebase 初始化失敗',
      );
      AppLogger.log('FirebaseMessaging', 'initialize failed error=$error');
      // Still try to surface any previously persisted history / topics.
      await PushNotificationHistory.load();
      await PushTopicRegistry.load();
    }
  }

  String _statusMessage({required String? token, required bool denied}) {
    if (denied) {
      return '通知權限已拒絕，請至系統設定開啟';
    }
    if (token == null) {
      return '已初始化，尚未取得 FCM token';
    }
    return '已啟用';
  }

  Future<void> _initLocalNotifications() async {
    if (_isFlutterTest || kIsWeb) {
      AppLogger.log(
        'FirebaseMessaging',
        'local notifications skipped (test/web)',
      );
      return;
    }
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings(
        '@drawable/ic_notification',
      );
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onLocalNotificationTapped,
      );

      final androidPlugin = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            kStationTasksHighChannelId,
            kStationTasksHighChannelName,
            description: '站務任務即時通知（高優先）',
            importance: Importance.max,
            playSound: true,
            showBadge: true,
          ),
        );
      }

      _localNotifications = plugin;
      _localNotificationsReady = true;
      AppLogger.log('FirebaseMessaging', 'local notifications ready');
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'local notifications init failed error=$error',
      );
      _localNotificationsReady = false;
    }
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(decoded);
      final system = _systemFrom(data['system']);
      final event = PushNotificationEvent(
        sequence: ++_nextEventSequence,
        source: 'LOCAL_TAP',
        system: system,
        messageId: data['messageId']?.toString(),
        data: data,
        title: data['title']?.toString(),
        body: data['body']?.toString(),
      );
      notificationSignal.value = event;
      navigationSignal.value = event;
      refreshSignal.value = PushRefreshEvent(
        sequence: event.sequence,
        system: event.system,
      );
      AppLogger.log(
        'FirebaseMessaging',
        'LOCAL_TAP system=${system?.name ?? '-'}',
      );
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'local notification tap parse failed error=$error',
      );
    }
  }

  Future<void> _showForegroundLocalNotification(RemoteMessage message) async {
    if (!_localNotificationsReady || _localNotifications == null) {
      return;
    }
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        '站務通知';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    final payloadMap = <String, dynamic>{
      ...message.data,
      if (message.messageId != null) 'messageId': message.messageId,
      'title': title,
      'body': body,
    };
    try {
      await _localNotifications!.show(
        id: _nextLocalNotificationId++,
        title: title,
        body: body.isEmpty ? null : body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            kStationTasksHighChannelId,
            kStationTasksHighChannelName,
            channelDescription: '站務任務即時通知（高優先）',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            channelShowBadge: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(payloadMap),
      );
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'show foreground notification failed error=$error',
      );
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_messaging == null) {
      // In widget tests messaging is null; skip registry I/O to avoid
      // cross-test async pollution. Production always has messaging after init.
      if (_isFlutterTest) {
        AppLogger.log(
          'FirebaseMessaging',
          'subscribeToTopic skipped (test, messaging null) topic=$trimmed',
        );
        return;
      }
      // Still track desired topic so resubscribe can pick it up after init.
      await PushTopicRegistry.add(trimmed);
      AppLogger.log(
        'FirebaseMessaging',
        'subscribeToTopic deferred (messaging null) topic=$trimmed',
      );
      return;
    }
    try {
      await _messaging!.subscribeToTopic(trimmed);
      await PushTopicRegistry.add(trimmed);
      AppLogger.log('FirebaseMessaging', 'subscribedToTopic topic=$trimmed');
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'subscribeToTopic failed topic=$trimmed error=$error',
      );
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_messaging == null) {
      if (_isFlutterTest) {
        return;
      }
      await PushTopicRegistry.remove(trimmed);
      return;
    }
    try {
      await _messaging!.unsubscribeFromTopic(trimmed);
      await PushTopicRegistry.remove(trimmed);
      AppLogger.log(
        'FirebaseMessaging',
        'unsubscribedFromTopic topic=$trimmed',
      );
    } on Object catch (error) {
      // Still drop from registry so we do not keep re-subscribing a dead topic.
      await PushTopicRegistry.remove(trimmed);
      AppLogger.log(
        'FirebaseMessaging',
        'unsubscribeFromTopic failed topic=$trimmed error=$error',
      );
    }
  }

  /// Re-subscribes every tracked topic (after init / token refresh).
  Future<void> resubscribeAllTopics() async {
    final topics = PushTopicRegistry.topics;
    if (topics.isEmpty) {
      AppLogger.log('FirebaseMessaging', 'resubscribeAllTopics: none tracked');
      return;
    }
    if (_messaging == null) {
      AppLogger.log(
        'FirebaseMessaging',
        'resubscribeAllTopics skipped (messaging null) count=${topics.length}',
      );
      return;
    }
    AppLogger.log(
      'FirebaseMessaging',
      'resubscribeAllTopics start count=${topics.length} topics=${topics.join(',')}',
    );
    for (final topic in topics) {
      try {
        await _messaging!.subscribeToTopic(topic);
        AppLogger.log('FirebaseMessaging', 'resubscribed topic=$topic');
      } on Object catch (error) {
        AppLogger.log(
          'FirebaseMessaging',
          'resubscribe failed topic=$topic error=$error',
        );
      }
    }
    AppLogger.log('FirebaseMessaging', 'resubscribeAllTopics done');
  }

  String topicFor(PushSystem system, String station) {
    return switch (system) {
      PushSystem.limabang => station,
      PushSystem.can => 'can_$station',
      PushSystem.charge => 'charge_$station',
    };
  }

  /// Whether the current [refreshSignal] should trigger a refresh for [expected].
  ///
  /// Unknown/missing system (`null`) refreshes all screens so production
  /// payloads without a `system` key still update the open task list.
  bool shouldRefreshFor(PushSystem expected) {
    final system = refreshSignal.value?.system;
    return system == null || system == expected;
  }

  Future<void> subscribeToSystemTopic(PushSystem system, String station) {
    return subscribeToTopic(topicFor(system, station));
  }

  Future<void> unsubscribeFromSystemTopic(PushSystem system, String station) {
    return unsubscribeFromTopic(topicFor(system, station));
  }

  void _publish(
    RemoteMessage message,
    String source, {
    bool navigation = false,
  }) {
    // Prefer explicit system; leave null when unknown so refresh-all fallback works.
    final system = _systemFrom(message.data['system']);
    final event = PushNotificationEvent(
      sequence: ++_nextEventSequence,
      source: source,
      system: system,
      messageId: message.messageId,
      data: Map<String, dynamic>.from(message.data),
      title: message.notification?.title,
      body: message.notification?.body,
    );
    notificationSignal.value = event;
    if (navigation) navigationSignal.value = event;
  }

  void _publishRefresh() {
    refreshSignal.value = PushRefreshEvent(
      sequence: _nextEventSequence,
      system: notificationSignal.value?.system,
    );
  }
}

PushSystem? _systemFrom(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized.isEmpty) return null;
  switch (normalized) {
    case 'can':
      return PushSystem.can;
    case 'charge':
      return PushSystem.charge;
    case 'limabang':
    case 'station_services':
      return PushSystem.limabang;
    default:
      AppLogger.log('FirebaseMessaging', 'unknown push system value=$value');
      return null;
  }
}

String _permissionLabel(AuthorizationStatus status) {
  return switch (status) {
    AuthorizationStatus.authorized => '已允許',
    AuthorizationStatus.denied => '已拒絕',
    AuthorizationStatus.notDetermined => '尚未決定',
    AuthorizationStatus.provisional => '暫時允許',
  };
}

class PushNotificationHistoryEntry {
  PushNotificationHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.source,
    this.system,
    this.messageId,
    this.title,
    this.body,
    this.data,
  });

  final int id;
  final DateTime timestamp;
  final String source;
  final String? system;
  final String? messageId;
  final String? title;
  final String? body;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'system': system,
      'messageId': messageId,
      'title': title,
      'body': body,
      'data': data,
    };
  }

  factory PushNotificationHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    Map<String, dynamic>? data;
    if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }
    return PushNotificationHistoryEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: json['source'] as String? ?? '-',
      system: PushNotificationHistory.systemString(json['system']),
      messageId: json['messageId'] as String?,
      title: json['title'] as String?,
      body: json['body'] as String?,
      data: data,
    );
  }
}

class PushNotificationHistory {
  PushNotificationHistory._();

  static const _maxEntries = 30;
  static const _fileName = 'push_notification_history.json';

  static final ValueNotifier<List<PushNotificationHistoryEntry>> entries =
      ValueNotifier(<PushNotificationHistoryEntry>[]);
  static int _nextId = 1;

  /// Serializes disk writes so concurrent record/clear/load do not interleave.
  static Future<void> _writeChain = Future<void>.value();

  /// Test-only override for the directory that holds the history file.
  @visibleForTesting
  static Directory? debugDirectoryOverride;

  /// Coerce FCM `system` (or any dynamic) to a string without throwing.
  static String? systemString(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value.toString();
  }

  static Future<File> _historyFile() async {
    final dir =
        debugDirectoryOverride ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final gate = Completer<void>();
    final previous = _writeChain;
    _writeChain = gate.future;
    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      if (!gate.isCompleted) gate.complete();
    });
  }

  /// Loads persisted history into [entries]. Safe to call multiple times.
  static Future<void> load() async {
    await _synchronized(() async {
      try {
        final file = await _historyFile();
        if (!await file.exists()) {
          return;
        }
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          entries.value = <PushNotificationHistoryEntry>[];
          _nextId = 1;
          return;
        }
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          AppLogger.log('PushHistory', 'load ignored: root is not a list');
          return;
        }
        final loaded = <PushNotificationHistoryEntry>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            loaded.add(PushNotificationHistoryEntry.fromJson(item));
          } else if (item is Map) {
            loaded.add(
              PushNotificationHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          }
        }
        final trimmed = loaded.length > _maxEntries
            ? loaded.sublist(loaded.length - _maxEntries)
            : loaded;
        entries.value = trimmed;
        var maxId = 0;
        for (final e in trimmed) {
          maxId = math.max(maxId, e.id);
        }
        _nextId = maxId + 1;
      } on Object catch (error) {
        AppLogger.log('PushHistory', 'load failed error=$error');
      }
    });
  }

  /// Updates in-memory history and persists the full list to disk.
  ///
  /// Errors are logged and never rethrown to callers.
  static Future<void> record({
    required String source,
    String? system,
    String? messageId,
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) async {
    await _synchronized(() async {
      try {
        final entry = PushNotificationHistoryEntry(
          id: _nextId++,
          timestamp: DateTime.now(),
          source: source,
          system: systemString(system),
          messageId: messageId,
          title: title,
          body: body,
          data: data == null ? null : Map<String, dynamic>.from(data),
        );
        final next = [...entries.value, entry];
        if (next.length > _maxEntries) {
          entries.value = next.sublist(next.length - _maxEntries);
        } else {
          entries.value = next;
        }
        await _writeEntries(entries.value);
      } on Object catch (error) {
        AppLogger.log('PushHistory', 'record/persist failed error=$error');
      }
    });
  }

  static Future<void> _writeEntries(
    List<PushNotificationHistoryEntry> list,
  ) async {
    final file = await _historyFile();
    final payload = jsonEncode(list.map((e) => e.toJson()).toList());
    await file.writeAsString(payload, flush: true);
  }

  /// Clears in-memory history and deletes the on-disk file.
  static Future<void> clear() async {
    await _synchronized(() async {
      entries.value = <PushNotificationHistoryEntry>[];
      _nextId = 1;
      try {
        final file = await _historyFile();
        if (await file.exists()) {
          await file.delete();
        }
      } on Object catch (error) {
        AppLogger.log('PushHistory', 'clear failed error=$error');
      }
    });
  }

  static String exportText() {
    if (entries.value.isEmpty) {
      return 'No push notifications recorded.';
    }
    final buffer = StringBuffer();
    for (final e in entries.value) {
      buffer.writeln(
        '[${_formatTimestamp(e.timestamp)}][${e.source}] '
        'system=${e.system ?? '-'} '
        'id=${e.messageId ?? '-'} title=${e.title ?? '-'}',
      );
      if (e.data != null && e.data!.isNotEmpty) {
        buffer.writeln('  data: ${jsonEncode(e.data)}');
      }
    }
    return buffer.toString();
  }
}

String _formatTimestamp(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  return '${twoDigits(value.month)}/${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
}

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.log(
    'FirebaseMessaging',
    'BACKGROUND messageId=${message.messageId ?? '-'} data=${message.data.keys.join(',')}',
  );
  PushNotificationHistory.record(
    source: 'BACKGROUND',
    system: message.data['system'] as String?,
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
  int _nextEventSequence = 0;

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

  String? get fcmToken => state.value.fcmToken;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _messaging = FirebaseMessaging.instance;

      final settings = await _messaging!.requestPermission();
      final token = await _messaging!.getToken();
      state.value = PushNotificationState(
        initialized: true,
        permissionLabel: _permissionLabel(settings.authorizationStatus),
        statusMessage: token == null ? '已初始化，尚未取得 FCM token' : '已啟用',
        fcmToken: token,
      );
      AppLogger.log(
        'FirebaseMessaging',
        'initialized permission=${state.value.permissionLabel} token=${token == null ? 'none' : 'available'}',
      );

      _messaging!.onTokenRefresh.listen((nextToken) {
        state.value = PushNotificationState(
          initialized: true,
          permissionLabel: state.value.permissionLabel,
          statusMessage: '已啟用',
          fcmToken: nextToken,
        );
        AppLogger.log('FirebaseMessaging', 'token refreshed');
      });

      FirebaseMessaging.onMessage.listen((message) {
        AppLogger.log(
          'FirebaseMessaging',
          'FOREGROUND messageId=${message.messageId ?? '-'} title=${message.notification?.title ?? '-'} data=${message.data.keys.join(',')}',
        );
        PushNotificationHistory.record(
          source: 'FOREGROUND',
          system: message.data['system'] as String?,
          messageId: message.messageId,
          title: message.notification?.title,
          body: message.notification?.body,
          data: message.data,
        );
        _publish(message, 'FOREGROUND');
        _publishRefresh();
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        AppLogger.log(
          'FirebaseMessaging',
          'OPENED messageId=${message.messageId ?? '-'} data=${message.data.keys.join(',')}',
        );
        PushNotificationHistory.record(
          source: 'OPENED',
          system: message.data['system'] as String?,
          messageId: message.messageId,
          title: message.notification?.title,
          body: message.notification?.body,
          data: message.data,
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
        PushNotificationHistory.record(
          source: 'INITIAL',
          system: initialMessage.data['system'] as String?,
          messageId: initialMessage.messageId,
          title: initialMessage.notification?.title,
          body: initialMessage.notification?.body,
          data: initialMessage.data,
        );
        _publish(initialMessage, 'INITIAL', navigation: true);
        _publishRefresh();
      }
    } on Object catch (error) {
      state.value = const PushNotificationState(
        initialized: false,
        permissionLabel: '不可用',
        statusMessage: 'Firebase 初始化失敗',
      );
      AppLogger.log('FirebaseMessaging', 'initialize failed error=$error');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (_messaging == null) {
      return;
    }
    try {
      await _messaging!.subscribeToTopic(topic);
      AppLogger.log('FirebaseMessaging', 'subscribedToTopic topic=$topic');
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'subscribeToTopic failed topic=$topic error=$error',
      );
    }
  }

  String topicFor(PushSystem system, String station) {
    return '${system == PushSystem.charge ? 'charge' : 'can'}_$station';
  }

  Future<void> subscribeToSystemTopic(PushSystem system, String station) {
    return subscribeToTopic(topicFor(system, station));
  }

  Future<void> unsubscribeFromSystemTopic(PushSystem system, String station) {
    return unsubscribeFromTopic(topicFor(system, station));
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (_messaging == null) {
      return;
    }
    try {
      await _messaging!.unsubscribeFromTopic(topic);
      AppLogger.log('FirebaseMessaging', 'unsubscribedFromTopic topic=$topic');
    } on Object catch (error) {
      AppLogger.log(
        'FirebaseMessaging',
        'unsubscribeFromTopic failed topic=$topic error=$error',
      );
    }
  }

  void _publish(
    RemoteMessage message,
    String source, {
    bool navigation = false,
  }) {
    final event = PushNotificationEvent(
      sequence: ++_nextEventSequence,
      source: source,
      system: _systemFrom(message.data['system']),
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
  switch (value) {
    case 'can':
      return PushSystem.can;
    case 'charge':
      return PushSystem.charge;
    case 'limabang':
    case 'station_services':
      return PushSystem.limabang;
    default:
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
}

class PushNotificationHistory {
  PushNotificationHistory._();

  static const _maxEntries = 30;
  static final ValueNotifier<List<PushNotificationHistoryEntry>> entries =
      ValueNotifier(<PushNotificationHistoryEntry>[]);
  static int _nextId = 1;

  static void record({
    required String source,
    String? system,
    String? messageId,
    String? title,
    String? body,
    Map<String, dynamic>? data,
  }) {
    final entry = PushNotificationHistoryEntry(
      id: _nextId++,
      timestamp: DateTime.now(),
      source: source,
      system: system,
      messageId: messageId,
      title: title,
      body: body,
      data: data,
    );
    final next = [...entries.value, entry];
    if (next.length > _maxEntries) {
      entries.value = next.sublist(next.length - _maxEntries);
    } else {
      entries.value = next;
    }
  }

  static void clear() {
    entries.value = <PushNotificationHistoryEntry>[];
  }

  static String exportText() {
    if (entries.value.isEmpty) {
      return 'No push notifications recorded.';
    }
    final buffer = StringBuffer();
    for (final e in entries.value) {
      buffer.writeln(
        '[${_formatTimestamp(e.timestamp)}][${e.source}] '
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

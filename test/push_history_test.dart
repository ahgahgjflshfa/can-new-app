import 'dart:io';

import 'package:can_new_app/services/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('push_history_test_');
    PushNotificationHistory.debugDirectoryOverride = tempDir;
    await PushNotificationHistory.clear();
  });

  tearDown(() async {
    await PushNotificationHistory.clear();
    PushNotificationHistory.debugDirectoryOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('record updates exportText with source, system, and data', () async {
    await PushNotificationHistory.record(
      source: 'FOREGROUND',
      system: 'can',
      messageId: 'msg-1',
      title: '溢滿通知',
      body: 'A12 有新任務',
      data: <String, dynamic>{'system': 'can', 'station': 'A12'},
    );

    final text = PushNotificationHistory.exportText();
    expect(text, contains('[FOREGROUND]'));
    expect(text, contains('system=can'));
    expect(text, contains('id=msg-1'));
    expect(text, contains('title=溢滿通知'));
    expect(text, contains('"station":"A12"'));
    expect(PushNotificationHistory.entries.value, hasLength(1));
  });

  test('systemString coerces non-String values', () {
    expect(PushNotificationHistory.systemString(null), isNull);
    expect(PushNotificationHistory.systemString('can'), 'can');
    expect(PushNotificationHistory.systemString(42), '42');
    expect(PushNotificationHistory.systemString('  '), isNull);
  });

  test('clear empties memory and exportText', () async {
    await PushNotificationHistory.record(source: 'BACKGROUND', system: 'can');
    expect(PushNotificationHistory.entries.value, isNotEmpty);

    await PushNotificationHistory.clear();

    expect(PushNotificationHistory.entries.value, isEmpty);
    expect(
      PushNotificationHistory.exportText(),
      'No push notifications recorded.',
    );
  });

  test('record persists and load restores entries', () async {
    await PushNotificationHistory.record(
      source: 'BACKGROUND',
      system: 'charge',
      messageId: 'bg-9',
      title: '充電任務',
      data: <String, dynamic>{'system': 'charge'},
    );
    expect(PushNotificationHistory.entries.value, hasLength(1));

    // Simulate a fresh isolate / process: wipe memory then reload from disk.
    PushNotificationHistory.entries.value = <PushNotificationHistoryEntry>[];
    expect(PushNotificationHistory.entries.value, isEmpty);

    await PushNotificationHistory.load();

    expect(PushNotificationHistory.entries.value, hasLength(1));
    final entry = PushNotificationHistory.entries.value.single;
    expect(entry.source, 'BACKGROUND');
    expect(entry.system, 'charge');
    expect(entry.messageId, 'bg-9');
    expect(entry.title, '充電任務');
    expect(PushNotificationHistory.exportText(), contains('[BACKGROUND]'));
  });

  test('keeps only the last 30 entries', () async {
    for (var i = 0; i < 35; i++) {
      await PushNotificationHistory.record(
        source: 'FOREGROUND',
        messageId: 'm-$i',
      );
    }
    expect(PushNotificationHistory.entries.value, hasLength(30));
    expect(PushNotificationHistory.entries.value.first.messageId, 'm-5');
    expect(PushNotificationHistory.entries.value.last.messageId, 'm-34');

    PushNotificationHistory.entries.value = <PushNotificationHistoryEntry>[];
    await PushNotificationHistory.load();
    expect(PushNotificationHistory.entries.value, hasLength(30));
    expect(PushNotificationHistory.entries.value.last.messageId, 'm-34');
  });

  group('PushTopicRegistry', () {
    setUp(() async {
      PushTopicRegistry.debugDirectoryOverride = tempDir;
      await PushTopicRegistry.clear();
    });

    tearDown(() async {
      await PushTopicRegistry.clear();
      PushTopicRegistry.debugDirectoryOverride = null;
    });

    test('add tracks topic and unsubscribe removes it', () async {
      await PushTopicRegistry.add('can_A1');
      await PushTopicRegistry.add('  charge_A12  ');
      await PushTopicRegistry.add(''); // ignored
      expect(PushTopicRegistry.topics, ['can_A1', 'charge_A12']);

      await PushTopicRegistry.remove('can_A1');
      expect(PushTopicRegistry.topics, ['charge_A12']);
    });

    test('persist and load restores topics', () async {
      await PushTopicRegistry.add('can_A1');
      await PushTopicRegistry.add('station_A12');
      expect(PushTopicRegistry.topics, hasLength(2));

      // Simulate fresh process: clear memory without deleting file.
      await PushTopicRegistry.clear();
      // clear() deletes file — re-add and wipe memory only via load path:
      await PushTopicRegistry.add('can_A1');
      await PushTopicRegistry.add('station_A12');

      // Wipe in-memory by loading after writing a fresh file from a second add cycle.
      // Directly re-load from disk after clearing memory set via remove-all pattern:
      final service = PushNotificationService();
      await service.trackTopicForTesting('can_B1');
      expect(service.subscribedTopics, contains('can_B1'));

      // Clear memory by loading empty then reloading from disk after re-persist.
      await PushTopicRegistry.clear();
      await PushTopicRegistry.add('can_A1');
      await PushTopicRegistry.add('station_A12');

      // Force empty memory without deleting disk: load after manually clearing
      // is not exposed; instead write then call load after clear+recreate file.
      final file = File('${tempDir.path}/push_subscribed_topics.json');
      expect(await file.exists(), isTrue);
      final onDisk = await file.readAsString();
      expect(onDisk, contains('can_A1'));
      expect(onDisk, contains('station_A12'));

      await PushTopicRegistry.clear();
      expect(PushTopicRegistry.topics, isEmpty);

      await file.writeAsString(onDisk, flush: true);
      await PushTopicRegistry.load();
      expect(PushTopicRegistry.topics, ['can_A1', 'station_A12']);
    });

    test('subscribedTopics is sorted', () async {
      final service = PushNotificationService();
      await service.trackTopicForTesting('z_topic');
      await service.trackTopicForTesting('a_topic');
      await service.trackTopicForTesting('m_topic');
      expect(service.subscribedTopics, ['a_topic', 'm_topic', 'z_topic']);

      await service.untrackTopicForTesting('m_topic');
      expect(service.subscribedTopics, ['a_topic', 'z_topic']);
    });
  });
}

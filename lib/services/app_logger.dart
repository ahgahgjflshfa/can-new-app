import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static const _maxEntries = 300;
  static final ValueNotifier<List<String>> entries = ValueNotifier(<String>[]);

  static void log(String source, String message) {
    final now = DateTime.now();
    final entry = '[${_formatTimestamp(now)}][$source] $message';
    debugPrint(entry);

    final next = [...entries.value, entry];
    if (next.length > _maxEntries) {
      entries.value = next.sublist(next.length - _maxEntries);
    } else {
      entries.value = next;
    }
  }

  static String exportText() {
    if (entries.value.isEmpty) {
      return 'No logs recorded.';
    }
    return entries.value.join('\n');
  }

  static void clear() {
    entries.value = <String>[];
  }
}

String _formatTimestamp(DateTime value) {
  String twoDigits(int input) => input.toString().padLeft(2, '0');
  String threeDigits(int input) => input.toString().padLeft(3, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
      '${twoDigits(value.second)}.${threeDigits(value.millisecond)}';
}

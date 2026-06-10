import 'package:flutter/foundation.dart';

class ApiLogEntry {
  ApiLogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.fullUrl,
    this.requestBody,
    this.statusCode,
    this.responseBody,
    this.durationMs,
    this.error,
  });

  final int id;
  final DateTime timestamp;
  final String method;
  final String path;
  final String fullUrl;
  final String? requestBody;
  final int? statusCode;
  final String? responseBody;
  final int? durationMs;
  final String? error;

  bool get isSuccess =>
      error == null && statusCode != null && statusCode! < 400;
}

class ApiLogStore {
  ApiLogStore._();

  static const _maxEntries = 50;
  static final ValueNotifier<List<ApiLogEntry>> entries = ValueNotifier(
    <ApiLogEntry>[],
  );
  static int _nextId = 1;

  static ApiLogEntry start({
    required String method,
    required String path,
    required String fullUrl,
    String? requestBody,
  }) {
    final entry = ApiLogEntry(
      id: _nextId++,
      timestamp: DateTime.now(),
      method: method,
      path: path,
      fullUrl: fullUrl,
      requestBody: requestBody,
    );
    _append(entry);
    return entry;
  }

  static void complete(
    ApiLogEntry entry, {
    required int statusCode,
    String? responseBody,
    required int durationMs,
  }) {
    final updated = ApiLogEntry(
      id: entry.id,
      timestamp: entry.timestamp,
      method: entry.method,
      path: entry.path,
      fullUrl: entry.fullUrl,
      requestBody: entry.requestBody,
      statusCode: statusCode,
      responseBody: responseBody,
      durationMs: durationMs,
      error: entry.error,
    );
    _replace(entry, updated);
  }

  static void fail(
    ApiLogEntry entry, {
    required String error,
    required int durationMs,
    int? statusCode,
    String? responseBody,
  }) {
    final updated = ApiLogEntry(
      id: entry.id,
      timestamp: entry.timestamp,
      method: entry.method,
      path: entry.path,
      fullUrl: entry.fullUrl,
      requestBody: entry.requestBody,
      statusCode: statusCode,
      responseBody: responseBody,
      durationMs: durationMs,
      error: error,
    );
    _replace(entry, updated);
  }

  static void clear() {
    entries.value = <ApiLogEntry>[];
  }

  static void _append(ApiLogEntry entry) {
    final next = [...entries.value, entry];
    if (next.length > _maxEntries) {
      entries.value = next.sublist(next.length - _maxEntries);
    } else {
      entries.value = next;
    }
  }

  static void _replace(ApiLogEntry oldEntry, ApiLogEntry newEntry) {
    final next = entries.value
        .map((e) => e.id == oldEntry.id ? newEntry : e)
        .toList(growable: false);
    entries.value = next;
  }
}

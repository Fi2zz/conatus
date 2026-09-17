/// [CronStorage] 的本地 JSON 文件实现：任务 JSON + 历史 JSONL。
///
/// 两个文件都按「临时文件 + rename」原子写入；读取对损坏降级（告警 + 空结果），
/// 历史逐行解码跳过撕裂行。本层只认原始 JSON（Map/List），记录语义在
/// `cron_history.dart`。日期一律 ISO 串（兼容读取 dsh-cron 的毫秒数）。
library;

import 'dart:convert';
import 'dart:io';

import 'cron_storage.dart';
import 'cron_types.dart';

/// 基于本地 JSON 文件的 [CronStorage] 实现。
class JsonCronStorage implements CronStorage {
  /// 构造一个文件存储；[onWarning] 接收损坏降级与写入失败的告警。
  JsonCronStorage({
    required this.tasksPath,
    required this.historyPath,
    void Function(String message)? onWarning,
  }) : _onWarning = onWarning;

  /// 任务 JSON 文件路径。
  final String tasksPath;

  /// 历史 JSONL 文件路径。
  final String historyPath;

  final void Function(String message)? _onWarning;

  @override
  CronStorageSnapshot loadTasks() {
    final File file = File(tasksPath);
    if (!file.existsSync()) return const CronStorageSnapshot();
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        _warn('cron: ignoring unreadable storage $tasksPath: not an object');
        return const CronStorageSnapshot();
      }
      return CronStorageSnapshot(
        dynamicTasks: _decodeTaskList(decoded['tasks']),
        runStamps: _decodeRunStamps(decoded['runs']),
        overrides: _decodeOverrides(decoded['overrides']),
      );
    } on Object catch (error) {
      _warn('cron: ignoring unreadable storage $tasksPath: $error');
      return const CronStorageSnapshot();
    }
  }

  @override
  void saveTasks({
    required List<Map<String, Object?>> tasks,
    required Map<String, CronRunStamp> runStamps,
    required Map<String, bool> overrides,
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      'version': kCronStorageVersion,
      'tasks': tasks,
      'runs': <String, Object?>{
        for (final MapEntry<String, CronRunStamp> entry in runStamps.entries)
          entry.key: <String, Object?>{
            'lastRunAt': formatCronInstant(entry.value.lastRunAt),
            'firedAt': formatCronInstant(entry.value.firedAt),
          },
      },
      'overrides': overrides,
    };
    _writeAtomic(
        tasksPath, const JsonEncoder.withIndent('  ').convert(payload));
  }

  @override
  List<Map<String, Object?>> loadHistory() {
    final File file = File(historyPath);
    if (!file.existsSync()) return const <Map<String, Object?>>[];
    try {
      final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
      for (final String line in file.readAsStringSync().split('\n')) {
        if (line.trim().isEmpty) continue;
        final Map<String, Object?>? record = _decodeLine(line);
        if (record != null) lines.add(record);
      }
      return lines;
    } on Object catch (error) {
      _warn('cron: ignoring unreadable history $historyPath: $error');
      return const <Map<String, Object?>>[];
    }
  }

  @override
  void saveHistory(List<Map<String, Object?>> records) {
    final String body = records.map(jsonEncode).join('\n');
    _writeAtomic(historyPath, records.isEmpty ? '' : '$body\n');
  }

  void _writeAtomic(String path, String content) {
    try {
      final File file = File(path);
      file.parent.createSync(recursive: true);
      final File tmp = File('$path.tmp');
      tmp.writeAsStringSync(content);
      tmp.renameSync(path);
    } on Object catch (error) {
      _warn('cron: failed to write $path: $error');
    }
  }

  void _warn(String message) {
    final void Function(String message)? handler = _onWarning;
    if (handler != null) handler(message);
  }
}

Map<String, Object?>? _decodeLine(String line) {
  try {
    final Object? decoded = jsonDecode(line);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on Object {
    // 跳过撕裂行。
  }
  return null;
}

List<Map<String, Object?>> _decodeTaskList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final Object? item in raw)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

Map<String, CronRunStamp> _decodeRunStamps(Object? raw) {
  if (raw is! Map) return const <String, CronRunStamp>{};
  final Map<String, CronRunStamp> stamps = <String, CronRunStamp>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final Object? key = entry.key;
    final Object? value = entry.value;
    if (key is String && value is Map) {
      stamps[key] = CronRunStamp(
        lastRunAt: _decodeInstant(value['lastRunAt']),
        firedAt: _decodeInstant(value['firedAt']),
      );
    }
  }
  return stamps;
}

Map<String, bool> _decodeOverrides(Object? raw) {
  if (raw is! Map) return const <String, bool>{};
  final Map<String, bool> overrides = <String, bool>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final Object? key = entry.key;
    final Object? value = entry.value;
    if (key is String && value is bool) overrides[key] = value;
  }
  return overrides;
}

DateTime? _decodeInstant(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return null;
}

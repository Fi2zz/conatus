/// cron 任务与历史的文件存储：JSON 任务文件 + JSONL 历史文件。
///
/// 两个文件都按「临时文件 + rename」原子写入；读取对损坏降级（告警 + 空结果），
/// 历史逐行解码跳过撕裂行。本层只认原始 JSON（Map/List），记录语义在
/// `cron_history.dart`。任务文件只写显式字段表，内部缓存（cronParsed /
/// cronNext）永不落盘。日期一律 ISO 串（兼容读取 dsh-cron 的毫秒数）。
library;

import 'dart:convert';
import 'dart:io';

import 'cron_types.dart';

/// 启动时从任务文件恢复的运行戳。
class CronRunStamp {
  /// 构造一组运行戳。
  const CronRunStamp({this.lastRunAt, this.firedAt});

  /// 最近一次成功交付的时刻。
  final DateTime? lastRunAt;

  /// at 任务已消费的时刻。
  final DateTime? firedAt;
}

/// 任务文件的加载结果：动态任务原文 + 运行戳 + 启停覆盖。
class CronStorageSnapshot {
  /// 构造一份快照。
  const CronStorageSnapshot({
    this.dynamicTasks = const <Map<String, Object?>>[],
    this.runStamps = const <String, CronRunStamp>{},
    this.overrides = const <String, bool>{},
  });

  /// 持久化的动态任务原文（未校验，交给服务入口校验）。
  final List<Map<String, Object?>> dynamicTasks;

  /// 任务 id → 运行戳。
  final Map<String, CronRunStamp> runStamps;

  /// 任务 id → 启停覆盖。
  final Map<String, bool> overrides;
}

/// cron 任务文件与历史文件的存储端口。
class CronStorage {
  /// 构造一个存储端口；[onWarning] 接收损坏降级与写入失败的告警。
  CronStorage({
    required this.tasksPath,
    required this.historyPath,
    void Function(String message)? onWarning,
  }) : _onWarning = onWarning;

  /// 任务 JSON 文件路径。
  final String tasksPath;

  /// 历史 JSONL 文件路径。
  final String historyPath;

  final void Function(String message)? _onWarning;

  /// 加载任务文件；缺失或损坏降级为空快照并告警。
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

  /// 原子写入任务文件；[tasks] 是服务给出的显式字段表。
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
    _writeAtomic(tasksPath, const JsonEncoder.withIndent('  ').convert(payload));
  }

  /// 加载历史文件，每行一个原始 JSON 对象（旧记录在前）；撕裂行与空行跳过。
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

  /// 原子写入历史 JSONL（每行一条，尾部带换行；空历史写空文件）。
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

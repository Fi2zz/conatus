/// memory 插件的存储端口与两种本地实现。
///
/// 端口是整表快照式的（载入 / 保存），便于替换为数据库或向量库；本地实现
/// 提供纯内存（默认、不落盘）与 JSON 文件两种。
library;

import 'dart:convert';
import 'dart:io';
import 'memory_types.dart';

/// 长记忆存储端口。
abstract class MemoryBackend {
  /// 载入全部记忆。
  Future<List<MemoryEntry>> load();

  /// 覆盖保存全部记忆。
  Future<void> save(List<MemoryEntry> entries);
}

/// 纯内存实现：进程退出即丢失，用作默认后端与测试替身。
class InMemoryMemoryBackend implements MemoryBackend {
  List<MemoryEntry> _entries = <MemoryEntry>[];

  @override
  Future<List<MemoryEntry>> load() async =>
      List<MemoryEntry>.of(_entries, growable: false);

  @override
  Future<void> save(List<MemoryEntry> entries) async {
    _entries = List<MemoryEntry>.of(entries);
  }
}

/// 本地 JSON 实现：整表写入一个文件。
class JsonMemoryBackend implements MemoryBackend {
  JsonMemoryBackend({required this.file});

  /// 记忆文件。
  final File file;

  @override
  Future<List<MemoryEntry>> load() async {
    if (!file.existsSync()) return const <MemoryEntry>[];
    final Object? json = jsonDecode(await file.readAsString());
    if (json is! List<Object?>) return const <MemoryEntry>[];
    return <MemoryEntry>[
      for (final Object? item in json)
        if (item is Map<String, Object?>) MemoryEntry.fromJson(item),
    ];
  }

  @override
  Future<void> save(List<MemoryEntry> entries) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<Map<String, Object?>>[
        for (final MemoryEntry entry in entries) entry.toJson(),
      ]),
      flush: true,
    );
  }
}

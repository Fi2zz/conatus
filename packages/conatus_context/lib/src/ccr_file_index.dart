/// 文件型 CCR 的索引：加载、持久化、TTL 清理与容量淘汰。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'ccr_store.dart';

/// 索引中的一条元数据。
class CcrFileEntry {
  CcrFileEntry({
    required this.chars,
    required this.createdAt,
    required this.lastAccess,
    this.hits = 0,
  });

  /// 原文字符数。
  final int chars;

  /// 首次写入时间。
  final DateTime createdAt;

  /// 最近访问时间。
  DateTime lastAccess;

  /// 命中次数。
  int hits;

  /// 转为对外元数据。
  CcrEntry toMeta(String id) => CcrEntry(
        id: id,
        chars: chars,
        createdAt: createdAt,
        lastAccess: lastAccess,
        hits: hits,
      );
}

/// `index.json` 的内存视图。
class CcrFileIndex {
  CcrFileIndex(this.entries);

  /// 按 id 索引的元数据。
  final Map<String, CcrFileEntry> entries;

  /// 读取索引；缺失或损坏时返回空索引。
  static Future<CcrFileIndex> load(FileSystem fs, String dir) async {
    final Map<String, CcrFileEntry> entries = <String, CcrFileEntry>{};
    try {
      final String text =
          await fs.readText(await fs.resolve('$dir/index.json'));
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return CcrFileIndex(entries);
      final Object? rawEntries = decoded['entries'];
      if (rawEntries is! Map<String, Object?>) return CcrFileIndex(entries);
      for (final MapEntry<String, Object?> item in rawEntries.entries) {
        final CcrFileEntry? entry = _parse(item.value);
        if (entry != null) entries[item.key] = entry;
      }
    } on Object {
      // 索引缺失或损坏：按空存储启动。
    }
    await _dropMissing(fs, dir, entries);
    return CcrFileIndex(entries);
  }

  static Future<void> _dropMissing(
    FileSystem fs,
    String dir,
    Map<String, CcrFileEntry> entries,
  ) async {
    final List<String> missing = <String>[];
    for (final String id in entries.keys) {
      try {
        final FsInfo? info = await fs.stat(await fs.resolve('$dir/$id.txt'));
        if (info == null) missing.add(id);
      } on Object {
        missing.add(id);
      }
    }
    for (final String id in missing) {
      entries.remove(id);
    }
  }

  static CcrFileEntry? _parse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final DateTime? createdAt = DateTime.tryParse('${raw['createdAt']}');
    final DateTime? lastAccess = DateTime.tryParse('${raw['lastAccess']}');
    final Object? chars = raw['chars'];
    if (createdAt == null || lastAccess == null || chars is! int) return null;
    return CcrFileEntry(
      chars: chars,
      createdAt: createdAt,
      lastAccess: lastAccess,
      hits: raw['hits'] is int ? raw['hits']! as int : 0,
    );
  }

  /// 原子写入索引；失败不阻断内存态使用。
  Future<void> flush(FileSystem fs, String dir) async {
    final Map<String, Object?> payload = <String, Object?>{
      for (final MapEntry<String, CcrFileEntry> entry in entries.entries)
        entry.key: <String, Object?>{
          'chars': entry.value.chars,
          'createdAt': entry.value.createdAt.toIso8601String(),
          'lastAccess': entry.value.lastAccess.toIso8601String(),
          'hits': entry.value.hits,
        },
    };
    try {
      await fs.writeText(
        await fs.resolve('$dir/index.json'),
        jsonEncode(<String, Object?>{'version': 1, 'entries': payload}),
      );
    } on Object {
      // 索引写入失败不阻断内存态使用。
    }
  }

  /// 删除过期条目，返回被删除的 id。
  List<String> purgeExpired(DateTime now, Duration ttl) {
    final List<String> removed = <String>[
      for (final MapEntry<String, CcrFileEntry> entry in entries.entries)
        if (now.difference(entry.value.createdAt) > ttl) entry.key,
    ];
    for (final String id in removed) {
      entries.remove(id);
    }
    return removed;
  }

  /// 按最近访问时间淘汰超额条目，返回被删除的 id。
  List<String> evictOverflow(int maxEntries) {
    final List<String> removed = <String>[];
    while (entries.length > maxEntries) {
      final String oldest = entries.entries
          .reduce((MapEntry<String, CcrFileEntry> a,
                  MapEntry<String, CcrFileEntry> b) =>
              a.value.lastAccess.isBefore(b.value.lastAccess) ? a : b)
          .key;
      entries.remove(oldest);
      removed.add(oldest);
    }
    return removed;
  }
}

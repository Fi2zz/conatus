/// 文件型 CCR 存储：内容按 id 落盘，索引原子写入。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'ccr_marker.dart';
import 'ccr_store.dart';

/// 默认 CCR 目录：`<conatus home>/context-cache`。
String contextCacheDir() =>
    '${resolveConatusHome()}${Platform.pathSeparator}context-cache';

class _FileEntry {
  _FileEntry({
    required this.chars,
    required this.createdAt,
    required this.lastAccess,
    this.hits = 0,
  });

  final int chars;
  final DateTime createdAt;
  DateTime lastAccess;
  int hits;

  CcrEntry toMeta(String id) => CcrEntry(
        id: id,
        chars: chars,
        createdAt: createdAt,
        lastAccess: lastAccess,
        hits: hits,
      );
}

/// 文件型 CCR 存储。
class CcrFileStore implements CcrStore {
  CcrFileStore({
    required this.fs,
    required this.dir,
    this.maxEntries = 1000,
    this.ttl = const Duration(hours: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 执行世界文件系统。
  final FileSystem fs;

  /// 存储目录。
  final String dir;

  /// 最大条目数。
  final int maxEntries;

  /// 条目存活时间。
  final Duration ttl;

  final DateTime Function() _now;
  final Map<String, _FileEntry> _entries = <String, _FileEntry>{};
  bool _loaded = false;
  int _hits = 0;

  @override
  int get hits => _hits;

  @override
  int get length => _entries.length;

  @override
  Future<String> put(String content) async {
    await _ensureLoaded();
    final String id = ccrIdOf(content);
    try {
      await fs.writeText(await _target('$id.txt'), content);
    } on Object {
      return id;
    }
    final DateTime now = _now();
    _entries[id] = _FileEntry(
      chars: content.length,
      createdAt: now,
      lastAccess: now,
      hits: _entries[id]?.hits ?? 0,
    );
    _purgeExpired(now);
    _evictOverflow();
    await _flush();
    return id;
  }

  @override
  Future<String?> get(String id) async {
    await _ensureLoaded();
    final _FileEntry? entry = _entries[id];
    if (entry == null) return null;
    if (_expired(entry)) {
      _entries.remove(id);
      await _flush();
      return null;
    }
    final String content;
    try {
      content = await fs.readText(await _target('$id.txt'));
    } on Object {
      _entries.remove(id);
      return null;
    }
    if (ccrIdOf(content) != id) {
      _entries.remove(id);
      return null;
    }
    _hits++;
    entry.hits++;
    entry.lastAccess = _now();
    await _flush();
    return content;
  }

  @override
  Future<CcrEntry?> stat(String id) async {
    await _ensureLoaded();
    return _entries[id]?.toMeta(id);
  }

  @override
  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries.remove(id);
    try {
      await fs.remove(await _target('$id.txt'));
    } on Object {
      // 文件可能已不存在；元数据删除已经完成。
    }
    await _flush();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    for (final String id in List<String>.of(_entries.keys)) {
      try {
        await fs.remove(await _target('$id.txt'));
      } on Object {
        // 忽略单个文件删除失败。
      }
    }
    _entries.clear();
    _hits = 0;
    await _flush();
  }

  Future<FsTarget> _target(String name) => fs.resolve('$dir/$name');

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final String text = await fs.readText(await _target('index.json'));
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return;
      final Object? entries = decoded['entries'];
      if (entries is! Map<String, Object?>) return;
      for (final MapEntry<String, Object?> item in entries.entries) {
        _restoreEntry(item.key, item.value);
      }
    } on Object {
      // 索引缺失或损坏：按空存储启动。
    }
  }

  void _restoreEntry(String id, Object? raw) {
    if (raw is! Map<String, Object?>) return;
    final DateTime? createdAt = DateTime.tryParse('${raw['createdAt']}');
    final DateTime? lastAccess = DateTime.tryParse('${raw['lastAccess']}');
    final Object? chars = raw['chars'];
    if (createdAt == null || lastAccess == null || chars is! int) return;
    _entries[id] = _FileEntry(
      chars: chars,
      createdAt: createdAt,
      lastAccess: lastAccess,
      hits: raw['hits'] is int ? raw['hits']! as int : 0,
    );
  }

  void _purgeExpired(DateTime now) {
    _entries.removeWhere((String _, _FileEntry entry) => _expired(entry));
  }

  bool _expired(_FileEntry entry) => _now().difference(entry.createdAt) > ttl;

  void _evictOverflow() {
    while (_entries.length > maxEntries) {
      final String oldest = _entries.entries
          .reduce((MapEntry<String, _FileEntry> a,
                  MapEntry<String, _FileEntry> b) =>
              a.value.lastAccess.isBefore(b.value.lastAccess) ? a : b)
          .key;
      _entries.remove(oldest);
    }
  }

  Future<void> _flush() async {
    final Map<String, Object?> entries = <String, Object?>{
      for (final MapEntry<String, _FileEntry> entry in _entries.entries)
        entry.key: <String, Object?>{
          'chars': entry.value.chars,
          'createdAt': entry.value.createdAt.toIso8601String(),
          'lastAccess': entry.value.lastAccess.toIso8601String(),
          'hits': entry.value.hits,
        },
    };
    try {
      await fs.writeText(
        await _target('index.json'),
        jsonEncode(<String, Object?>{'version': 1, 'entries': entries}),
      );
    } on Object {
      // 索引写入失败不阻断内存态使用。
    }
  }
}

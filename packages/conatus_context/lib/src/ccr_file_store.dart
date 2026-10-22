/// 文件型 CCR 存储：内容按 id 落盘，索引原子写入。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'ccr_file_index.dart';
import 'ccr_marker.dart';
import 'ccr_store.dart';

/// 默认 CCR 目录：`<conatus home>/context-cache`。
String contextCacheDir() =>
    '${resolveConatusHome()}${Platform.pathSeparator}context-cache';

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
  CcrFileIndex? _index;
  int _hits = 0;

  @override
  int get hits => _hits;

  @override
  int get length => _index?.entries.length ?? 0;

  @override
  Future<String> put(String content) async {
    final CcrFileIndex index = await _ensureLoaded();
    final String id = ccrIdOf(content);
    try {
      await fs.writeText(await _target('$id.txt'), content);
    } on Object {
      return id;
    }
    final DateTime now = _now();
    index.entries[id] = CcrFileEntry(
      chars: content.length,
      createdAt: now,
      lastAccess: now,
      hits: index.entries[id]?.hits ?? 0,
    );
    final List<String> removed = <String>[
      ...index.purgeExpired(now, ttl),
      ...index.evictOverflow(maxEntries),
    ];
    await _deleteAll(removed);
    await index.flush(fs, dir);
    return id;
  }

  @override
  Future<String?> get(String id) async {
    final CcrFileIndex index = await _ensureLoaded();
    final CcrFileEntry? entry = index.entries[id];
    if (entry == null) return null;
    if (_now().difference(entry.createdAt) > ttl) {
      await _drop(id);
      return null;
    }
    final String content;
    try {
      content = await fs.readText(await _target('$id.txt'));
    } on Object {
      await _drop(id);
      return null;
    }
    if (ccrIdOf(content) != id) {
      await _drop(id);
      return null;
    }
    _hits++;
    entry.hits++;
    entry.lastAccess = _now();
    await index.flush(fs, dir);
    return content;
  }

  @override
  Future<CcrEntry?> stat(String id) async {
    final CcrFileIndex index = await _ensureLoaded();
    return index.entries[id]?.toMeta(id);
  }

  @override
  Future<void> remove(String id) async {
    await _drop(id);
    await (await _ensureLoaded()).flush(fs, dir);
  }

  @override
  Future<void> clear() async {
    final CcrFileIndex index = await _ensureLoaded();
    final List<String> ids = List<String>.of(index.entries.keys);
    index.entries.clear();
    _hits = 0;
    await _deleteAll(ids);
    await index.flush(fs, dir);
  }

  Future<CcrFileIndex> _ensureLoaded() async =>
      _index ??= await CcrFileIndex.load(fs, dir);

  Future<FsTarget> _target(String name) => fs.resolve('$dir/$name');

  Future<void> _drop(String id) async {
    final CcrFileIndex index = await _ensureLoaded();
    index.entries.remove(id);
    try {
      await fs.remove(await _target('$id.txt'));
    } on Object {
      // 文件可能已不存在。
    }
  }

  Future<void> _deleteAll(List<String> ids) async {
    for (final String id in ids) {
      try {
        await fs.remove(await _target('$id.txt'));
      } on Object {
        // 忽略单个文件删除失败。
      }
    }
  }
}

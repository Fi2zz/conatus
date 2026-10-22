/// 进程内 CCR 存储：LRU + TTL。
library;

import 'dart:collection';

import 'ccr_marker.dart';
import 'ccr_store.dart';

class _MemoryEntry {
  _MemoryEntry({
    required this.content,
    required this.createdAt,
    required this.lastAccess,
    this.hits = 0,
  });

  final String content;
  final DateTime createdAt;
  DateTime lastAccess;
  int hits;

  CcrEntry toMeta(String id) => CcrEntry(
        id: id,
        chars: content.length,
        createdAt: createdAt,
        lastAccess: lastAccess,
        hits: hits,
      );
}

/// 内存型 CCR 存储，按访问顺序做 LRU 淘汰。
class CcrMemoryStore implements CcrStore {
  CcrMemoryStore({
    this.maxEntries = 1000,
    this.ttl = const Duration(hours: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 最大条目数。
  final int maxEntries;

  /// 条目存活时间。
  final Duration ttl;

  final DateTime Function() _now;
  final LinkedHashMap<String, _MemoryEntry> _entries =
      LinkedHashMap<String, _MemoryEntry>();
  int _hits = 0;

  @override
  int get hits => _hits;

  @override
  int get length => _entries.length;

  @override
  Future<String> put(String content) async {
    _purgeExpired();
    final String id = ccrIdOf(content);
    final _MemoryEntry? previous = _entries.remove(id);
    _entries[id] = _MemoryEntry(
      content: content,
      createdAt: _now(),
      lastAccess: _now(),
      hits: previous?.hits ?? 0,
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return id;
  }

  @override
  Future<String?> get(String id) async {
    final _MemoryEntry? entry = _entries[id];
    if (entry == null) return null;
    if (_expired(entry)) {
      _entries.remove(id);
      return null;
    }
    _hits++;
    entry.hits++;
    entry.lastAccess = _now();
    _entries.remove(id);
    _entries[id] = entry;
    return entry.content;
  }

  @override
  Future<CcrEntry?> stat(String id) async => _entries[id]?.toMeta(id);

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    _hits = 0;
  }

  void _purgeExpired() {
    final List<String> expired = <String>[
      for (final MapEntry<String, _MemoryEntry> entry in _entries.entries)
        if (_expired(entry.value)) entry.key,
    ];
    for (final String id in expired) {
      _entries.remove(id);
    }
  }

  bool _expired(_MemoryEntry entry) => _now().difference(entry.createdAt) > ttl;
}

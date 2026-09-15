/// memory 插件：长记忆库（写入 / 关键词召回 / 遗忘 / 容量治理）。
///
/// 服务键 `'memory'`。记忆以自由文本存入，召回时按查询词元与记忆文本/标签的
/// 重叠数打分（中英文混合按字母数字词 + 中文二元组切分），同分按新旧排序。
/// 超过 [maxEntries] 时逐出最旧的一条。存储经 [MemoryBackend] 端口落盘。
///
/// ```dart
/// final memory = provideMemory(app);
/// await memory.remember('用户喜欢京剧', tags: {'偏好'});
/// for (final MemoryEntry e in memory.recall('京剧', limit: 3)) print(e.text);
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'memory_backend.dart';
import 'memory_types.dart';

/// 长记忆库服务。
class MemoryStore {
  MemoryStore({this.maxEntries = 1000, MemoryBackend? backend})
      : _backend = backend ?? InMemoryMemoryBackend() {
    if (maxEntries < 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', '必须是非负整数');
    }
  }

  /// 容量上限，超出时逐出最旧的一条。
  final int maxEntries;

  final MemoryBackend _backend;
  final List<MemoryEntry> _entries = <MemoryEntry>[];
  final List<void Function()> _listeners = <void Function()>[];
  bool _loaded = false;
  int _seq = 0;

  /// 当前记忆（加载后）。
  List<MemoryEntry> get entries => List<MemoryEntry>.unmodifiable(_entries);

  /// 记忆条数。
  int get length => _entries.length;

  /// 是否已从后端加载。
  bool get loaded => _loaded;

  /// 从后端加载记忆；幂等。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final List<MemoryEntry> loaded = await _backend.load();
    if (loaded.isEmpty) return;
    _entries
      ..clear()
      ..addAll(loaded);
    _notify();
  }

  /// 记住一段文本，返回新条目。首次调用会自动 [load]。
  Future<MemoryEntry> remember(
    String text, {
    Set<String> tags = const <String>{},
  }) async {
    await load();
    final MemoryEntry entry = MemoryEntry(
      id: _nextId(),
      text: text,
      tags: Set<String>.of(tags),
      createdAt: DateTime.now(),
    );
    _entries.add(entry);
    _govern();
    await _backend.save(_entries);
    _notify();
    return entry;
  }

  /// 按关键词召回，返回按得分（同分按新→旧）排序的前 [limit] 条。
  ///
  /// 只看已加载的记忆；需要读盘时先 [load]。
  List<MemoryEntry> recall(String query, {int limit = 5}) {
    final Set<String> queryTokens = _tokenize(query);
    if (queryTokens.isEmpty || limit <= 0) return const <MemoryEntry>[];
    final List<(MemoryEntry, int)> scored = <(MemoryEntry, int)>[];
    for (final MemoryEntry entry in _entries) {
      final int score = _score(entry, queryTokens);
      if (score > 0) scored.add((entry, score));
    }
    scored.sort(((MemoryEntry, int) a, (MemoryEntry, int) b) {
      final int byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : b.$1.createdAt.compareTo(a.$1.createdAt);
    });
    return scored
        .take(limit)
        .map(((MemoryEntry, int) entry) => entry.$1)
        .toList(growable: false);
  }

  /// 按 id 遗忘一条。返回是否确实删除了。首次调用会自动 [load]。
  Future<bool> forget(String id) async {
    await load();
    final int before = _entries.length;
    _entries.removeWhere((MemoryEntry entry) => entry.id == id);
    if (_entries.length == before) return false;
    await _backend.save(_entries);
    _notify();
    return true;
  }

  /// 按正文**完全一致**遗忘（删除所有匹配条目），返回删除条数。
  Future<int> forgetByText(String text) =>
      _forgetWhere((MemoryEntry entry) => entry.text == text);

  /// 按正文**包含** [query]（不区分大小写）遗忘，返回删除条数。
  ///
  /// [query] 为空时不删除任何条目。
  Future<int> forgetMatching(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return Future<int>.value(0);
    return _forgetWhere(
      (MemoryEntry entry) => entry.text.toLowerCase().contains(needle),
    );
  }

  Future<int> _forgetWhere(bool Function(MemoryEntry entry) test) async {
    await load();
    final int before = _entries.length;
    _entries.removeWhere(test);
    final int deleted = before - _entries.length;
    if (deleted == 0) return 0;
    await _backend.save(_entries);
    _notify();
    return deleted;
  }

  /// 清空全部记忆。
  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    await _backend.save(_entries);
    _notify();
  }

  /// 监听记忆变更。返回撤销函数（幂等）。
  Disposer onChange(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  int _score(MemoryEntry entry, Set<String> queryTokens) {
    final Set<String> entryTokens =
        _tokenize('${entry.text} ${entry.tags.join(' ')}');
    return queryTokens.where(entryTokens.contains).length;
  }

  void _govern() {
    while (_entries.length > maxEntries) {
      int oldest = 0;
      for (int i = 1; i < _entries.length; i++) {
        if (_entries[i].createdAt.isBefore(_entries[oldest].createdAt)) {
          oldest = i;
        }
      }
      _entries.removeAt(oldest);
    }
  }

  static Set<String> _tokenize(String text) {
    final String lower = text.toLowerCase();
    final Set<String> tokens = <String>{
      for (final Match m in RegExp(r'[a-z0-9]+').allMatches(lower)) m.group(0)!,
    };
    for (final Match m in RegExp(r'[\u4e00-\u9fff]+').allMatches(lower)) {
      final String run = m.group(0)!;
      if (run.length == 1) {
        tokens.add(run);
        continue;
      }
      for (int i = 0; i + 2 <= run.length; i++) {
        tokens.add(run.substring(i, i + 2));
      }
    }
    return tokens;
  }

  String _nextId() {
    _seq++;
    return 'memory-${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }

  void _notify() {
    for (final void Function() listener
        in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

/// 将 [MemoryStore] 作为 `'memory'` 服务提供到上下文。
MemoryStore provideMemory(
  Context ctx, {
  MemoryStore? memory,
  MemoryBackend? backend,
}) {
  final MemoryStore resolved =
      memory ?? MemoryStore(backend: backend ?? InMemoryMemoryBackend());
  ctx.provide('memory', resolved);
  return resolved;
}

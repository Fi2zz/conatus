import 'dart:convert';
import 'dart:io';

import 'rag_backend.dart';
import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_snapshot.dart';
import 'rag_stats.dart';

/// JSON 文件索引后端：首次操作时整体读入内存视图，每次变更后整体原子落盘。
/// 文件损坏时抛 `rag_backend_broken`，不会静默清空索引。
class JsonRagBackend implements RagIndexBackend {
  JsonRagBackend({required File file}) : _file = file;

  final File _file;
  final InMemoryRagBackend _memory = InMemoryRagBackend();
  bool _loaded = false;

  @override
  Future<RagSnapshotMeta?> meta() async {
    await _ensureLoaded();
    return _memory.meta();
  }

  @override
  Future<void> init(RagSnapshotMeta meta) async {
    await _ensureLoaded();
    await _memory.init(meta);
    await _save();
  }

  @override
  Future<List<RagHit>> search(
    RagFilter filter, {
    required List<double> queryVector,
    required int k,
  }) async {
    await _ensureLoaded();
    return _memory.search(filter, queryVector: queryVector, k: k);
  }

  @override
  Future<void> upsert(List<RagChunk> chunks, List<List<double>> vectors) async {
    await _ensureLoaded();
    await _memory.upsert(chunks, vectors);
    await _save();
  }

  @override
  Future<int> delete(RagFilter filter) async {
    await _ensureLoaded();
    final int removed = await _memory.delete(filter);
    await _save();
    return removed;
  }

  @override
  Future<int> count() async {
    await _ensureLoaded();
    return _memory.count();
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    await _memory.clear();
    await _save();
  }

  @override
  Future<RagCursor?> cursorOf(String sourceId) async {
    await _ensureLoaded();
    return _memory.cursorOf(sourceId);
  }

  @override
  Future<void> saveCursor(RagCursor cursor) async {
    await _ensureLoaded();
    await _memory.saveCursor(cursor);
    await _save();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    if (await _file.exists()) {
      await _restore(_parse(await _file.readAsString()));
    }
    _loaded = true;
  }

  RagSnapshot _parse(String text) {
    try {
      return RagSnapshot.fromJson(jsonDecode(text) as Map<String, Object?>);
    } on Object {
      throw _broken();
    }
  }

  Future<void> _restore(RagSnapshot snapshot) async {
    final RagSnapshotMeta? meta = snapshot.meta;
    if (meta != null) {
      await _memory.init(meta);
    }
    try {
      await _memory.upsert(snapshot.chunks, snapshot.vectors);
    } on ArgumentError {
      throw _broken();
    }
    for (final RagCursor cursor in snapshot.cursors) {
      await _memory.saveCursor(cursor);
    }
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    final File temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(_memory.snapshot().toJson()),
      flush: true,
    );
    await temp.rename(_file.path);
  }

  RagException _broken() =>
      const RagException('rag_backend_broken', '索引文件损坏，需 rebuild()');
}

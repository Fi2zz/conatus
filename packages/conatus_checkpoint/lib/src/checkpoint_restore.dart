/// 归档式检查点恢复：目标检查点 = base 全量铺底 +（差量时）changed 覆盖 /
/// deleted 删除 + 删当前多余文件（rsync 语义）。
///
/// 由 [ArchiveCheckpointStore.restore] 调用；也可直接用于测试。
///
// REASON: base / 差量 / 旧目录树三种恢复共用同一套目标态与越界校验逻辑，
// 拆文件会把「先校验后写」的两遍式不变式割裂到多处。
library;

import 'dart:io';

import 'checkpoint_archive.dart';
import 'checkpoint_io.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_scan.dart';
import 'checkpoint_store_archive.dart';
import 'checkpoint_types.dart';

/// 把工作区恢复到 [turn] 轮的文件状态；返回恢复计数。
Future<CheckpointRestore> restoreArchiveCheckpoint(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
) async {
  final File archive = store.archiveFile(sessionId, turn);
  if (archive.existsSync()) {
    return _restoreArchive(store, sessionId, turn, archive);
  }
  return _restoreLegacy(store, sessionId, turn);
}

/// 新格式（单文件归档）恢复：清单走流式头部读取，条目流式产出、按条写盘
/// （内存 ≈ 最大单文件而非全归档）。
Future<CheckpointRestore> _restoreArchive(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
  File archive,
) async {
  final CheckpointManifest manifest = await readCheckpointManifest(archive);
  final Set<String> target;
  int restored;
  int removed = 0;
  if (manifest.isDelta) {
    final (Set<String> paths, int writes, int deletedCount) =
        await _restoreDelta(store, sessionId, archive, manifest);
    target = paths;
    restored = writes;
    removed = deletedCount;
  } else {
    final (Set<String> paths, int writes) = await _restoreBase(
      store,
      archive,
      manifest,
    );
    target = paths;
    restored = writes;
  }
  final int extras = await _deleteExtras(store, target);
  return CheckpointRestore(restored: restored, deleted: removed + extras);
}

/// base 恢复：先校验清单里的全部路径（fail-closed），再流式铺底。
/// 返回 (目标状态集, 写入文件数)。
Future<(Set<String>, int)> _restoreBase(
  ArchiveCheckpointStore store,
  File archive,
  CheckpointManifest manifest,
) async {
  final Set<String> target = <String>{
    for (final CheckpointFileEntry entry in manifest.files)
      if (_restorable(store, entry.path)) entry.path,
  };
  ensurePathsRestorable(store.root, target);
  int restored = 0;
  await for (final (String path, List<int> bytes) in readCheckpointEntries(
    archive,
  )) {
    if (!_restorable(store, path)) continue;
    await checkpointWriteBytes(store.root, path, bytes);
    restored++;
  }
  return (target, restored);
}

/// delta 恢复：base 铺底 + 差量覆盖 + deleted 删除；返回
/// (目标状态集给 `_deleteExtras` 清多余文件, 写入文件数, 被删文件数)。
/// 目标态里同一文件被 base 与 changed 各写一遍时计数也各计一遍。
Future<(Set<String>, int, int)> _restoreDelta(
  ArchiveCheckpointStore store,
  String sessionId,
  File archive,
  CheckpointManifest manifest,
) async {
  final CheckpointManifest base = await store.loadManifest(sessionId, 0);
  final Set<String> deleted = manifest.deleted.toSet();
  final Set<String> basePaths = <String>{
    for (final CheckpointFileEntry entry in base.files)
      if (_restorable(store, entry.path)) entry.path,
  };
  final Set<String> target = <String>{
    ...basePaths.where((String p) => !deleted.contains(p)),
    for (final String path in manifest.changed)
      if (_restorable(store, path)) path,
  };
  ensurePathsRestorable(store.root, <String>[...target, ...manifest.deleted]);
  int restored = 0;
  await for (final (String path, List<int> bytes) in readCheckpointEntries(
    store.archiveFile(sessionId, 0),
  )) {
    if (deleted.contains(path)) continue;
    if (!_restorable(store, path)) continue;
    await checkpointWriteBytes(store.root, path, bytes);
    restored++;
  }
  await for (final (String path, List<int> bytes) in readCheckpointEntries(
    archive,
  )) {
    if (!_restorable(store, path)) continue;
    await checkpointWriteBytes(store.root, path, bytes);
    restored++;
  }
  int removed = 0;
  for (final String path in manifest.deleted) {
    if (!_restorable(store, path)) continue;
    final File file = File('${store.root}${Platform.pathSeparator}$path');
    if (file.existsSync()) {
      file.deleteSync();
      removed++;
    }
  }
  return (target, restored, removed);
}

/// 旧版目录树检查点恢复（逐文件 gz/明文回退）。
// REASON: 旧格式分支与新格式路径共用同一套「写回 / 删除」判据（`_restorable`
// + `ensurePathsRestorable` + `_deleteExtras`）；拆函数就得把目标态集合与
// 计数器的传递契约复制一份，两条路径一旦漂移就会重现「按残缺清单删文件」。
Future<CheckpointRestore> _restoreLegacy(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
) async {
  final Directory? dir = store.legacyDir(sessionId, turn);
  if (dir == null) {
    throw CheckpointException(
      'missing-checkpoint',
      '检查点 $turn 不存在（会话 $sessionId）',
    );
  }
  final CheckpointManifest manifest = store.manifestOf(sessionId, turn);
  int restored = 0;
  int removed = 0;
  final Set<String> target;
  if (manifest.isDelta) {
    final CheckpointManifest base = store.manifestOf(sessionId, 0);
    final Directory? baseDir = store.legacyDir(sessionId, 0);
    final Set<String> deleted = manifest.deleted.toSet();
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in base.files)
        if (_restorable(store, entry.path)) entry.path,
    };
    target = <String>{
      ...basePaths.where((String p) => !deleted.contains(p)),
      for (final String path in manifest.changed)
        if (_restorable(store, path)) path,
    };
    ensurePathsRestorable(store.root, <String>[
      for (final CheckpointFileEntry entry in base.files)
        if (!deleted.contains(entry.path)) entry.path,
      ...manifest.changed,
      ...manifest.deleted,
    ]);
    if (baseDir != null) {
      for (final CheckpointFileEntry entry in base.files) {
        if (deleted.contains(entry.path)) continue;
        if (!_restorable(store, entry.path)) continue;
        await checkpointRestoreFromGz(baseDir.path, store.root, entry.path);
        restored++;
      }
    }
    for (final String path in manifest.changed) {
      if (!_restorable(store, path)) continue;
      await checkpointRestoreFromGz(dir.path, store.root, path);
      restored++;
    }
    for (final String path in manifest.deleted) {
      if (!_restorable(store, path)) continue;
      final File file = File('${store.root}${Platform.pathSeparator}$path');
      if (file.existsSync()) {
        file.deleteSync();
        removed++;
      }
    }
  } else {
    target = <String>{
      for (final CheckpointFileEntry entry in manifest.files)
        if (_restorable(store, entry.path)) entry.path,
    };
    ensurePathsRestorable(store.root, <String>[
      for (final CheckpointFileEntry entry in manifest.files) entry.path,
      ...manifest.deleted,
    ]);
    for (final CheckpointFileEntry entry in manifest.files) {
      if (!_restorable(store, entry.path)) continue;
      await checkpointRestoreFromGz(dir.path, store.root, entry.path);
      restored++;
    }
  }
  final int extras = await _deleteExtras(store, target);
  return CheckpointRestore(restored: restored, deleted: removed + extras);
}

/// 恢复清单里的路径是否允许写回：与采集 / 删除判定**同源**
/// （[checkpointExcluded]）。
///
/// 旧快照可能含策略后来才标为只读的目录、凭据、`build/` 等——采集侧已经
/// 排除，恢复侧若照写就会把它们重新创建出来（只读目录更会直接破坏策略
/// 约束）。写入与删除循环都逐条过滤，目标态同步剔除（`_deleteExtras` 自身
/// 也排除这些路径，不会误删）。
bool _restorable(ArchiveCheckpointStore store, String path) =>
    !checkpointExcluded(path, store.projectRel, store.policy);

/// 删除当前工作区中「不在目标状态、且未被排除」的文件；返回删除数。
///
/// 用 [checkpointWalk] 而非裸 `Directory.list`：嵌套版本库整棵跳过（它不在
/// 快照里，若当成「多余文件」删掉，恢复一次就抹掉一个 worktree）。
Future<int> _deleteExtras(
  ArchiveCheckpointStore store,
  Set<String> target,
) async {
  final List<File> extras = <File>[];
  await for (final FileSystemEntity entity in checkpointWalk(
    store.root,
    store.projectRel,
    store.policy,
  )) {
    if (target.contains(checkpointRelativeTo(entity, store.root))) continue;
    extras.add(entity as File);
  }
  for (final File file in extras) {
    // 防御性：walk 已排除链接，父链仍可能是。
    ensureRestorable(store.root, checkpointRelativeTo(file, store.root));
    file.deleteSync();
  }
  return extras.length;
}

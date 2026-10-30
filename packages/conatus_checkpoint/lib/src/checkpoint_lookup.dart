/// 归档检查点的「按轮次读内容」实现（两轮差异见 `checkpoint_turn_diff.dart`）。
///
/// 归档格式是 turn 0 全量 + 各轮相对 base 的差量，故「某轮某文件的内容」
/// = base 里的内容，被该轮差量覆盖时取差量——只读该轮归档会漏掉未变化的
/// 文件（`/diff` 的两侧都要有内容）。形态与 `checkpoint_restore.dart` 的
/// base 铺底 + 差量覆盖一致，只是产物留在内存而非写盘。
///
/// 只覆盖当前的单文件归档格式：旧版「每轮一个可读目录」的检查点仍能
/// `restore` / rewind，但按文件读取返回 `null`、差异比较只看集合差（内容
/// 无从读起）。旧格式只存在于升级过渡期，且 `keep` 很快会裁掉。
library;

import 'dart:io';

import 'checkpoint_archive.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_store_archive.dart';
import 'checkpoint_types.dart';

/// 读 [path] 在 [turn] 轮的内容；不在该轮 / 被排除 / 轮次不存在返回 `null`。
///
/// 读不出归档（索引说有、文件没了）同样返回 `null`——读取侧不该把「数据
/// 丢了」伪装成内容；`changesBetween` 才会显式报错。
Future<List<int>?> readArchiveFile(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
  String path,
) async {
  if (!checkpointReadablePath(path, store.projectRel, store.policy)) {
    return null;
  }
  if (!store.turnsOf(sessionId).contains(turn)) return null;
  try {
    final Map<String, List<int>> found = await readArchiveFiles(
      store,
      sessionId,
      turn,
      <String>{path},
    );
    return found[path];
  } on CheckpointException {
    return null;
  }
}

/// 批量读 [turn] 轮里若干路径的内容（base / 差量各只解压一遍）。
///
/// 归档缺失抛 [CheckpointException]（`missing-checkpoint`）：退回 base 内容
/// 会把「差量丢了」伪装成「文件没变」，diff 会给出错的结论。
Future<Map<String, List<int>>> readArchiveFiles(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
  Set<String> paths,
) async {
  final Map<String, List<int>> found = <String, List<int>>{};
  if (paths.isEmpty) return found;
  final File base = requireArchiveFile(store, sessionId, 0);
  if (turn == 0) {
    await _collect(base, paths, found);
    return found;
  }
  final CheckpointManifest delta = await store.loadManifest(sessionId, turn);
  await _collect(base, paths.difference(delta.deleted.toSet()), found);
  await _collect(requireArchiveFile(store, sessionId, turn), paths, found);
  return found;
}

/// 某轮的归档文件；缺失抛 `missing-checkpoint`。
File requireArchiveFile(
  ArchiveCheckpointStore store,
  String sessionId,
  int turn,
) {
  final File archive = store.archiveFile(sessionId, turn);
  if (archive.existsSync()) return archive;
  throw CheckpointException(
    'missing-checkpoint',
    '检查点 $turn 的归档缺失（会话 $sessionId）',
  );
}

/// 从 [archive] 里挑出 [wanted] 的条目写进 [found]（后者覆盖前者）。
Future<void> _collect(
  File archive,
  Set<String> wanted,
  Map<String, List<int>> found,
) async {
  if (wanted.isEmpty) return;
  await for (final (String path, List<int> bytes) in readCheckpointEntries(
    archive,
  )) {
    if (wanted.contains(path)) found[path] = bytes;
  }
}

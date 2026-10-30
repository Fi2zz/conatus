/// 两种存储实现共用的工作区遍历：决定「哪些文件进快照」。
///
/// 单独成文件是为了让 [ArchiveCheckpointStore] 与 [GitShadowStore] 的排除
/// 判定**逐字节一致**。这不是洁癖：影子实现一度用 `git add --all`，git 会
/// 顺从工作区的 `.gitignore`（Swift 项目的 `.build/`、前端项目的
/// `dist/` 都在里面），而归档实现只认 [kCheckpointDefaultIgnores] + 策略
/// 里的 ignore。两者排除面不一致的后果是实打实的：影子快照只收了 293 个
/// 文件，而恢复按 rsync 语义删掉了其余 9119 个。
///
/// 结论：**排除判定必须由我们自己算，不能委托给 git**。影子实现改为把
/// 自己 walk 出来的路径显式喂给 `git add -f`（`-f` 覆盖 ignore 规则；既然
/// 只传我们想要的，结果就等于自定义排除面）。
///
/// 遍历是**手写队列**而非 `list(recursive: true)`：需要在下降到某个目录前
/// 先看它是不是嵌套版本库（目录里有 `.git`），是则整棵子树剪掉——
/// `Directory.list` 没法在递归下降时剪枝。
library;

import 'dart:io';

import 'checkpoint_io.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_policy.dart';

/// 遍历 [root] 下需进快照的文件。
///
/// [extra] 是额外的排除集（全局 gitignore 的解析结果，见
/// `global_git_ignore.dart`）。它同时作用于采集与删除判定——两者必须同源。
///
/// 剪掉两类子树：
/// - 含 `.git` 的目录（嵌套版本库 / `git worktree` 检出）——git 收不了它们
///   内部的文件（`git add` 对嵌套仓库内的显式路径**静默跳过**，rc=0 无告警），
///   收了也不一致；恢复侧同样要跳过，否则整棵子树会被 rsync 删掉。
/// - 命中 [kCheckpointDefaultIgnores] / `projectDir` / 策略前缀的目录。
///
/// 跳过符号链接：恢复侧对等处理（`ensureRestorable` 做越界校验），快照侧
/// 不收，两边才对得上。
Stream<FileSystemEntity> checkpointWalk(
  String root,
  String projectRel,
  CheckpointPolicy policy, [
  Set<String> extra = const <String>{},
]) async* {
  final List<Directory> queue = <Directory>[Directory(root)];
  while (queue.isNotEmpty) {
    final Directory dir = queue.removeAt(0);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // 读不动（权限 / 并发删除）的目录跳过，不中断整轮
    }
    for (final FileSystemEntity entry in entries) {
      if (entry is Directory) {
        if (_prune(entry, root, projectRel, policy, extra)) continue;
        queue.add(entry);
        continue;
      }
      if (entry is! File) continue;
      if (!_excluded(
        checkpointRelativeTo(entry, root),
        projectRel,
        policy,
        extra,
      )) {
        yield entry;
      }
    }
  }
}

/// 该目录是否应整棵剪掉（嵌套版本库 / 命中排除前缀）。
bool _prune(
  Directory dir,
  String root,
  String projectRel,
  CheckpointPolicy policy,
  Set<String> extra,
) {
  // 嵌套版本库：目录里存在 `.git`（目录或 worktree 的 gitfile 都算）。
  if (FileSystemEntity.typeSync(
        '${dir.path}${Platform.pathSeparator}$kCheckpointVcsDir',
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound) {
    return true;
  }
  final String rel = checkpointRelativeTo(dir, root);
  return rel.isEmpty || _excluded(rel, projectRel, policy, extra);
}

/// 排除判定（内置规则 + 额外集）。删除侧走同一条路径，保证同源。
bool _excluded(
  String rel,
  String projectRel,
  CheckpointPolicy policy,
  Set<String> extra,
) =>
    checkpointExcluded(rel, projectRel, policy, extra: extra);

/// 单个实体是否进快照（是文件 + 未命中排除）。
///
/// 注意：这只判**路径级**排除；嵌套版本库的子树剪枝在 [_prune] 里做，
/// 单文件调用方需自行保证不落在嵌套仓库内。
bool checkpointIncluded(
  FileSystemEntity entity,
  String root,
  String projectRel,
  CheckpointPolicy policy, [
  Set<String> extra = const <String>{},
]) {
  if (entity is! File) return false;
  return !_excluded(
    checkpointRelativeTo(entity, root),
    projectRel,
    policy,
    extra,
  );
}

/// [rel] 是否落在某个嵌套版本库内（`a/.git/b` 形态）。
///
/// 删除判定（`_deleteExtras`）必须用它：剪枝只作用于遍历，恢复侧的删除
/// 是独立的一次全量 walk，撞上嵌套仓库会把它整棵删掉。
bool insideNestedRepo(String rel) =>
    rel.split(Platform.pathSeparator).contains(kCheckpointVcsDir);

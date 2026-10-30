/// conatus 的工作区检查点内核：每轮快照、rsync 式恢复、按轮差异读取与
/// 检查点时间线编排。
///
/// 包内只含通用能力：排除面与只读前缀由 [CheckpointPolicy] 注入，不含任何
/// 产品目录；undo/redo 与 TUI 命令留在消费方。
///
/// * 归档后端 [ArchiveCheckpointStore]：自研 gzip 归档，零外部依赖。
/// * 影子 git 后端 [GitShadowStore]：把工作区提交进独立 git dir，内容寻址
///   与增量交给 git；装配工厂 [openCheckpointStore] 按选项/环境选实现。
/// * 编排 [CheckpointManager]：轮次计数、串行链、绑定/解绑与 `/rewind`。
/// * 恢复 [restoreArchiveCheckpoint]：base 铺底 + 差量覆盖 + 删多余（rsync）。
/// * `/diff` 数据源 [DiffSource] / [WorkingDiff]：工作区 git 差异与按轮
///   检查点差异；排除面复用检查点策略（[CheckpointManager.showsDiffPath]）。
library;

export 'src/checkpoint_archive.dart'
    show
        CheckpointArchiveEntry,
        CheckpointArchiveWriter,
        checkpointArchiveName,
        kCheckpointArchiveTempSuffix,
        readCheckpointArchive,
        readCheckpointEntries,
        readCheckpointManifest,
        writeCheckpointArchive;
export 'src/checkpoint_backend.dart' show openCheckpointStore;
export 'src/checkpoint_changes.dart' show CheckpointFileChange;
export 'src/checkpoint_hashes.dart'
    show
        checkpointHashesFile,
        deleteCheckpointHashes,
        readCheckpointHashes,
        writeCheckpointHashes;
export 'src/checkpoint_io.dart'
    show
        checkpointPathSegments,
        checkpointReadGz,
        checkpointRelativeTo,
        checkpointRestoreFromGz,
        checkpointWriteBytes,
        checkpointWriteGz,
        ensurePathsRestorable,
        ensureRestorable;
export 'src/checkpoint_lookup.dart' show readArchiveFile, readArchiveFiles;
export 'src/checkpoint_manager.dart' show CheckpointManager;
export 'src/checkpoint_options.dart' show CheckpointBackend, CheckpointOptions;
export 'src/checkpoint_paths.dart'
    show
        checkpointExcluded,
        checkpointReadOnlyPath,
        checkpointReadablePath,
        checkpointSensitive,
        kCheckpointDefaultIgnores,
        kCheckpointVcsDir;
export 'src/checkpoint_policy.dart' show CheckpointPolicy;
export 'src/checkpoint_restore.dart' show restoreArchiveCheckpoint;
export 'src/checkpoint_scan.dart'
    show checkpointIncluded, checkpointWalk, insideNestedRepo;
export 'src/checkpoint_store.dart'
    show CheckpointPathVisibility, CheckpointStore;
export 'src/checkpoint_store_archive.dart' show ArchiveCheckpointStore;
export 'src/checkpoint_store_git.dart' show GitShadowStore;
export 'src/checkpoint_types.dart'
    show
        CheckpointException,
        CheckpointFileEntry,
        CheckpointInfo,
        CheckpointManifest,
        CheckpointRestore,
        CheckpointRewindResult;
export 'src/diff_source.dart' show DiffSource, kDiffNoTurnNotice;
export 'src/global_git_ignore.dart' show resolveGlobalGitIgnore;
export 'src/shadow_git_runner.dart'
    show GitResult, GitRunner, ProcessGitRunner, UnavailableGitRunner;
export 'src/working_diff.dart' show WorkingDiff;

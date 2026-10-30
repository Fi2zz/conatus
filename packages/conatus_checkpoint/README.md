# conatus_checkpoint

conatus 的**工作区检查点内核**：每轮工作区快照、rsync 式恢复、按轮差异读取与
检查点时间线编排。纯 Dart，只依赖 `conatus_diff` / `conatus_foundation` /
`crypto`。

> ⚠️ **实验性**：API 可能在没有 major 版本变更的情况下破坏性调整，勿在生产依赖。

从 nava（`packages/conatus_code`）的检查点实现迁出：磁盘布局、归档容器格式、
影子 git 索引、恢复语义与旧目录树兼容全部保持不变；产品策略（只读目录、应用
数据目录）改为经 `CheckpointPolicy` 注入，包内不含任何产品目录名。

## 安装

```yaml
dependencies:
  conatus_checkpoint:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: master
      path: packages/conatus_checkpoint
```

生产使用请把 `ref` pin 到包含 `packages/conatus_checkpoint` 的具体 commit SHA
或 tag。或经伞包 `import 'package:conatus/conatus.dart';` 一并导出。

## 快速开始

```dart
import 'package:conatus_checkpoint/conatus_checkpoint.dart';

final CheckpointManager manager = CheckpointManager(
  store: ArchiveCheckpointStore(
    root: '/path/to/workspace',
    projectDir: '/path/to/workspace/.app-data',
    policy: const CheckpointPolicy(
      readOnlyPrefixes: <String>['.app'],
      excludedPrefixes: <String>['dist'],
    ),
  ),
  options: const CheckpointOptions(keep: 5),
);

await manager.bind('session-id');   // 接管已有时间线，无历史时写 turn 0
await manager.recordTurn();         // 每轮收口后拍差量
await manager.rewind(1);            // 工作区回到上一轮
```

## API 速查

| 成员 | 说明 |
|------|------|
| `CheckpointManager({required CheckpointStore store, required CheckpointOptions options})` | 时间线编排：`bind` / `reset` / `detach` / `recordTurn` / `rewind` / `restoreTo` / `clearSession` / `flush` |
| `CheckpointOptions({enabled, keep, backend, policy})` | 装配选项：启用开关、保留点数、后端选择、排除策略 |
| `CheckpointPolicy({ignore, excludedPrefixes, readOnlyPrefixes})` | 排除面：额外 ignore 前缀、整树排除前缀、只读前缀（顶层、大小写不敏感） |
| `CheckpointBackend { auto, git, archive }` | 后端选择（影子 git 后端由后续版本提供） |
| `ArchiveCheckpointStore({root, projectDir, keep, policy})` | 自研 gzip 归档后端 |
| `CheckpointStore` | 存储接口：`snapshot` / `restore` / `readFile(s)` / `changesBetween` / `list` / `prune` |
| `CheckpointManifest` / `CheckpointFileEntry` / `CheckpointInfo` | 清单与摘要类型（base 全量 / delta 差量） |
| `CheckpointRestore` / `CheckpointRewindResult` | 恢复计数与回滚结果（含对话切点 `lastEventId`） |
| `CheckpointFileChange` | 两轮之间的 `added` / `modified` / `deleted` / `renamed` |
| `checkpointExcluded(rel, projectRel, policy, {extra})` | 排除判定（采集 / 恢复 / `/diff` 共用的单一事实来源） |
| `checkpointReadablePath(rel, projectRel, policy)` | 路径能否作为按文件读取的目标 |
| `checkpointReadOnlyPath(rel, readOnlyPrefixes)` | 是否落在只读前缀下 |
| `checkpointWalk(root, projectRel, policy, [extra])` | 需进快照的文件遍历（剪嵌套版本库 / 排除前缀） |
| `checkpointIncluded(entity, root, projectRel, policy, [extra])` | 单个实体是否进快照 |
| `restoreArchiveCheckpoint(store, sessionId, turn)` | 归档恢复（也可直接用于测试） |
| `readArchiveFile` / `readArchiveFiles` | 按轮读内容（base 铺底 + 差量覆盖） |

## 磁盘布局与语义

- `<projectDir>/checkpoints/<sessionId>/<sha256前16位>`：单个 gzip 归档
  （清单头 + 条目帧），文件名不可读、不暴露轮次；`index` 记录 turn → 文件数。
- turn 0 全量 base，其余轮次为相对 base 的差量；base 永不裁剪。
- 恢复是 **rsync 语义**：目标态有的覆盖/补回，当前有而目标态没有的删除；
  恢复前先做符号链接越界校验（fail-closed），越界时一个文件都不动。
- 凭据文件（`id_rsa`、`.env`、证书等）与嵌套版本库（含 `.git` 的目录）既不
  进快照，也不会在恢复时被当成多余文件删掉。
- 旧版「每轮一个可读目录」的检查点仍可读、可恢复。

## 不在本包范围

- undo/redo 的 `RevertService`（依赖会话存储，留在消费方）。
- TUI 命令（`/rewind`、`/diff`）与产品配置解析。
- 产品目录策略：只读 / 排除前缀一律由 `CheckpointPolicy` 注入。

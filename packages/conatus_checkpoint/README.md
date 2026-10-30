# conatus_checkpoint

conatus 的**工作区检查点内核**：每轮工作区快照、rsync 式恢复、按轮差异读取与
检查点时间线编排。纯 Dart，只依赖 `conatus_diff` / `conatus_foundation` /
`crypto`。两种存储后端：

- **归档**（`ArchiveCheckpointStore`）：自研 gzip 归档容器，零外部依赖，任何环境可跑。
- **影子 git**（`GitShadowStore`）：把工作区提交进独立 git dir，内容寻址与增量交给
  git；需要 git 二进制，快且跨会话复用对象。

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

// 按后端选择 + 环境探测造存储：auto 有 git 走影子仓库，否则退回归档。
// 一份 options 同时喂给工厂与管理器（管理器只读 enabled，其余字段供工厂用）。
const CheckpointOptions options = CheckpointOptions(
  keep: 5,
  backend: CheckpointBackend.auto,
  policy: CheckpointPolicy(
    readOnlyPrefixes: <String>['.app'],
    excludedPrefixes: <String>['dist'],
  ),
);

final CheckpointStore store = await openCheckpointStore(
  options: options,
  root: '/path/to/workspace',
  projectDir: '/path/to/workspace/.app-data',
);

final CheckpointManager manager = CheckpointManager(
  store: store,
  options: options,
);

await manager.bind('session-id');   // 接管已有时间线，无历史时写 turn 0
await manager.recordTurn();         // 每轮收口后拍差量
await manager.rewind(1);            // 工作区回到上一轮
```

需要固定后端时直接构造实现（`ArchiveCheckpointStore` 或 `GitShadowStore`），
参数相同：`root` / `projectDir` / `keep` / `policy`。

## API 速查

| 成员 | 说明 |
|------|------|
| `CheckpointManager({required CheckpointStore store, required CheckpointOptions options})` | 时间线编排：`bind` / `reset` / `detach` / `recordTurn` / `rewind` / `restoreTo` / `clearSession` / `flush` |
| `CheckpointOptions({enabled, keep, backend, policy})` | 装配选项：启用开关、保留点数、后端选择、排除策略 |
| `CheckpointPolicy({ignore, excludedPrefixes, readOnlyPrefixes})` | 排除面：额外 ignore 前缀、整树排除前缀、只读前缀（顶层、大小写不敏感） |
| `CheckpointBackend { auto, git, archive }` | 后端选择：`auto` 有 git 走影子仓库、否则归档；`git` / `archive` 显式指定且不降级 |
| `openCheckpointStore({options, root, projectDir, git})` | 装配工厂：按 options 造存储，并顺带收紧旧检查点目录权限 |
| `ArchiveCheckpointStore({root, projectDir, keep, policy})` | 自研 gzip 归档后端 |
| `GitShadowStore({root, projectDir, keep, policy, git})` | 影子 git 后端（独立 git dir，复用对象；无 git 时报错） |
| `GitRunner` / `ProcessGitRunner` / `UnavailableGitRunner` / `GitResult` | 影子仓库的 git 执行缝（可注入 fake / 禁用） |
| `resolveGlobalGitIgnore({git, gitDir, workTree, candidates})` | 只按全局 `core.excludesFile` 求额外排除集；解析失败 fail-closed |
| `CheckpointStore` | 存储接口：`snapshot` / `restore` / `readFile(s)` / `changesBetween` / `list` / `prune`（含 `policy`） |
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
| `DiffSource({workdir, checkpoint, sessionId, turn})` | `/diff` 数据源：工作区 git 差异或指定轮次的检查点差异 |
| `WorkingDiff(workdir, {acceptsPath})` | 工作区未提交差异（含未跟踪文件） |
| `kDiffNoTurnNotice` | 该轮没有检查点时的固定提示文案 |

## 磁盘布局与语义

两种后端共用 `<projectDir>/checkpoints/` 根目录，互不覆盖：

- **归档**：`<projectDir>/checkpoints/<sessionId>/<sha256前16位>` 是单个 gzip
  归档（清单头 + 条目帧），文件名不可读、不暴露轮次；`index` 记录 turn → 文件数。
  turn 0 全量 base，其余轮次为相对 base 的差量；base 永不裁剪。
- **影子 git**：`<projectDir>/checkpoints/shadow.git` 是独立仓库，每会话一个
  gzip JSON 索引 `checkpoints/shadow-index/<sessionId>`（轮次 → 提交 sha）；轮次
  即提交，内容寻址与增量由 git 提供，对象跨会话复用。用户自己的仓库完全不受
  影响（影子提交不进用户历史），工作区也不必是 git 仓库。
- 恢复是 **rsync 语义**：目标态有的覆盖/补回，当前有而目标态没有的删除；
  恢复前先做符号链接越界校验（fail-closed），越界时一个文件都不动。
- 影子 git 会按全局 `core.excludesFile`（机器级忽略）额外排除，但**不采纳**
  工作区 `.gitignore`：构建产物恰恰最需要可回滚；解析失败按失败处理，不返回
  残缺排除集。
- 凭据文件（`id_rsa`、`.env`、证书等）与嵌套版本库（含 `.git` 的目录）既不
  进快照，也不会在恢复时被当成多余文件删掉。
- 只读前缀（`policy.readOnlyPrefixes`）既不进快照，也不被恢复写回：按文件读取
  返回 `null`；含只读路径的旧快照在恢复时**整体拒绝**（fail-closed，一个文件都
  不动）。
- 旧版「每轮一个可读目录」的检查点仍可读、可恢复；两种后端可并存，同一 session
  的索引互不覆盖。

## 不在本包范围

- undo/redo 的 `RevertService`（依赖会话存储，留在消费方）。
- TUI 命令（`/rewind`、`/diff`）与产品配置解析。
- 产品目录策略：只读 / 排除前缀一律由 `CheckpointPolicy` 注入。

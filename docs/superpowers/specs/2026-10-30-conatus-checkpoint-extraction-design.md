# conatus_checkpoint 提取设计

日期：2026-10-30
状态：待实施
范围：父仓 `packages/conatus_checkpoint`；子模块 `packages/conatus_code`

## 背景

`conatus_code` 的工作区检查点（每轮快照 + `/rewind`）、检查点差异数据源与
undo/redo 编排目前只服务 nava。桌面端（`products/conatus_work`）同样需要
“改坏了能回到上一轮”的能力，直接依赖 `conatus_code` 会拖入 TUI / SQLite /
nocterm。

本设计把检查点内核提取为独立包；nava 保留 TUI 命令、`.opencode` 排除策略与
配置解析。undo/redo 的 `RevertService` 本轮留在 nava（它依赖 `SessionStore`，
可与本包分阶段迁移），不在本计划范围内。

## 目标

- 新增 `conatus_checkpoint`：工作区快照存储（归档 + 影子 git）、每会话时间线、
  rsync 式恢复、按轮差异读取、工作区 git diff 数据源。
- 包内不出现 `.opencode` / `.nava` / nava 配置类型；排除面与只读前缀由
  `CheckpointPolicy` 注入。
- 磁盘格式与语义完全不变：`<projectDir>/checkpoints/<sessionId>/<sha256>`、
  `shadow.git`、`index`、旧目录树兼容、rsync 恢复、符号链接 fail-closed。
- nava 通过 `lib/diff.dart` / `lib/conatus_code.dart` 保持公共符号兼容。

## 非目标

- 不迁移 `src/revert/`（undo/redo）到本包；nava 改为从新包导入
  `CheckpointManager` 即可。
- 不迁移 TUI（`tui_diff_*`、`/rewind`、`/diff` 命令）。
- 不改变 checkpoint 的磁盘布局、保留策略、恢复语义或错误码。
- 不改 `.opencode` / `.config/opencode` 的产品策略。

## 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 包边界 | `conatus_checkpoint` 只含 checkpoint + diff 数据源 | undo/redo 依赖 Session，后移可降低首轮风险 |
| 配置类型 | 包内 `CheckpointOptions` / `CheckpointPolicy`；nava 做映射 | 不把 nava `config_schema.dart` 带进框架 |
| 排除策略 | 通用默认 `build` / `.dart_tool` / `node_modules`；`.opencode` / `.config/opencode` 由 policy 注入 | 产品策略留在产品 |
| 只读前缀 | `CheckpointPolicy.readOnlyPrefixes`，顶层、大小写不敏感 | 与旧 `checkpointReadOnlyPath` 行为一致，但不再硬编码 |
| FS 接缝 | v1 只支持本地工作区，`dart:io` 直连；文档明确 | 恢复是应用级维护操作，与 session 持久化同信任域 |
| 依赖 | `conatus_diff`、`conatus_foundation`、`crypto` | 纯 Dart；不依赖 agent / core |
| 大文件 | `checkpoint_paths` / `checkpoint_restore` / `checkpoint_archive` 按职责拆分；store 后端保留单一协议实现并加 `// REASON` | 满足 200 行约束，同时不把私有状态拆散 |
| 兼容入口 | `conatus_code/lib/diff.dart` 继续导出 `DiffSource`；`conatus_code.dart` 继续导出 checkpoint 符号 | 现有 TUI / 测试 import 不必全改 |

## 兼容性

- 工具/命令行为不变：`/rewind`、`/diff turn`、undo/redo 的 checkpoint 部分。
- `CheckpointManager` 构造从 `CheckpointConfig` 改为 `CheckpointOptions`；仅
  nava 装配点与测试需要改。
- `CheckpointStore` 增加 `policy` getter；`ignore` 字段语义保留在 policy 内。
- 磁盘路径、归档容器、影子 git 索引格式不变；提供一个现有归档 fixture 的读取测试。

## 风险

- 26 个 checkpoint 文件 + 13 个测试迁移，删除/重命名面大。
- `checkpoint_store_git` / `store_archive` 分别 594 / 487 行，拆分成本高；先以
  `// REASON` 保留，后续单独重构。
- nava 的 `/rewind` 与 TUI 命令测试依赖 `CheckpointManager`；迁移后必须跑完整
  `conatus_code` 测试（已知 2 条 TUI 既有失败）。
- 两仓顺序：父仓包先落地，子模块 pin ref 后再删副本。

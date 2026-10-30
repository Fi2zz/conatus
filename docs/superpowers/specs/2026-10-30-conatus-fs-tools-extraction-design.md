# conatus_fs_tools 提取设计

日期：2026-10-30
状态：待实施
范围：父仓 `packages/conatus_diff`、`packages/conatus_fs_tools`、`packages/conatus_foundation`；
子模块 `packages/conatus_code`；桌面端消费方

## 背景

`conatus_code` 的文件工具（read / write / edit / glob / grep / list / apply_patch）
此前只服务 nava 一个消费者，因此随 `conatus_tui` / `conatus_coding` 一起并入子模块
是合理的。现在出现第二个消费者：`products/conatus_work`（类似 WorkBuddy 的桌面端
产品层）。桌面端直接依赖 `conatus_code` 会把 TUI / nocterm / sqlite3 / toml /
command_shield 一并拖进依赖闭包，代价不可接受。

按仓库的 products/ 判据：产品只 `import package:conatus/conatus.dart`，不直接依赖
单个模块包，也不进伞包 re-export。因此 `conatus_fs_tools` 必须进伞包导出，桌面端才能
通过 umbrella 使用它。

本设计把可复用的文件工具与纯 diff 内核提取到父仓，产品策略（`.nava`、`.opencode`、
fs jail、审批、TUI）留在子模块。

## 目标

- 新增 `conatus_diff`：零依赖的统一 diff 生成 / 解析 / 应用内核。
- 新增 `conatus_fs_tools`：文件工具与 `provideFsTools` 装配，只依赖
  `conatus_core`、`conatus_diff`、`conatus_foundation`、`glob`。
- `ReadOnlyPathGuard` 与通用路径助手进 `conatus_foundation`；`.opencode` 策略留在
  nava。
- `ToolResultEviction` 类进 `conatus_foundation`；`provideToolResultEviction` 装配
  仍留在 `conatus_agent`。
- nava 保留 `.nava` 溢出目录、`.opencode` 保护根、fs jail、审批、TUI、story。
- 桌面端作为 `products/conatus_work` 成员，只依赖伞包 `conatus`（不直接依赖
  `conatus_code` 或单个模块包）；`conatus_fs_tools` 通过伞包导出对它可见。

## 非目标

- 不提取 `src/project/`（SQLite 项目注册表、`NAVA_HOME`、`workspace.json`）。
- 不提取 `src/checkpoint/`、`src/revert/`。它们是后续独立计划，`conatus_diff` 只为
  它们铺路。
- 不提取 TUI（`nocterm`）、LSP、story、XERJ、命令策略、审批接线。
- 不改变工具名、参数名、默认值；nava 的用户可见行为必须保持不变。

## 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 工具包位置 | 新建 `conatus_fs_tools`，标实验性，并进伞包导出 | 第二消费者证明它不是 nava 私有；放 foundation 会因 `glob` / 工具层职责造成分层污染；产品层只能 import 伞包 |
| 产品消费方式 | `products/conatus_work` 只依赖伞包 `conatus` | 仓库的 products/ 判据：产品不进伞包、不直接依赖模块包；新能力靠伞包导出到达产品 |
| 纯 diff 位置 | 新建 `conatus_diff`，零依赖 | `fs_tools` 的 write/edit 与 `checkpoint` 的 diff 数据源共用；避免两边各复制一份 |
| 只读闸门 | `ReadOnlyPathGuard` + `normalizeReadOnlyPath` / `underReadOnlyRoot` / `realPathViaAncestor` 进 foundation | 它是通用的 `FileSystem` 装饰器；具体保护根是宿主策略 |
| 结果驱逐 | `ToolResultEviction` 类进 foundation；provider 留 agent | 工具包只需要类，不需要 Agent Loop；避免 `fs_tools → agent` 的倒挂依赖 |
| ripgrep 执行 | 新增 `RipgrepRunner` 接缝：`ShellRipgrepRunner` + `ProcessRipgrepRunner` | `ShellExecutor` 只收命令字符串，Windows `cmd /c` 下 POSIX 引号必坏；桌面端可注入本地进程 runner |
| 默认工具集 | read/write/edit/list/glob 默认开；apply_patch 默认关 | `apply_patch` 是高风险工具，由宿主显式开启 |
| 兼容入口 | `conatus_code/lib/fs_tools.dart` 改为 re-export | nava 内部与旧测试的 import 不必一次性全改；也方便回滚 |
| 包版本 | 新包 `version: 0.16.0`、`publish_to: none`、`resolution: workspace` | 与全仓冻结版本一致，`tool/version.sh` 才能通过 |
| 依赖闭包 | `conatus_diff` 零依赖；`conatus_fs_tools` 只加 `glob` | 父项目对新增依赖谨慎；`glob` 已是纯 Dart 且 nava 现有依赖 |

## 边界

### 进父仓

- `conatus_diff`：`diff_types` / `diff_model` / `diff_paths` / `diff_builder` /
  `diff_parser` / `unified_diff` / `line_ops` / `apply`。
- `conatus_fs_tools`：`read` / `write` / `edit` / `list` / `glob` / `grep` /
  `apply_patch`、`buildApprovalPreview`、`RipgrepBinary` / `RipgrepRunner`、
  `provideFsTools` + `FsToolOptions`。
- `conatus_foundation`：`ReadOnlyPathGuard`、通用路径助手、`ToolResultEviction` 类。

### 留 `conatus_code`

- `src/read_only_policy.dart`：`.opencode` / `~/.config/opencode` 的根、文案、相对
  路径判定、写前检查。
- `src/tool_result_spill.dart`：`.nava/tool-results` 位置。
- `src/diff/diff_source.dart`：检查点数据源（依赖 `CheckpointManager`）。
- `src/diff/tui_*`：`nocterm` 视图。
- `src/tui/`、`src/tools/code_tools.dart` 的 git/run 工具、审批、fs jail、story。

## 兼容性

- 工具名与参数不变：`read` / `write` / `edit` / `list` / `glob` / `grep` /
  `apply_patch`。
- `conatus_code/lib/fs_tools.dart` 继续导出工具与 `provideFsTools`；新增
  `FsToolOptions`，旧调用点改为 `options:` 形式。
- `provideFsTools` 默认新增 `list`（低风险、原由 `provideCodeTools` 注册）；
  `apply_patch` 改为显式 `enablePatch: true`，nava 在 `tui_app` 开启。
- 磁盘上没有需要迁移的数据；本计划不触碰 checkpoint 格式。

## 风险

- 两个消费者共享 API 后，参数/默认值变更需要按 tag 管理；新包先标实验性。
- 父项目的 200 行/150 行类约束要求拆分 `read_file` 等文件；拆分不能改变行为。
- 两仓同步窗口：父仓先合入，子模块再 pin ref、删副本、重建二进制。
- `ProcessRipgrepRunner` 绕过 `'shell'` 接缝，只适用于本地进程；远程沙箱必须注入
  自己的 runner。

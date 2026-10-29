# 方案：工具标识与权限动作统一为 OpenCode 命名

> 日期：2026-10-29 · 状态：待评审
>
> 范围：`packages/conatus_code`（nava）为主，连带 `conatus_agent` /
> `conatus_search` / `conatus_tasks` / `conatus_harness` / `conatus_skill` /
> `conatus_foundation` 的公开工具标识与权限动作名。
>
> 参考：OpenCode 官方 Tools / Permissions 文档（`bash`、`edit`、`write`、`read`、
> `grep`、`glob`、`apply_patch`、`task`、`todowrite`、`webfetch`、`websearch`、
> `question`、`skill`；权限键 `bash` / `edit` / `task` 等），以及
> `packages/conatus_code/lib/src/agents/agent_open_code.dart` 现有映射。

## 1. 背景与目标

nava 的工具标识自成一套：OpenCode 里叫 `bash`，nava 叫 `run_command`；叫 `edit`，
nava 叫 `edit_file`。同一个动作在对话上屏、Agent `tools` 白名单、`[[permissions]]`
里出现三种不同的名字，用户需要记两套词汇；权限配置按 OpenCode 习惯写
`action = "bash"` 也不会命中（nava 要求 `shell`）。

目标：**把 nava 的工具标识与权限动作名统一成 OpenCode 的名字**，让
「模型看到的工具名 / 上屏显示 / Agent 白名单 / 权限规则」四处使用同一套词汇。

### 成功标准

- 上屏、工具 schema、日志里只出现 OpenCode 工具名；不再出现 `run_command` /
  `edit_file` / `web_search` 等旧标识。
- `[[permissions]]` 用 `action = "bash"`、`action = "task"` 即可命中对应工具；
  `nava import opencode` 导出的配置直接就是这套动作名。
- Agent frontmatter 里写 OpenCode 工具名（`bash` / `read` / `edit` / `task` …）
  无需任何转换即生效。
- `dart analyze --fatal-infos` 干净；受影响包测试与根集成测试全绿；
  重建 `dist/nava` 可用。

### 非目标

- 不改工具实现、参数 schema、风险等级与审批语义。
- 不改包名、文件名、类名（`RunCommandTool`、`read_file.dart` 保持）与服务键
  （`'shell'`、`'fs'`、`'tools'`）。
- 不改 ripgrep 可执行文件名 `rg`、RipgrepBinary 相关逻辑。
- 不保留旧名的兼容别名（见决策记录）。
- 不重写 `docs/superpowers/specs|plans` 下的历史文档。

## 2. 决策记录

| 决策点 | 结论 | 理由 |
|---|---|---|
| 改动范围 | **全仓库统一**，公共包的 `Tool.name` 一起改 | 只有一处权威命名，才能让「显示 / 白名单 / 权限」自然一致；分两层会继续漂移 |
| 旧名兼容 | **不留别名，一次性切换** | 当前只有内部 dogfood，长痛不如短痛；双注册会让模型看到两份工具 |
| OpenCode 无对应物的工具 | 保持原名 | `run_tests` / `run_code` / `git_*` / 后台任务 / LSP / XERJ / memory 工具没有 OpenCode 同类物，自创名字只会增加认知负担 |
| `apply_patch` | 保持 `apply_patch` | 与 OpenCode 现行工具名一致（旧称 `patch` 已被替代） |
| 权限动作 | `shell` → `bash`，`subagent` → `task` | 直接采用 OpenCode permission key；其余键本就同名 |
| 文件 / 类 / 服务键 | 不改 | 改名只发生在标识层，避免无意义的文件大挪移与 import 破坏 |

## 3. 命名映射

### 3.1 工具名

| nava 现名 | 新名 | 归属 |
|---|---|---|
| `read_file` | `read` | conatus_code |
| `write_file` | `write` | conatus_code |
| `edit_file` | `edit` | conatus_code |
| `apply_patch` | `apply_patch`（不变） | conatus_code |
| `list_files` | `list` | conatus_code |
| `run_command` | `bash` | conatus_code |
| `rg` | `grep` | conatus_code |
| `glob` | `glob`（不变） | conatus_code |
| `web_search` | `websearch` | conatus_search |
| `fetch_url` | `webfetch` | conatus_search |
| `spawn_agent` | `task` | conatus_agent |
| `ask_user` | `question` | conatus_code TUI |
| `update_plan` | `todowrite` | conatus_code |
| `skill` | `skill`（不变） | conatus_skill |

保持原名：`run_tests`、`run_code`、`run_command_background`、
`list_background_tasks`、`background_output`、`background_kill`、`git_status`、
`git_diff`、`git_add`、`git_commit`、`git_branch`、`git_stash`、
`list_tasks`、`cancel_task`、`lsp_diagnostics`、`lsp_hover`、`lsp_definition`、
`lsp_references`、`lsp_document_symbols`、`code_search`、`find_definition`、
`index_project`、`remember`、`forget`、`list_mcp_resources`、`read_mcp_resource`。

### 3.2 权限动作

| 现动作 | 新动作 | 来源工具 |
|---|---|---|
| `shell` | `bash` | `bash`、`run_tests`、`run_code`、`run_command_background`、`background_*`、`git_add` / `git_commit` / `git_branch` / `git_stash` |
| `subagent` | `task` | `task` |
| `read` | `read`（不变） | `read`、`list` |
| `edit` | `edit`（不变） | `write`、`edit`、`apply_patch` |
| `grep` / `glob` / `webfetch` / `websearch` / `skill` / `question` / `external_directory` | 不变 | 同名工具 |
| `todowrite` | 新增独立动作 | `todowrite` |

MCP 工具仍按 `server__tool` → `server_tool` 归一；`list_mcp_resources` /
`read_mcp_resource` 动作名不变。

## 4. 改动落点

### 4.1 工具标识

- `conatus_code/lib/src/fs_tools/{read_file,write_file,edit_file}.dart`、
  `src/tools/{apply_patch,list_files,run_command}.dart`、
  `src/fs_tools/ripgrep_tool.dart`、`src/tui/ask_user_tool.dart`、
  `src/tools/update_plan.dart`：`name` getter 与常量改新名。
- `conatus_search/lib/src/web_tools.dart`（`websearch` / `webfetch`）；
  `search_parallel.dart` 的 `kParallelSearchTool`。
- `conatus_agent/lib/src/sub_agent.dart`（`task`）；
  `conatus_tasks/lib/src/task_tracking.dart` 的 `kSpawnAgentToolName`。

### 4.2 按工具名分派的派生表

- `conatus_agent/lib/src/permissions/permission_action.dart`：动作归一表、
  `_pathActions`、`apply_patch` 特判、git 资源派生。
- `conatus_code/lib/src/agents/agent_open_code.dart`：工具映射退化为恒等并删除
  多余表；动作表只保留 `write` / `patch` → `edit` 等归并。
- `conatus_code/lib/src/agents/agent_builtins.dart`（内置白名单）、
  `agent_definition.dart` / `agent_resolver.dart` 的默认白名单。
- `conatus_code/lib/src/format/formatter_service.dart`、
  `src/story/{story,story_review,story_notices}.dart`、
  `src/xerj/xerj_auto_indexer.dart`、`src/instructions/instruction_wiring.dart`、
  `src/diff/preview.dart`、`src/tui/{tui_permission_gate,transcript}.dart`、
  `src/headless/headless_guard.dart`、`src/skills/bootstrap_skills.dart`。
- `conatus_agent/lib/src/{approval,tool_result_eviction,sub_agent_profile,plan_mode,
  sub_agent_progress,sub_agent_permission,tool_budget_policy}.dart`；
  `conatus_harness/lib/src/manifest.dart`（默认 `finalizeAllowed`）。

### 4.3 配置与导入导出

- `config_loader.dart` 模板注释、`config_schema.dart`、`config_parser.dart`：
  示例动作改为 `bash`；OpenCode 导入的动作归一继续走 `permissionActionFor`。
- `cli/opencode_import_*.dart`：导出的 `[[permissions]]` / frontmatter 直接写
  OpenCode 动作名（`bash` / `edit` / `task` …）。
- `README.md`、`packages/conatus_code/README.md`、各受影响包 README、
  `packages/conatus_code/docs/{story,plugin-integration}.md`。
- `example/` 与根 `test/` 中引用真实工具名的脚本化模型 / 断言。

## 5. 兼容性与风险

- **破坏性**：存量 `~/.nava/config.toml` 的 `action = "shell"` / `"subagent"`、
  Agent frontmatter、Skill 提示里的旧工具名都会失效。按决策不保留别名。
- **`rg` 词形冲突**：只改工具标识，不改 ripgrep 二进制与注释里的 `rg`。
- **`shell` / `subagent` 词形冲突**：只改权限动作字符串；`'shell'` 服务键、
  ShellExecutor、subagent 领域概念一概不动。
- **`linter.dart` 含一个 NUL 字节**（`_claim(targets.join('\0'))`）：编辑该文件时
  必须按 UTF-8 原样写回，不能做编码转换。
- 公开包改名会影响伞包外消费者；当前无已知下游，且项目仍在 dogfood。

## 6. 验证与发布顺序

1. 父仓库：公共包改名 + 全部引用更新，`dart analyze --fatal-infos`，
   受影响包 `dart test`，根 `dart test test/integration/`。
2. 提交并推父仓库。
3. 子模块 `packages/conatus_code`：`bash tool/pin_conatus_refs.sh` 刷新 conatus
   ref，跑 `dart test`，`bash tool/build_binary.sh` 重建 `dist/nava`。
4. 提交并推子模块，父仓库同步 gitlink（`chore(code): ...`）。
5. 手工验收：`nava` 里触发一次 `bash` / `edit` / `read`，确认上屏为新名；
   用 `[[permissions]] action = "bash"` 验证规则命中。

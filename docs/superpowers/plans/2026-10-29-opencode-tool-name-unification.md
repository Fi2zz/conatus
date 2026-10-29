# 工具标识与权限动作统一为 OpenCode 命名 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 nava 与公共包里的工具标识、权限动作名一次性改成 OpenCode 的名字，使上屏、Agent 白名单、`[[permissions]]` 使用同一套词汇。

**Architecture:** 只改标识层：`Tool.name`、权限动作归一表、按工具名分派的派生表与配置读写。工具实现、类名、文件名、服务键、ripgrep 二进制名不动。旧名不留别名。

**Tech Stack:** Dart 3.11 / pub workspace / package:test；nava 子模块 `packages/conatus_code`。

**Spec:** `docs/superpowers/specs/2026-10-29-opencode-tool-name-unification-design.md`

## Global Constraints

- 工具名映射（逐字）：`read_file`→`read`、`write_file`→`write`、`edit_file`→`edit`、`list_files`→`list`、`run_command`→`bash`、`rg`→`grep`、`web_search`→`websearch`、`fetch_url`→`webfetch`、`spawn_agent`→`task`、`ask_user`→`question`、`update_plan`→`todowrite`；`apply_patch`、`glob`、`skill` 不变。
- 权限动作映射：`shell`→`bash`、`subagent`→`task`；`run_tests` / `run_code` / `run_command_background` / `background_*` / `git_add` / `git_commit` / `git_branch` / `git_stash` 归一为 `bash`；`list` 归一为 `read`；`todowrite` 为独立动作。
- 不保留旧名别名；不新增兼容层。
- 不改类名、文件名、导出名、服务键（`'shell'`、`'fs'`、`'tools'`）。
- 不改 ripgrep 可执行名 `rg`、`RipgrepBinary`、`doctor` 的 `rg` 检查；不改 `kParallelSearchTool = 'web_search'` / `kExaMcpSearchTool = 'web_search_exa'`（远端 MCP 工具名）。
- 不改 `docs/superpowers/specs|plans` 下的历史文档。
- 遵守仓库硬约束：单文件 ≤ 200 行、函数体 ≤ 40 行、包内相对导入。
- `packages/conatus_code/lib/src/lint/linter.dart` 含一个字面 NUL 字节（`targets.join('\0')`）：任何重写必须保留 UTF-8 与 NUL，不得转码。
- 每个任务结束提交；提交信息用 `refactor(<scope>): ...` / `docs(...)` / `chore(code): ...`。

## Review Focus

1. **上屏与注册名一致**：每个工具测试断言 `tool.name` 是新名，避免只改内部表、上屏仍显示旧名。
2. **`bash` 动作仍覆盖 git / 后台工具**：`git_add` 等经 `permissionActionFor` 必须是 `bash`，`action="bash", resource="git *"` 能拦住。
3. **OpenCode 导入导出闭合**：`nava import opencode` 导入 `bash` / `write` 后导出 TOML 写 `action = "bash"` / `"edit"`，不出现 `shell`。
4. **远端 MCP 工具名不被误改**：Parallel / Exa 的 `web_search` 常量保持原样，只改本地 `WebSearchTool.name`。
5. **linter.dart 的 NUL 保留**：改名后 `linter_test.dart` 通过，且文件仍能按 UTF-8 解码、NUL 计数为 1。

---

### Task 1: conatus_agent —— 工具 `task` 与权限动作 `bash` / `task`

**Files:**
- Modify: `packages/conatus_agent/lib/src/sub_agent.dart`
- Modify: `packages/conatus_agent/lib/src/permissions/permission_action.dart`
- Modify: `packages/conatus_agent/lib/src/tool_budget_policy.dart`
- Modify: `packages/conatus_agent/lib/src/plan_mode.dart`
- Modify: `packages/conatus_agent/lib/src/tool_result_eviction.dart`
- Modify: `packages/conatus_agent/lib/src/{approval,sub_agent_profile,sub_agent_permission,sub_agent_progress}.dart`（注释与提示文案）
- Modify: `packages/conatus_agent/lib/src/permissions/permission_path.dart`（注释）
- Test: `packages/conatus_agent/test/**` 中引用旧名的文件（见步骤 1）
- Test: 新增 `packages/conatus_agent/test/permissions/permission_opencode_action_test.dart`

**Interfaces:**
- Produces: `SpawnAgentTool().name == 'task'`；`permissionActionFor(tool)` 返回 `bash` / `task` / `read` / `edit` / `todowrite` 等新动作。
- Produces: `ToolBudgetPolicy.finalizeAllowed` 默认 `{'read'}`。

- [ ] **Step 1: 更新测试到新名（先红）**

  在 `packages/conatus_agent/test/` 里按映射替换测试中的真实工具名（`read_file`→`read`、`write_file`→`write`、`run_command`→`bash`、`web_search`→`websearch`、`spawn_agent`→`task`）。至少覆盖：
  `permissions/permission_git_action_test.dart`、`permissions/permission_subagent_test.dart`、
  `permissions/sub_agent_profile_permission_test.dart`、`permissions/permission_path_spelling_test.dart`、
  `tool_budget_policy_test.dart`、`tool_budget_hooks_test.dart`、`tool_result_eviction_test.dart`、
  `approval_test.dart`、`agent_images_test.dart`、`layered_compaction_test.dart`、
  `sub_agent_test.dart`、`sub_agent_agent_llm_test.dart`、`sub_agent_agent_mode_test.dart`、
  `sub_agent_agent_profile_test.dart`、`sub_agent_progress_test.dart`、`sub_agent_profile_support.dart`、
  `telemetry_test.dart`、`eval_test.dart`、`eval_checks_test.dart`。

  `permission_git_action_test.dart` 的断言改为：

  ```dart
  expect(permissionActionFor(tool), 'bash');
  const PermissionRule(action: 'bash', resource: 'git *', effect: PermissionEffect.deny);
  ```

  新增 `permission_opencode_action_test.dart`：

  ```dart
  import 'package:conatus_agent/conatus_agent.dart';
  import 'package:test/test.dart';

  void main() {
    test('权限动作采用 OpenCode 键名', () {
      expect(permissionActionFor('bash'), 'bash');
      expect(permissionActionFor('run_tests'), 'bash');
      expect(permissionActionFor('git_add'), 'bash');
      expect(permissionActionFor('task'), 'task');
      expect(permissionActionFor('list'), 'read');
      expect(permissionActionFor('todowrite'), 'todowrite');
      expect(permissionActionFor('write'), 'edit');
      expect(permissionActionFor('apply_patch'), 'edit');
    });
  }
  ```

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_agent && dart test`
  Expected: FAIL（`permissionActionFor('git_add')` 仍为 `shell`；`SpawnAgentTool.name` 仍为 `spawn_agent`）

- [ ] **Step 3: 改实现**

  - `sub_agent.dart`：`String get name => 'task';`
  - `permission_action.dart`：`_toolActions` 只保留跨名映射：
    `list`→`read`、`write`→`edit`、`apply_patch`→`edit`、`run_tests`→`bash`、
    `run_code`→`bash`、`run_command_background`→`bash`、`list_background_tasks`→`bash`、
    `background_output`→`bash`、`background_kill`→`bash`、`git_add`→`bash`、
    `git_commit`→`bash`、`git_branch`→`bash`、`git_stash`→`bash`。
    删除旧工具名条目；`permissionResourcesFor` 的 `switch` 分支 `'shell'` 改为 `'bash'`；
    注释里的 `action="shell"` 改为 `action="bash"`。
  - `tool_budget_policy.dart`：`finalizeAllowed` 默认值改为 `const <String>{'read'}`。
  - `plan_mode.dart`：提示词 `web_search and ask_user` → `websearch and question`。
  - `tool_result_eviction.dart`：提示文案 `read_file` → `read`。
  - 其余命中文件只改注释/文案中的旧工具名。

- [ ] **Step 4: 跑测试确认通过**

  Run: `cd packages/conatus_agent && dart test`
  Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent
git commit -m "refactor(agent): 工具标识与权限动作对齐 OpenCode（task/bash）"
```

---

### Task 2: conatus_tasks —— 子代理工具名 `task`

**Files:**
- Modify: `packages/conatus_tasks/lib/src/task_tracking.dart`
- Modify: `packages/conatus_tasks/lib/src/task_center_provider.dart`（注释）
- Modify: `packages/conatus_tasks/lib/conatus_tasks.dart`（注释）
- Test: `packages/conatus_tasks/test/task_tracking_test.dart`
- Test: `packages/conatus_tasks/README.md`

**Interfaces:**
- Consumes: Task 1 的 `SpawnAgentTool.name == 'task'`。
- Produces: `kSpawnAgentToolName == 'task'`。

- [ ] **Step 1: 更新测试与常量断言**

  `task_tracking_test.dart` 增加：

  ```dart
  test('子代理工具名与 OpenCode 一致', () {
    expect(kSpawnAgentToolName, 'task');
  });
  ```

  组名与 reason 文案里的 `spawn_agent` 改为 `task`。

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_tasks && dart test`
  Expected: FAIL（常量为 `spawn_agent`）

- [ ] **Step 3: 改实现**

  `const String kSpawnAgentToolName = 'task';`，同步注释与 README 中的 `spawn_agent` 文案。

- [ ] **Step 4: 跑测试确认通过**

  Run: `cd packages/conatus_tasks && dart test`
  Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_tasks
git commit -m "refactor(tasks): 子代理工具名改为 task"
```

---

### Task 3: conatus_search —— `websearch` / `webfetch`

**Files:**
- Modify: `packages/conatus_search/lib/src/web_tools.dart`
- Modify: `packages/conatus_search/lib/src/search_kimi.dart`（注释）
- Test: `packages/conatus_search/test/web_tools_test.dart`
- Modify: `packages/conatus_search/README.md`

**Interfaces:**
- Produces: `WebSearchTool().name == 'websearch'`、`FetchUrlTool().name == 'webfetch'`。
- 保持：`kParallelSearchTool == 'web_search'`、`kExaMcpSearchTool == 'web_search_exa'`。

- [ ] **Step 1: 更新测试**

  `web_tools_test.dart`：`expect(tool.name, 'web_search')` → `'websearch'`；
  `containsAll(['web_search', 'fetch_url'])` → `containsAll(['websearch', 'webfetch'])`。
  新增断言远端常量未被改名：

  ```dart
  test('远端 MCP 工具名保持上游值', () {
    expect(kParallelSearchTool, 'web_search');
    expect(kExaMcpSearchTool, 'web_search_exa');
  });
  ```

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_search && dart test`
  Expected: FAIL（本地工具名仍为旧值）

- [ ] **Step 3: 改实现**

  `WebSearchTool.name` 改 `websearch`、`FetchUrlTool.name` 改 `webfetch`；
  只更新注释/README 中的本地工具名，**不要**改 `kParallelSearchTool` / `kExaMcpSearchTool`。

- [ ] **Step 4: 跑测试确认通过**

  Run: `cd packages/conatus_search && dart test`
  Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_search
git commit -m "refactor(search): 联网工具名对齐 OpenCode（websearch/webfetch）"
```

---

### Task 4: conatus_harness —— 默认收口白名单 `read`

**Files:**
- Modify: `packages/conatus_harness/lib/src/manifest.dart`
- Test: `packages/conatus_harness/test/manifest_json_test.dart`
- Test: `packages/conatus_harness/test/apply_test.dart`
- Test: `packages/conatus_harness/test/diff_test.dart`
- Modify: `packages/conatus_harness/README.md`

**Interfaces:**
- Produces: 未声明 `finalizeAllowed` 时默认 `{'read'}`。

- [ ] **Step 1: 更新测试**

  把测试里的 `read_file` 改为 `read`；在 `manifest_json_test.dart` 增加：

  ```dart
  test('缺省 finalizeAllowed 使用 OpenCode 工具名', () {
    final HarnessManifest parsed = HarnessManifest.fromJson(<String, Object?>{
      'name': 'slim',
      'profile': <String, Object?>{'name': 'lean'},
    });
    expect(parsed.profile.budget.finalizeAllowed, <String>{'read'});
  });
  ```

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_harness && dart test`
  Expected: FAIL（默认仍为 `read_file`）

- [ ] **Step 3: 改实现**

  `manifest.dart` 默认值 `{'read_file'}` → `{'read'}`；README 示例同步。

- [ ] **Step 4: 跑测试确认通过**

  Run: `cd packages/conatus_harness && dart test`
  Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_harness
git commit -m "refactor(harness): 默认工具白名单改为 read"
```

---

### Task 5: conatus_code —— 工具标识、派生表与兼容层

**Files:**
- Modify: `packages/conatus_code/lib/src/fs_tools/{read_file,write_file,edit_file,ripgrep_tool}.dart`
- Modify: `packages/conatus_code/lib/src/tools/{list_files,run_command,update_plan}.dart`
- Modify: `packages/conatus_code/lib/src/tui/{ask_user_tool,tui_app,tui_controller,tui_permission_gate}.dart`
- Modify: `packages/conatus_code/lib/src/agents/{agent_builtins,agent_open_code,agent_tools,agent_definition,agent_resolver}.dart`
- Modify: `packages/conatus_code/lib/src/permissions/{permission_wiring,permission_rule_pattern}.dart`
- Modify: `packages/conatus_code/lib/src/{format/formatter_service,story/story,story/story_review,story/story_render,story/story_notices,xerj/xerj_auto_indexer,instructions/instruction_wiring,diff/preview,headless/headless_guard,skills/bootstrap_skills,references/references,lsp/lsp_tool,mcp/mcp_assembly,subagent/swarm_member}.dart`
- Modify: `packages/conatus_code/lib/src/fs_tools/{read_only_path_guard,spill_dir,fs_tools}.dart`、`lib/{conatus_code,fs_tools,tui}.dart`（注释/导出说明）
- Modify: `packages/conatus_code/lib/src/{config/config_loader,config_schema,config_parser}.dart`（注释与示例）
- Modify: `packages/conatus_code/lib/src/tools/{code_tools,git_tools,git_write_tools,protected_command}.dart`（注释）
- Test: `packages/conatus_code/test/**`（步骤 1 列出的替换）
- Test: `packages/conatus_code/example/playground.dart`

**Interfaces:**
- Consumes: Tasks 1–4 的 `task` / `websearch` / `webfetch` / `read`。
- Produces: 全部 nava 工具名为 OpenCode 名；`agent_open_code.dart` 不再有工具名映射。

- [ ] **Step 1: 更新 conatus_code 测试与示例到新名（先红）**

  在 `packages/conatus_code/test/` 与 `packages/conatus_code/example/` 内替换真实工具标识：
  `read_file`→`read`、`write_file`→`write`、`edit_file`→`edit`、`list_files`→`list`、
  `run_command`→`bash`、`web_search`→`websearch`、`fetch_url`→`webfetch`、
  `spawn_agent`→`task`、`ask_user`→`question`、`update_plan`→`todowrite`。

  例外（保持不动）：`test/fs_tools/ripgrep_binary_test.dart`、`lib/src/diagnose/doctor.dart`
  里的可执行文件 `rg`；远端 MCP 工具名；`docs/superpowers` 历史文档。

  在既有工具测试里补 `name` 断言（Review Focus 1）：

  ```dart
  expect(ReadFileTool(fs: fakeFs).name, 'read');      // test/fs_tools/read_file_test.dart
  expect(WriteFileTool(fs: fakeFs).name, 'write');    // test/fs_tools/write_file_test.dart
  expect(EditFileTool(fs: fakeFs).name, 'edit');      // test/fs_tools/edit_file_test.dart
  expect(RunCommandTool(shell: fakeShell).name, 'bash'); // test/tools/run_command_test.dart
  expect(ListFilesTool(fs: fakeFs).name, 'list');     // test/tools/list_files_test.dart
  expect(RipgrepTool(...).name, 'grep');              // test/fs_tools/ripgrep_tool_test.dart
  ```

  用测试文件里已有的 fake 构造，不新增替身框架。

  权限测试改新动作：`test/permissions/permission_action_rules_test.dart` 中
  `run_tests` 期望 `bash`、`web_search`→`websearch`、`read_file/list_files`→`read/list`、
  `write_file/edit_file`→`write/edit`、`rg`→`grep`、`spawn_agent`→`task`（动作 `task`）、
  `ask_user`→`question`、`fetch_url`→`webfetch`。

  `test/agents/agent_parser_opencode_test.dart` 期望值改为恒等：

  ```dart
  expect(def.disabledTools, containsAll(<String>['write', 'edit', 'bash']));
  expect(def.tools, <String>['read', 'grep', 'custom_tool']);
  expect(def.tools, <String>['question', 'todowrite']);
  ```

  `test/agents/agent_parser_test.dart` 的白名单期望改为 `<String>['read', 'grep']`。

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_code && dart test`
  Expected: FAIL（工具 `name`、权限动作、Agent 解析仍是旧值）

- [ ] **Step 3: 改实现**

  - 工具 `name`：`read`、`write`、`edit`、`grep`、`list`、`bash`、`question`、`todowrite`。
  - `agent_open_code.dart`：
    - `_openCodeActions` 只保留 `write`→`edit`、`patch`→`edit`；
    - 删除 `_openCodeTools` 与 `mapAgentToolName`，`agent_tools.dart` 直接用原始字符串；
    - `_knownActions` 改为 `read/edit/bash/grep/glob/webfetch/websearch/task/skill/question/todowrite/external_directory`；
    - `_unsupportedActions` 只保留 `todoread`、`lsp`。
  - `permission_wiring.dart` 与 `permission_rule_pattern.dart`：`'shell'` → `'bash'`。
  - 派生列表：formatter `['write','edit','apply_patch']`；story 同；xerj 同；
    instruction 白名单 `['read','list','grep','glob']`；diff 预览 `write`/`edit`；
    lsp 写工具集合 `{'write','edit','apply_patch'}`；
    `agent_builtins` 的内置白名单改用新名（general：`read/list/grep/glob/write/edit/apply_patch/git_*/websearch/webfetch/todowrite`；
    explore：`read/list/grep/glob/websearch/webfetch`）。
  - TUI：`tools.get('task')`、`LlmToolCall(name: 'task')`、探索默认白名单新名、
    bootstrap 提示、story 提示、references 提示、eviction/spill 提示全部改新名。
  - config 注释与 schema 文案：`action = "bash"`、`task`。
  - `linter.dart` 只把列表里的 `write_file`/`edit_file` 改为 `write`/`edit`，保留原编码与 NUL。

- [ ] **Step 4: 全包测试通过**

  Run: `cd packages/conatus_code && dart test`
  Expected: PASS

- [ ] **Step 5: 确认 linter.dart 未被转码（Review Focus 5）**

  ```bash
  python3 - <<'EOF'
  b = open('packages/conatus_code/lib/src/lint/linter.dart', 'rb').read()
  assert b.count(b'\x00') == 1
  b.decode('utf-8')
  print('ok')
  EOF
  ```

  Expected: `ok`

- [ ] **Step 6: 提交**

```bash
git add packages/conatus_code
git commit -m "refactor(code): 工具标识与权限动作对齐 OpenCode"
```

---

### Task 6: conatus_code —— OpenCode 导入/导出与配置模板

**Files:**
- Modify: `packages/conatus_code/lib/src/cli/opencode_import_permissions.dart`（如需）
- Modify: `packages/conatus_code/lib/src/config/config_loader.dart`（`# action = "shell"` 示例）
- Test: `packages/conatus_code/test/cli/opencode_import_map_test.dart`
- Test: `packages/conatus_code/test/cli/opencode_import_writer_test.dart`
- Test: `packages/conatus_code/test/config/config_mcp_writer_test.dart`
- Test: `packages/conatus_code/test/permissions/permission_config_test.dart`
- Test: `packages/conatus_code/test/permissions/permission_config_runtime_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `permissionActionFor` / `agentActionSupported`。
- Produces: 导入导出的 TOML / frontmatter 只出现 `bash` / `edit` / `task` 等 OpenCode 动作。

- [ ] **Step 1: 更新测试**

  - `opencode_import_map_test.dart`：权限归一化期望 `<String>['bash', 'edit']`，`lsp` 仍告警跳过。
  - `opencode_import_writer_test.dart`：已有配置 fixture 改 `action = "bash"`；重复权限计数仍为 1。
  - `config_mcp_writer_test.dart`：fixture 与期望 `action = "bash"`。
  - `permission_config_test.dart` / `permission_config_runtime_test.dart`：`action = "shell"` → `"bash"`，断言动作 `bash`。
  - 新增断言：导入 `bash` 后导出的 TOML 包含 `action = "bash"` 且不包含 `action = "shell"`。

- [ ] **Step 2: 跑测试确认失败**

  Run: `cd packages/conatus_code && dart test test/cli test/config test/permissions/permission_config_test.dart test/permissions/permission_config_runtime_test.dart`
  Expected: FAIL

- [ ] **Step 3: 改实现**

  `opencode_import_permissions.dart` 无需新增映射（`normalizeAgentAction` 已返回 `bash`）；
  确认 `agentActionSupported` 已放行 `list` / `todowrite`、仍拦截 `lsp` / `todoread`。
  `config_loader.dart` 模板注释 `action = "shell"` → `action = "bash"`。

- [ ] **Step 4: 跑测试确认通过**

  Run: 同 Step 2
  Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_code
git commit -m "refactor(code): OpenCode 导入导出使用 bash 等动作名"
```

---

### Task 7: 文档、示例与根测试

**Files:**
- Modify: `README.md`、`AGENTS.md`
- Modify: `packages/{conatus_agent,conatus_browser_use,conatus_code,conatus_foundation,conatus_harness,conatus_mcp,conatus_search,conatus_tasks,conatus_team}/README.md`
- Modify: `packages/conatus_code/docs/{story,plugin-integration}.md`
- Modify: `packages/conatus_code/example/playground.dart`（若 Task 5 未覆盖）
- Modify: 根 `example/{main,voice_plan_mode}.dart`
- Test: 根 `test/integration/{terminal_booking,plan_mode,goal_continuation,failure_retry}_test.dart`

- [ ] **Step 1: 按映射替换文档、示例与根测试中的真实工具名与权限动作**

  只替换描述 nava / conatus 当前行为的名字；不碰 `docs/superpowers/specs|plans` 历史文档；
  `conatus_mcp` 的别名示例可保留任意名，但统一改成 `read` 更清晰。
  根测试里脚本化模型调用的工具名同步替换（`read_file`→`read` 等）。

- [ ] **Step 2: 校验没有遗漏**

  ```bash
  grep -rn "'read_file'\|'write_file'\|'edit_file'\|'run_command'\|'spawn_agent'\|action = \"shell\"" \
    README.md AGENTS.md packages/*/README.md packages/conatus_code/docs example test packages/*/lib packages/*/test
  ```

  Expected: 无输出（远端 `web_search` / `rg` 二进制命中除外，需逐条确认）。

- [ ] **Step 3: 提交**

```bash
git add README.md AGENTS.md packages example
git commit -m "docs: 工具名与权限动作统一为 OpenCode 命名"
```

---

### Task 8: 全仓验证与发布顺序

**Files:** 无新增；只跑验证与发版步骤。

- [ ] **Step 1: 静态检查**

  Run: `dart analyze --fatal-infos`
  Expected: `No issues found!`

- [ ] **Step 2: 逐包测试**

  ```bash
  for d in packages/*/; do (cd "$d" && dart test) || exit 1; done
  ```

  Expected: 全部 PASS（子模块 `conatus_code` 也在其中）。

- [ ] **Step 3: 根集成测试**

  Run: `dart test test/integration/ --reporter=expanded`
  Expected: PASS

- [ ] **Step 4: 提交并推送父仓库**

  ```bash
  git status --short
  git push origin master
  ```

- [ ] **Step 5: 子模块刷新 conatus ref、测试、重建二进制**

  ```bash
  cd packages/conatus_code
  bash tool/pin_conatus_refs.sh
  dart test
  bash tool/build_binary.sh
  ./dist/nava --version
  ```

  Expected: 测试 PASS；`--version` 输出成功。

- [ ] **Step 6: 提交并推送子模块，父仓同步 gitlink**

  ```bash
  git -C packages/conatus_code add -A
  git -C packages/conatus_code commit -m "chore: 刷新 conatus refs（OpenCode 工具名统一）"
  git -C packages/conatus_code push origin master
  git add packages/conatus_code
  git commit -m "chore(code): 同步子模块 gitlink（OpenCode 工具名统一）"
  git push origin master
  ```

- [ ] **Step 7: 手工验收**

  启动 `nava`，确认：

  - 调用 shell 时上屏显示 `bash`，读文件显示 `read`，编辑显示 `edit`；
  - `[[permissions]] action = "bash"` + `resource = "npm *"` 能放行/拦截对应命令；
  - `[[permissions]] action = "edit"` 能拦住 `write` / `edit` / `apply_patch`。

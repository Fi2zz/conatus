# nava 日常体验对齐 OpenCode V2 — B 组（自定义）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现自定义命令、自定义 Agent、AGENTS.md 层级 + `instructions`、主题与键位，全部兼容 OpenCode 文件约定但只读 `.opencode`。

**Architecture:** 先抽一个通用 frontmatter 解析器（复用 `conatus_skill` 的 YAML 能力），再分别建 Command / Agent 注册表；命令与 Agent 都从 `.nava` 与 `.opencode` 读取，nava 优先。Agent 通过 `SpawnAgentTool` 的 resolver 注入，权限复用 A 组的 `PermissionScope`。指令加载器替换现有根目录 `project_context.dart`。主题用语义 token 层替换硬编码 `Colors.*`；键位只接管全局动作。

**Tech Stack:** Dart 3.11+、`package:test`、`nocterm`、`yaml`（经 `conatus_skill` 导出）、`toml`。

**Spec:** `docs/superpowers/specs/2026-10-22-nava-opencode-daily-parity-design.md`

## Global Constraints

- `.opencode` 与 `~/.config/opencode` **严格只读**：只 `read`/`list`，不建目录、不写缓存、不改元数据。
- nava 只写 `~/.nava/**` 或显式项目数据目录；不写 OpenCode 目录。
- 所有新增配置可选；不配置时行为与当前一致。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、参数 ≤ 4 个。
- 每个任务跑目标测试 + `dart analyze --fatal-infos`；提交用 Conventional Commits。
- 命令/Agent 的 ID 由路径派生：`.nava/commands/team/review.md` → `team/review`；不要求 frontmatter 提供 `name`。

## Review Focus

1. **`.opencode` 只读**：命令/Agent 发现只读；不得因为“补一个默认目录”而创建 `.opencode`。
2. **同名覆盖顺序**：项目 > 全局，nava > opencode；内置命令/Agent 可被同名自定义覆盖（命令除外：内置斜杠命令优先，防止劫持 `/exit`）。
3. **frontmatter 非法**：缺字段/类型错误只跳过该条目并警告，不让整个注册表失败。
4. **Agent 权限只能收紧**：子 Agent 自定义 `permissions` 不能放宽父级显式 deny。
5. **主题默认不变**：不配置主题时，渲染结果与当前一致；键位默认不改变现有快捷键。

---

### Task 1: 通用 frontmatter 解析器

**Files:**
- Create: `packages/conatus_skill/lib/src/frontmatter.dart`
- Modify: `packages/conatus_skill/lib/src/skill_markdown.dart`（改为复用新解析器）
- Modify: `packages/conatus_skill/lib/conatus_skill.dart`（导出）
- Test: `packages/conatus_skill/test/frontmatter_test.dart`

**Interfaces:**
- `class FrontmatterDocument { const FrontmatterDocument({required Map<String, Object?> fields, required String body, String? error}); }`
- `FrontmatterDocument parseFrontmatter(String text)`

- [ ] **Step 1: Write the failing test**

```dart
test('parses fields and body', () {
  final doc = parseFrontmatter('---\ndescription: review\nmode: subagent\n---\nBody here\n');
  expect(doc.fields['description'], 'review');
  expect(doc.fields['mode'], 'subagent');
  expect(doc.body, 'Body here');
  expect(doc.error, isNull);
});

test('missing closing fence returns error', () {
  expect(parseFrontmatter('---\na: b\nbody').error, contains('缺少'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_skill && dart test test/frontmatter_test.dart`
Expected: FAIL — `parseFrontmatter` not defined.

- [ ] **Step 3: Implement**

把 `skill_markdown.dart` 的 `_splitFrontmatter` + `loadYaml` 逻辑抽到 `frontmatter.dart`；`parseSkillDocument` 改为调用它，再校验 `name`/`description`。保持现有错误文案与 CRLF 容忍。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/conatus_skill && dart test test/frontmatter_test.dart test/skill_markdown_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_skill/lib/src/frontmatter.dart packages/conatus_skill/lib/src/skill_markdown.dart packages/conatus_skill/lib/conatus_skill.dart packages/conatus_skill/test/frontmatter_test.dart
git commit -m "refactor(skill): 抽出通用 frontmatter 解析器"
```

---

### Task 2: 命令定义、解析与注册表

**Files:**
- Create: `packages/conatus_code/lib/src/commands/command_definition.dart`
- Create: `packages/conatus_code/lib/src/commands/command_parser.dart`
- Create: `packages/conatus_code/lib/src/commands/command_registry.dart`
- Create: `packages/conatus_code/lib/src/commands/command_expander.dart`
- Test: `packages/conatus_code/test/commands/command_parser_test.dart`
- Test: `packages/conatus_code/test/commands/command_registry_test.dart`
- Test: `packages/conatus_code/test/commands/command_expander_test.dart`

**Interfaces:**
- `class CommandDefinition { final String name; final String description; final String template; final String? agent; final String? model; final bool subagent; final String sourcePath; final Future<String> Function(String args)? executor; }`
  - `executor` 非空时优先于 `template`，供 MCP prompt 等动态命令使用（C 组）。
- `CommandDefinition? parseCommandDocument(String text, {required String name, required String sourcePath})`
- `class CommandRegistry { static Future<CommandRegistry> load({required String workdir, String? home}); List<CommandDefinition> get all; CommandDefinition? byName(String name); void add(CommandDefinition def); }`
- `String expandCommand(CommandDefinition def, String args, {required Future<String> Function(String) runShell})`

- [ ] **Step 1: Write the failing tests**

```dart
test('parses command frontmatter and body', () {
  final def = parseCommandDocument('''
---
description: review
agent: plan
model: ark/doubao-seed-2-0-lite
subagent: false
---
Review $ARGUMENTS.
''', name: 'review', sourcePath: '/tmp/review.md')!;
  expect(def.agent, 'plan');
  expect(def.template, contains(r'$ARGUMENTS'));
});

test('expands positional args and shell blocks', () async {
  final def = CommandDefinition(name: 'x', description: '', template: 'Check \$1\n!\`echo hi\`', sourcePath: '');
  expect(await expandCommand(def, '"a b" c', runShell: (c) async => 'OUT'), contains('Check a b'));
  expect(await expandCommand(def, 'x', runShell: (c) async => 'OUT'), contains('OUT'));
});

test('registry precedence: project .nava over global .opencode', () async {
  // temp dirs with same command name
  expect(registry.byName('review')!.sourcePath, contains('.nava'));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/commands`
Expected: FAIL — `CommandDefinition` not defined.

- [ ] **Step 3: Implement**

- 解析：`parseFrontmatter`；字段类型校验；缺 `template` 的空正文允许（空命令只提示）。
- 发现顺序（低→高）：`~/.config/opencode/commands` → `~/.nava/commands` → `<workdir>/.opencode/commands` → `<workdir>/.nava/commands`；递归 `.md`，嵌套路径成 ID。
- 只读：只用 `Directory.list` / `File.readAsString`；不创建目录。
- 展开：`$ARGUMENTS`、`$1..$9`（引号分组）；无占位符则参数追加；shell 块 `!` + 反引号，单块输出上限 8000 字符。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/commands`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/commands packages/conatus_code/test/commands
git commit -m "feat(code): 增加自定义命令解析与注册表"
```

---

### Task 3: Agent 定义、解析与内置 Agent

**Files:**
- Create: `packages/conatus_code/lib/src/agents/agent_definition.dart`
- Create: `packages/conatus_code/lib/src/agents/agent_parser.dart`
- Create: `packages/conatus_code/lib/src/agents/agent_registry.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`（`AgentConfig.defaultAgent`）
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Test: `packages/conatus_code/test/agents/agent_parser_test.dart`
- Test: `packages/conatus_code/test/agents/agent_registry_test.dart`
- Test: `packages/conatus_code/test/config/config_default_agent_test.dart`

**Interfaces:**
- `enum AgentMode { primary, subagent, all }`
- `class AgentDefinition { final String id; final String description; final AgentMode mode; final String system; final String? model; final int? steps; final List<String>? tools; final List<PermissionRule> permissions; final bool hidden; final String? color; final String sourcePath; }`
- `AgentDefinition? parseAgentDocument(String text, {required String id, required String sourcePath})`
- `class AgentRegistry { static Future<AgentRegistry> load({required String workdir, String? home, String? defaultId}); AgentDefinition? byId(String id); List<AgentDefinition> get visible; List<AgentDefinition> get subagents; AgentDefinition get defaultAgent; }`
- `AgentConfig.defaultAgent`（`[agent] default_agent`，缺省 `'build'`）；`AgentRegistry.defaultAgent` 优先用它，找不到回退 `build`。
- 内置：`build`（primary）、`plan`（primary，`edit` deny）、`general`（subagent）、`explore`（subagent，只读）。

- [ ] **Step 1: Write the failing tests**

```dart
test('parses agent permissions and mode', () {
  final def = parseAgentDocument('''
---
description: reviewer
mode: subagent
model: ark/doubao-seed-2-0-lite
steps: 6
permissions:
  - action: edit
    resource: "*"
    effect: deny
---
Review only.
''', id: 'reviewer', sourcePath: '/tmp/reviewer.md')!;
  expect(def.mode, AgentMode.subagent);
  expect(def.steps, 6);
  expect(def.permissions.single.effect, PermissionEffect.deny);
});

test('hidden agents are not visible but resolvable', () async {
  final registry = await AgentRegistry.load(workdir: dir.path, home: home.path);
  expect(registry.visible.any((a) => a.id == 'hidden'), isFalse);
  expect(registry.byId('hidden'), isNotNull);
});

test('[agent] default_agent selects the default', () {
  final config = loadConfigFromToml('[agent]\ndefault_agent = "plan"');
  expect(config.agent.defaultAgent, 'plan');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/agents`
Expected: FAIL — `AgentDefinition` not defined.

- [ ] **Step 3: Implement**

- 发现顺序同命令（`.opencode/agents` + `.nava/agents` + 全局），嵌套路径成 ID；内置先注册，自定义同名覆盖。
- frontmatter：`description` 可选但建议；`mode` 缺省 primary；`permissions` 列表转 `PermissionRule`；`tools` 列表；`hidden`/`color`/`steps`/`model`。
- `plan` 的 `permissions` 预置 `edit * deny`；`explore` 预置 `edit * deny` + 只读工具；`general` 不禁止写，但不能 spawn 子 Agent（由 spawn 工具自身限制）。
- 非法条目：返回 `null` + 调用方 Warning；不要让整个 load 失败。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/agents`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/agents packages/conatus_code/test/agents
git commit -m "feat(code): 增加自定义 Agent 解析与内置 Agent"
```

---

### Task 4: `spawn_agent` 支持自定义 Agent

**Files:**
- Modify: `packages/conatus_agent/lib/src/sub_agent.dart`
- Create: `packages/conatus_agent/lib/src/sub_agent_profile.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`（注入 resolver）
- Test: `packages/conatus_agent/test/sub_agent_agent_profile_test.dart`
- Test: `packages/conatus_code/test/agents/spawn_agent_assembly_test.dart`

**Interfaces:**
- Consumes: B Task 3 `AgentRegistry`；A Task 1–3 `PermissionRule` / `PermissionScope`。
- `class SubAgentProfile { final String id; final String system; final int? steps; final List<String>? tools; final List<PermissionRule> permissions; final LlmProvider? llm; }`
- `abstract class SubAgentProfileResolver { Future<SubAgentProfile?> resolve(String agentId); }`
- `SpawnAgentTool` 新增构造参数 `profileResolver`；`params` 新增 `ParamSpec.string('agent')`。
- `provideSpawnAgent` 新增 `SubAgentProfileResolver? profileResolver`。

- [ ] **Step 1: Write the failing tests**

```dart
test('agent param applies profile tools, steps and system prompt', () async {
  final tool = SpawnAgentTool(host: ctx, llm: fakeLlm, tools: registry,
      profileResolver: FakeResolver(SubAgentProfile(
        id: 'reviewer', system: 'REVIEW ONLY', steps: 3,
        tools: ['read_file'], permissions: [denyEditRule], llm: null)));
  final result = await tool.call(ToolContext(const ToolCall(name: 'spawn_agent', arguments: {
    'task': 'review', 'agent': 'reviewer',
  })));
  expect(result.isError, isFalse);
  expect(fakeLlm.systemPrompts.single, contains('REVIEW ONLY'));
  expect(fakeLlm.maxSteps.single, 3);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_agent && dart test test/sub_agent_agent_profile_test.dart`
Expected: FAIL — `SubAgentProfile` not defined.

- [ ] **Step 3: Implement**

- `call` 读取 `agent`；有值时 `await resolver.resolve(id)`，空则按现状。
- 白名单取 `requested ∩ profile.tools ∩ 非 high`；`maxRounds = profile.steps ?? 当前`；`subAgentPrompt = profile.system`；`permissionMode` 从 profile 规则转成子 scope（与 A 组 `PermissionScope` 对接）。
- `llm = profile.llm ?? childLlm?.call(llm) ?? llm`。
- 未知 agent：返回失败 `UNKNOWN_AGENT`，不静默降级。
- nava 侧 resolver 从 `AgentRegistry` + `ProviderRegistry.buildLlm` 构造 profile；`plan`/`explore` 的规则原样带入。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_agent && dart test test/sub_agent_agent_profile_test.dart`
Run: `cd packages/conatus_code && dart test test/agents/spawn_agent_assembly_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_agent/lib/src/sub_agent.dart packages/conatus_agent/lib/src/sub_agent_profile.dart packages/conatus_agent/lib/conatus_agent.dart packages/conatus_code/lib/src/tui/tui_app.dart packages/conatus_code/test/agents/spawn_agent_assembly_test.dart packages/conatus_agent/test/sub_agent_agent_profile_test.dart
git commit -m "feat(agent): spawn_agent 支持自定义 Agent 配置"
```

---

### Task 5: 命令分发、Agent/Model 覆盖与菜单

**Files:**
- Create: `packages/conatus_code/lib/src/commands/command_dispatcher.dart`
- Create: `packages/conatus_code/lib/src/agents/agent_picker.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Test: `packages/conatus_code/test/commands/command_dispatch_test.dart`
- Test: `packages/conatus_code/test/tui/tui_custom_command_test.dart`
- Test: `packages/conatus_code/test/tui/tui_agent_picker_test.dart`

**Interfaces:**
- `class CommandDispatcher { CommandDispatcher({required CommandRegistry registry, required AgentRegistry agents, required ProviderRegistry? providers}); Future<String> expand(CommandDefinition def, String args); }`
- 控制器：`Future<bool> runCustomCommand(String name, String args)`、`Future<bool> switchAgent(String id)`。
- `AgentPicker` 列出 `visible` 的 primary/all Agent；`/agents` 打开，选择后切换并重建 AgentLoop。
- `TuiCommand` 动态列表包含自定义命令（`agent`/`model` 信息进 description）。

- [ ] **Step 1: Write the failing test**

```dart
test('/review dispatches template with args', () async {
  await controller.handleLine('/review src/a.dart');
  expect(controller.transcript.messages.last.text, contains('src/a.dart'));
});

test('built-in commands cannot be overridden', () async {
  // .nava/commands/exit.md
  await controller.handleLine('/exit');
  expect(controller.exited, isTrue); // 不是执行自定义 exit
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/commands/command_dispatch_test.dart`
Expected: FAIL — custom command not dispatched.

- [ ] **Step 3: Implement**

- `_handleCommand` 先匹配内置；未命中再查 `CommandRegistry`；未知仍走现有提示。
- `expand` 后若 `def.agent != null`：切换会话 agent（B3/B4）；若 `def.model != null`：`providers.buildLlm` + `switchLlm` + `rebind`，记录 `_commandModelRestore`，在 `_afterTurn` 恢复。
- `subagent: true`：调用 `spawn_agent` 前台执行，结果写入 transcript；不并发。
- 菜单合并静态 + 技能 + 自定义命令；内置在前。
- `/agents` 打开 `AgentPicker`；选择后 `switchAgent` 重建 system prompt/model/权限，`plan` 同时进入 Plan Mode。
- `.opencode` 命令只读；不写任何文件。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/commands test/tui/tui_custom_command_test.dart test/tui/tui_agent_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/commands packages/conatus_code/lib/src/tui packages/conatus_code/test/commands packages/conatus_code/test/tui/tui_custom_command_test.dart
git commit -m "feat(code): 自定义命令接入 TUI 与 Agent/Model 覆盖"
```

---

### Task 6: AGENTS.md 层级 + `instructions`

**Files:**
- Create: `packages/conatus_code/lib/src/instructions/instruction_loader.dart`
- Create: `packages/conatus_code/lib/src/instructions/instruction_source.dart`
- Modify: `packages/conatus_code/lib/src/tui/project_context.dart`（保留 `loadProjectContext` 作为 `InstructionLoader` 的薄包装，避免现有调用/测试断裂）
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Test: `packages/conatus_code/test/instructions/instruction_loader_test.dart`
- Test: `packages/conatus_code/test/tui/project_context_test.dart`（迁移/补充）

**Interfaces:**
- `class InstructionLoader { InstructionLoader({required String workdir, String? home, List<String> extra = const []}); Future<String?> compose(); Future<void> notePath(String path); void dispose(); }`
- `ConatusCodeConfig.instructions`（顶层 `List<String>`）
- 服务键 `'instructions'`；`tui_app` 的 `project` PromptSection 改为 `text: loader.compose`（每次 assemble 调用，不是启动快照）。

- [ ] **Step 1: Write the failing tests**

```dart
test('loads global, upward and nested AGENTS.md in order', () async {
  final text = await loader.compose();
  expect(text, contains('GLOBAL'));
  expect(text.indexOf('ROOT'), lessThan(text.indexOf('NESTED')));
});

test('symlink outside workdir is ignored', () async {
  // AGENTS.md -> ../secret
  expect(await loader.compose(), isNull);
});

test('instructions glob and URL are appended after AGENTS', () async {
  final text = await loader.compose();
  expect(text, contains('CONTRIBUTING'));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/instructions`
Expected: FAIL — `InstructionLoader` not defined.

- [ ] **Step 3: Implement**

- 全局 `~/.nava/AGENTS.md`，其次 `~/.config/opencode/AGENTS.md`（只读兼容）。
- 项目：从 workdir 向上到 git 根（无 git 到 home），由远及近加载 `AGENTS.md` / `NAVA.md`。
- 嵌套：`notePath` 从目标路径向上到 workdir，加载未读过的 `AGENTS.md`，最近优先；`tui_app` 挂一个工具后置中间件，对 `read_file`/`list_files`/`rg`/`glob` 调 `notePath`。
- `instructions`：路径/glob/URL；URL 5s 超时；失败跳过；单文件 16 KiB、总 64 KiB。
- 符号链接：canonical 路径必须在 workdir 内；全局/显式绝对路径例外。
- `.opencode` 只读：只读文件，不写缓存。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/instructions test/tui/project_context_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/instructions packages/conatus_code/lib/src/tui/project_context.dart packages/conatus_code/lib/src/config packages/conatus_code/lib/src/tui/tui_app.dart packages/conatus_code/test/instructions packages/conatus_code/test/tui/project_context_test.dart
git commit -m "feat(code): AGENTS.md 层级加载与 instructions 配置"
```

---

### Task 7: 主题 token 层与 `/theme`

**Files:**
- Create: `packages/conatus_code/lib/src/tui/theme/nava_palette.dart`
- Create: `packages/conatus_code/lib/src/tui/theme/nava_theme.dart`
- Create: `packages/conatus_code/lib/src/tui/theme/theme_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_chrome.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_views.dart`
- Modify: `tui_chrome.dart`、`tui_views.dart`、`tui.dart`、`tui_form_view.dart`、`tui_plan_view.dart`、`tui_command_menu_view.dart`、`tui_permission_view.dart`、`at_ref_menu_view.dart`、`tui_session_picker_view.dart`、`tui_provider_view.dart`、`tui_choice_view.dart`、`tui_model_view.dart`、`team_views.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Test: `packages/conatus_code/test/tui/theme_test.dart`

**Interfaces:**
- `class NavaPalette { final Color text, muted, faint, accent, success, warning, error, border, panel, selected, selectedText, inputBorder, shellBorder, background; final Map<String, Color> message; }`
- `class NavaTheme { static NavaPalette get palette; static List<String> get names; static void use(String name); }`
- `TuiConfig { String theme; bool animations; }`，`ConatusCodeConfig.tui`
- 控制器 `void setTheme(String name)`；`/theme` 打开 `ThemeView`。

- [ ] **Step 1: Write the failing test**

```dart
test('default palette preserves current colors', () {
  NavaTheme.use('default');
  expect(NavaTheme.palette.inputBorder, Colors.blue);
  expect(NavaTheme.palette.shellBorder, Colors.magenta);
  expect(NavaTheme.palette.muted, Colors.gray);
});

test('unknown theme falls back to default', () {
  NavaTheme.use('nope');
  expect(NavaTheme.palette.inputBorder, Colors.blue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_code && dart test test/tui/theme_test.dart`
Expected: FAIL — `NavaTheme` not defined.

- [ ] **Step 3: Implement**

- 用 `NavaPalette` 替换 `tui_chrome.dart` / `tui_views.dart` / 各浮层的 `Colors.*` 与 `Color.fromRGB`；默认值逐项等于当前值。
- 内置 `default` / `dark` / `light` / `tokyonight`；`/theme` 用现有 `TuiChoiceView` 模式展示，选择后 `setTheme` + `onChanged`。
- 配置 `[tui] theme`；装配时 `NavaTheme.use(config.tui.theme)`。
- 不引入用户自定义主题 JSON（首版只内置）。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/tui/theme_test.dart test/tui/agent_tui_test.dart`
Expected: PASS；关键屏文案/颜色快照不变。

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/tui packages/conatus_code/lib/src/config packages/conatus_code/test/tui/theme_test.dart
git commit -m "feat(code): 增加 TUI 主题 token 层与 /theme"
```

---

### Task 8: 键位解析与全局 dispatcher

**Files:**
- Create: `packages/conatus_code/lib/src/tui/keymap/key_binding.dart`
- Create: `packages/conatus_code/lib/src/tui/keymap/keymap.dart`
- Create: `packages/conatus_code/lib/src/tui/keymap/keymap_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui.dart`
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Test: `packages/conatus_code/test/tui/keymap_test.dart`
- Test: `packages/conatus_code/test/tui/keymap_dispatch_test.dart`

**Interfaces:**
- `class KeyBinding { final LogicalKey key; final bool ctrl, shift, alt, meta; }`
- `KeyBinding? parseKeyBinding(String text, {LogicalKey? leader})`
- `class Keymap { static Keymap fromConfig(Map<String,String> config); String? actionFor(KeyboardEvent event); }`
- 动作常量：`app.exit` / `app.clear` / `help.show` / `session.new` / `session.list` / `model.list` / `agent.list` / `command.palette` / `tab.next` / `tab.previous`。

- [ ] **Step 1: Write the failing test**

```dart
test('parses ctrl+x and leader combinations', () {
  final k = Keymap.fromConfig({'leader': 'ctrl+x', 'model.list': '<leader>m'});
  expect(k.actionFor(const KeyboardEvent(logicalKey: LogicalKey.keyM, modifiers: ModifierKeys(ctrl: true, meta: false, alt: false, shift: false))), isNull);
  // 先按 leader 再按 m 的两段式由 dispatcher 处理；单键表测试：
  expect(parseKeyBinding('ctrl+m')!.ctrl, isTrue);
});

test('default keymap preserves current exit keys', () {
  final k = Keymap.fromConfig({});
  expect(k.actionFor(const KeyboardEvent(logicalKey: LogicalKey.keyC, modifiers: ModifierKeys(ctrl: true))), 'app.exit');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/tui/keymap_test.dart`
Expected: FAIL — `Keymap` not defined.

- [ ] **Step 3: Implement**

- 解析 `ctrl+/alt+/shift+/meta+`；`<leader>` 展开；未知动作 ID 启动时警告并忽略。
- 首版只接管全局动作：退出、清屏、帮助、新会话、会话列表、模型列表、Agent 列表、命令面板、tab 切换。视图内局部按键（浮层、diff）保持硬编码。
- 默认映射保持现有键：`app.exit=ctrl+c,ctrl+d`；新增 `session.new=ctrl+x,n` 等不冲突组合；不改变 Ctrl+T/Ctrl+O 的现有行为。
- `tui.dart` 的 `_onKey` 开头先问 `Keymap`，未命中再走现有分支；`_onInputKey` 同样只查全局表。
- `/keybinds` 打印当前绑定与冲突。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/tui/keymap_test.dart test/tui/keymap_dispatch_test.dart test/tui/agent_tui_test.dart`
Expected: PASS；现有快捷键不回归。

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/tui/keymap packages/conatus_code/lib/src/tui/tui.dart packages/conatus_code/lib/src/config packages/conatus_code/test/tui/keymap_test.dart packages/conatus_code/test/tui/keymap_dispatch_test.dart
git commit -m "feat(code): 增加可配置键位与全局 dispatcher"
```

---

## 完成标准

- 自定义命令/Agent 可从 `.nava` 与 `.opencode` 读取，nava 优先，`.opencode` 无写入。
- `spawn_agent` 的 `agent` 参数生效，权限只能收紧。
- AGENTS.md 全局/向上/嵌套 + `instructions` 生效，符号链接越界被拒。
- 主题默认渲染不变，`/theme` 可切换；键位默认行为不变，可配置全局动作。
- `cd packages/conatus_skill && dart test`、`cd packages/conatus_code && dart test`、`dart analyze --fatal-infos` 全绿。

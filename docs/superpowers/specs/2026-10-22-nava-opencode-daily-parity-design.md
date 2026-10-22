# 方案：nava 日常体验对齐 OpenCode V2（A → B → C）

> 日期：2026-10-22 · 状态：待评审
>
> 范围：`packages/conatus_code`（nava）；按需触及 `conatus_agent` / `conatus_mcp` /
> `conatus_foundation`。不引入 server / 运行时插件 / 多端架构。
>
> 参考：OpenCode V2 官方文档（CLI / TUI / agents / commands / plugins / tools /
> permissions / policies / snapshots / references / MCP / API / ACP）与本机
> `opencode --help`。仓库既有盘点：
> `docs/superpowers/specs/2026-09-24-conatus-code-feature-gaps-design.md`。

## 1. 目标与成功标准

### 目标

1. 把 OpenCode V2 的**日常高频动作**补齐到 nava，按 A（安全与流程）→ B（自定义）
   → C（会话与生态）推进，共 10 项。
2. 保持 nava 的差异化：单二进制 AOT、OS 沙箱、checkpoint/rewind、故事层、
   Team、Goal/cron/memory、XERJ、`/trace` / `/doctor`。
3. 不为了对齐而引入架构负担：权限引擎下沉只为 headless/未来复用，不做 server。

### 成功标准

- 10 项均可通过用户命令或配置使用，且有单元/集成测试。
- `dart analyze --fatal-infos` 干净；受影响包 `dart test` 全绿；
  `bash tool/build_binary.sh && ./dist/nava --version` 成功。
- 默认配置下行为与当前一致：不配置 `[[permissions]]` / `[formatter]` /
  `[instructions]` / `[tui]` / `[keybinds]` 时不改变既有审批、编辑、上下文行为。
- 现有 142 个测试文件不回归；沙箱、审批、checkpoint 语义不退化。
- **不碰用户的 OpenCode**：含 `.opencode` fixture 的完整会话前后，`.opencode`
  的文件集合、内容哈希、mtime、权限位不变；nava 的所有写回只落在 `~/.nava`
  或用户显式配置的项目数据目录（见 3.2 的写回表）。

### 非目标

- server / HTTP API / SDK / ACP / web / desktop / 共享后台服务。
- TS 插件运行时、运行时自定义工具、Code Mode、browser、worktrees、references。
- policies / managed config / Console / 企业管控。
- 跨平台 OS 沙箱（Linux/Windows）与安装器/自动更新。
- ASR 语音输入（仍暂缓）。

## 2. 决策记录

| 决策点 | 结论 | 理由 |
|---|---|---|
| OpenCode 目录兼容 | **双目录**：原生 `.nava/commands|agents` + 兼容 `.opencode/commands|agents`；项目级优先于全局，nava 优先于 opencode | nava 是**兼容方/访客**：只读取 OpenCode 的文件约定，帮助用户平滑试用；不接管、不迁移、不改写 |
| `.opencode` 写权限 | **严格只读**：项目 `.opencode/**` 与全局 `~/.config/opencode/**` 一律只读；不创建、不修改、不删除、不改权限/时间戳、不写缓存 | 这是用户现有的 OpenCode 配置，nava 只是读取方；任何写入都可能破坏用户的 OpenCode 工作流 |
| undo 粒度 | **按轮**（一个用户 prompt = 一轮），复用 checkpoint；同一轮内单次模型步不单独回滚 | OpenCode 的 `/undo` 也面向“上一条用户消息及其之后”；按步快照成本过高 |
| 权限持久化 | **项目数据目录** `~/.nava/projects/<hash>/permissions.json`（0600），不进仓库；`config.toml` 的 `[[permissions]]` 是只读基线 | 与 session/checkpoint 落盘策略一致，避免本机信任被提交 |
| tabs 语义 | **视图态单活**：tab 保存会话与滚动位置，同一时刻只有一个 tab 在跑；切换时若 busy 先提示 | 避免多 AgentLoop 并发带来的 Context/预算/审批串扰；覆盖日常多任务切换 |
| 配置入口 | 统一 `~/.nava/config.toml`，不引入 `cli.toml` | nava 已有单一配置入口；主题/键位不是 server 配置，放同一文件更简单 |

## 3. 总体架构

### 3.1 模块落点

```
packages/conatus_agent/lib/src/permissions/     # 可复用的权限引擎
  permission_effect.dart
  permission_rule.dart
  permission_decision.dart
  permission_matcher.dart
  permission_engine.dart
  permission_store.dart

packages/conatus_code/lib/src/permissions/      # nava 接线与审批 UI
  permission_config.dart
  permission_wiring.dart
  permission_prompt.dart

packages/conatus_code/lib/src/revert/           # undo / redo
  revert_stage.dart
  revert_service.dart

packages/conatus_code/lib/src/diff/             # /diff
  diff_model.dart
  diff_parser.dart
  diff_source.dart
  diff_line.dart

packages/conatus_code/lib/src/format/           # formatter-on-edit
  formatter_probe.dart
  formatter_service.dart

packages/conatus_code/lib/src/commands/         # 自定义命令
  command_definition.dart
  command_parser.dart
  command_registry.dart
  command_expander.dart

packages/conatus_code/lib/src/agents/           # 自定义 Agent
  agent_definition.dart
  agent_parser.dart
  agent_registry.dart

packages/conatus_code/lib/src/instructions/     # AGENTS.md 层级 + instructions
  instruction_loader.dart
  instruction_source.dart

packages/conatus_code/lib/src/tui/theme/        # 主题 token
  tui_theme.dart
  theme_registry.dart

packages/conatus_code/lib/src/tui/keymap/       # 键位
  key_binding.dart
  keymap.dart

packages/conatus_code/lib/src/tabs/             # 会话 tab
  tab_manager.dart
  tab_bar.dart

packages/conatus_mcp/lib/src/                   # MCP 补全
  mcp_resources.dart
  mcp_prompts.dart
  mcp_oauth.dart
  mcp_oauth_store.dart
```

文件仍遵守仓库硬约束：单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、
参数 ≤ 4 个；超限拆文件并加 `// REASON:`。

### 3.2 `.opencode` 只读闸门与 nava 自己的写回位置

**定位：nava 是 OpenCode 的兼容读取方，不是 `.opencode` 的所有者。**
用户可能同时在用 OpenCode；nava 只读取它认识的命令 / Agent / AGENTS 约定，
绝不把 `.opencode` 当成自己的配置目录或数据目录。

#### 只读的强定义

- 范围：项目 `<workdir>/.opencode/**` 与全局 `~/.config/opencode/**`。
- 不做：创建 / 写入 / 追加 / 删除 / 重命名 / 改权限 / 改时间戳 / 写缓存 /
  写索引 / 写锁文件。
- 读取失败、格式不认识、字段不支持：跳过并在 `/doctor` 或命令输出提示，
  **不尝试修复、迁移或重写**。
- 判定用 canonical path（与 fs jail 同一套规范化），防止 `..`、符号链接绕过。

#### nava 自己的写回位置

| 数据 | 写回位置 |
|---|---|
| 全局配置 / 主题 / 键位 | `~/.nava/config.toml` |
| 项目数据（默认） | `~/.nava/projects/<编码工作区路径>/` |
| 项目数据（显式 `[agent] project_dir`） | `<workdir>/<project_dir>/` |
| 权限“始终允许” | `<项目数据目录>/permissions.json` |
| 会话 / checkpoint / 导出 / story-log | `<项目数据目录>/...` |
| OAuth token | `~/.nava/oauth/<server>.json`（0600） |
| nava 原生命令 / Agent | 用户手写 `.nava/commands` / `.nava/agents`；nava 只读 |
| MCP `nava mcp add` | `~/.nava/config.toml` |

> `.opencode` 不出现在上表任何一行；nava 不在其中保存任何状态。

#### 闸门接入点

- `write_file` / `edit_file` / `apply_patch`：写入前拒绝，返回
  `ToolResult.error('READ_ONLY_PATH: .opencode 目录只读')`，模型可见。
- `story` 待定补丁：拒绝登记目标在保护区的补丁。
- `formatter`：跳过保护区内文件。
- `checkpoint`：加入内置忽略集，不纳入快照/回滚（避免 rewind 写入）。
- 自定义命令 / Agent 发现：只读扫描，不产生任何写操作、不建缓存。
- `config_writer`：只写 `~/.nava/config.toml`；代码层禁止传入 `.opencode` 路径。
- 会话 / 导出 / token：路径解析统一走 nava 的项目数据目录，不读 OpenCode 的路径。

#### 测试

- 每个写入入口单测：目标在保护区内必须失败或跳过。
- 符号链接越界：`<workdir>/.opencode/link -> 外部` 不得被写入。
- **快照测试**：在含 `.opencode` fixture 的临时工作区跑完整会话（读命令 / Agent /
  AGENTS、编辑、checkpoint、formatter、MCP add），断言 `.opencode` 的文件集合、
  内容哈希、mtime、权限位前后完全一致。

### 3.3 权限与审批的单一入口

当前审批在 TUI 层（`TuiPermissionGate implements Approval`），headless 无审批。
新设计：

1. 用 `instrumentPermission` 替换 nava 会话里的 `instrumentApproval`
   （**不是**再叠一层中间件，避免双重弹窗）。
2. **挂载位置是根上下文的最外层**：必须在 hooks / eviction / story / lint 之前
   注册，否则这些中间件可以短路掉工具调用，权限规则永远看不到。控制器不再
   每个会话重挂审批中间件；当前会话/Agent 的规则由 `PermissionScope` 服务槽
   提供，`_bind` 时只更新槽位。
3. 它评估每次工具调用，返回 `allow / ask / deny`：
   - `allow` → `next()`；
   - `ask` → 复用当前 `Approval.request`（TUI 弹层；headless 按 `deny`）；
   - `deny` → 直接返回 `PERMISSION_DENIED` 错误，不进入执行体。
4. 中间件仍打 `kApprovalMiddlewareTag`。子 Agent：`inherit` 复用宿主 scope；
   `readonly` / `ask` / `auto` 按现有逻辑排除宿主中间件，安装子 scope。
5. 没有命中任何显式规则时，退回当前 `[approval] mode` + `ToolRisk` 行为，
   保证零配置完全兼容。
6. 权限引擎不依赖 TUI；未来 server / ACP 可直接复用。

## 4. A 组：安全与流程

### 4.1 权限 v2

#### 规则模型

```dart
enum PermissionEffect { allow, ask, deny }

class PermissionRule {
  const PermissionRule({
    required this.action,
    required this.resource,
    required this.effect,
    this.source,
  });
  final String action;    // read / edit / shell / webfetch / websearch / ...
  final String resource;  // 路径 / 命令 / URL / 查询词 / agent id / skill id
  final PermissionEffect effect;
  final String? source;   // config / project / session
}
```

匹配规则：

- 通配符 `*`（零或多字符，含 `/`）、`?`（单字符），整值匹配。
- shell 规则以 ` *` 结尾时同时匹配无参数形式：`git status *` 覆盖 `git status`。
- 路径先规范化（`~` 展开、`..` 折叠、符号链接 canonical），再匹配。
- 同一组规则**最后匹配的生效**；多个资源同时检查时，任一 `deny` 即拒绝，
  否则任一 `ask` 即询问，否则放行。

#### 动作映射

| 工具 | action | resource |
|---|---|---|
| `read_file` / `list_files` | `read` | 规范化路径 |
| `rg` | `grep` | pattern（不是搜索路径） |
| `glob` | `glob` | pattern |
| `write_file` / `edit_file` / `apply_patch` | `edit` | 每个目标路径 |
| `run_command` / `run_tests` / `run_code` / background | `shell` | 实际命令串 |
| `web_search` | `websearch` | query |
| `fetch_url` | `webfetch` | URL |
| `spawn_agent` | `subagent` | agent id（缺省 `default`） |
| skill 工具 | `skill` | skill id |
| `ask_user` | `question` | `*` |
| MCP 工具 `server__tool` | `<server>_<tool>`（单下划线） | `*` |
| 工作区外路径 | `external_directory` | 目录边界（`.../*`） |

工具通过可选 getter 声明，未声明的按默认推导：

```dart
String get permissionAction => name;
List<String> permissionResources(ToolContext ctx) => const <String>['*'];
```

现有工具逐个补；不补的工具走默认值，不破坏行为。

#### 规则来源与优先级

低 → 高：

1. 内置默认（仅用于把 `.env` 读取映射为 `ask` 等少量基线；可由用户覆盖）。
2. `config.toml` 的 `[[permissions]]`（只读）。
3. 项目持久化 `permissions.json`（“始终允许”写入此处）。
4. 会话级规则（“信任此文件夹”等，切会话清空）。

同一动作/资源按“最后匹配生效”合并；`deny` 永不被 `allow` 覆盖，除非更晚的
规则显式 `allow`（与 OpenCode 一致，便于“全局拒绝 + 局部例外”）。

#### 配置

```toml
[[permissions]]
action = "shell"
resource = "*"
effect = "ask"

[[permissions]]
action = "shell"
resource = "git status *"
effect = "allow"

[[permissions]]
action = "shell"
resource = "git push *"
effect = "deny"

[[permissions]]
action = "edit"
resource = "*.env"
effect = "ask"
```

#### 持久化

`~/.nava/projects/<hash>/permissions.json`：

```json
{
  "version": 1,
  "rules": [
    { "action": "shell", "resource": "git status *", "effect": "allow", "savedAt": "2026-10-22T10:00:00Z" }
  ]
}
```

原子写入（临时文件 + rename），权限 0600；加载失败按空规则处理并在 `/doctor`
提示，不阻塞启动。`PermissionStore` 只接收文件路径，不自己推导项目目录；
路径由 nava 的 `resolveProjectDataDir` 注入，确保只写 nava 自己的位置。

#### 审批 UI

- 弹层展示：工具名、action、resource、命中的规则（含来源）、风险级。
- 选项：允许一次 / 总是允许（展示将要保存的 pattern）/ 信任此文件夹（路径类）/
  拒绝。
- shell 的“总是允许”保存命令前缀；read/edit 保存目录 glob；MCP 保存工具名。
- 拒绝返回 `ToolResult.error`，内容包含规则摘要；模型可据此调整。
- headless：`ask` → `deny`，错误码 `PERMISSION_ASK_UNATTENDED`；`deny` 直接拒绝。

#### 与现有审批模式的关系

- `[approval] mode = "never_ask"`：等价于兜底 `allow *`（显式 `deny` 仍生效）。
- `ask_when_needed`：兜底按风险级（readOnly 放行，medium/high 询问）。
- `always_ask`：兜底全部询问（readOnly 也问）。
- 子 Agent：`SubAgentPermission` 转为规则集，与父规则取交集（只能更严）。

#### 测试

- 匹配器：通配符、大小写、路径规范化、shell 尾随 `*`、多资源 deny 优先。
- 优先级：config < project < session；最后匹配生效。
- 零配置回归：三种 `[approval] mode` 行为与今天一致。
- headless：ask 拒绝、deny 拒绝、allow 放行。
- 持久化：写 0600、原子、损坏文件降级。
- `.opencode` 写入被拒绝。

### 4.2 `/undo` / `/redo`

#### 语义

- `/undo [N]`：回滚最近 N 轮（缺省 1）的文件与对话，并把被撤回的用户 prompt
  放回输入框；不自动重发。
- `/redo`：取消最近一次 staged rollback，恢复文件与原会话。
- 发送新 prompt 视为**提交**当前回滚，清空 stage。
- 粒度按轮；同一轮内的单次工具调用不单独回滚（文档明示）。

#### 状态

```dart
class RevertStage {
  final String originalSessionId;
  final String forkSessionId;
  final int fromTurn;   // undo 前轮次
  final int toTurn;     // 回滚目标轮次
  final String prompt;  // 放回输入框的文本
  final DateTime createdAt;
}
```

仅内存保存；进程退出即失效。stage 存在时，`/undo` 再执行视为新的回滚（覆盖
旧 stage，旧 stage 不可 redo）。

#### `/undo` 流程

1. `await checkpoint.flush()`，确保在途快照完成。
2. 取当前会话检查点列表；目标 `toTurn = max(0, currentTurn - N)`；不存在则报错。
3. 若工作区有用户外部改动（checkpoint 清单哈希与当前文件不一致），先弹确认：
   “回滚会覆盖 N 个文件，继续？”
4. `checkpoint.restoreTo(sessionId, toTurn)` 恢复文件。
5. 用目标检查点的 `lastEventId` 调 `Session.fork`，`SessionStore.adopt`，
   切到 fork 会话。
6. 从原会话事件中取出被撤回的用户消息文本；把最近一条放入输入框（N>1 时
   在系统行提示“另有 N-1 条已撤回”）。
7. 记录 `RevertStage`。

#### `/redo` 流程

1. 无 stage → 提示“没有可重做的回滚”。
2. 用 `checkpoint.restoreTo(originalSessionId, fromTurn)` 恢复文件到 undo 前状态。
3. 切回 `originalSessionId`；清空 stage。
4. 若原会话已被删除/找不到，提示并保留 stage 供排查。

#### 边界

- `[checkpoint] enabled = false`：只 fork 对话，文件不动；提示“checkpoint 已关闭，
  仅回滚对话”。
- 无历史 / `N` 超界：报错，不改任何状态。
- rewind 与 undo 并存：`/rewind` 保留原语义（文件回滚 + 对话 fork，无 redo）；
  `/undo` 是带 stage 的新命令。文档说明差异，暂不合并。
- checkpoint 的 `restoreTo` 需要支持“按 sessionId 恢复”，不依赖 manager 当前
  绑定；`CheckpointStore.restore(sessionId, turn)` 已具备该能力，manager 只需
  暴露包装并串行化。
- 绑定已有会话时用 `bind` 而不是 `reset`：有检查点则接管（`turn = max(turn)`，
  不 `clearSession`），没有才写 turn 0 基线。现有 `reset` 会清空时间线，
  既破坏 `/redo`，也会在 `--session` 恢复时误删历史；本项一并修正。
- `rewind` / `restoreTo` 进入 `_chain` 串行执行，并新增 `flush()` 等待在途快照；
  `/undo` 前先 `flush()`，避免与 `recordTurn` 抢文件。

#### 测试

- 文件 + 对话同时回滚；redo 恢复；新 prompt 提交后 stage 清空。
- N>1、N 超界、无 checkpoint、外部改动确认。
- 中途快照（flush）不交叉。
- 回滚后 `/rewind list` 与对话切点一致。

### 4.3 `/diff`

#### 数据源

| 源 | 数据 | 说明 |
|---|---|---|
| `working` | `git diff --no-ext-diff --unified=3` + untracked 文件内容 | 当前未提交改动 |
| `turn` | 最近一轮 checkpoint 的 manifest + 归档内容 | 非 git 仓库也可用 |
| `branch` | `git diff <base>...HEAD` | 可选，第二期 |

`turn` 源用 `CheckpointManifest.changed/deleted` 取出文件，再从归档读旧内容，
用 LCS 行 diff 生成 hunks；单文件上限 5000 行 / 1 MiB，超限只显示“文件过大，
已省略逐行差异”。

#### 视图

- 左侧文件树（路径、+/- 行数、状态），右侧 unified diff。
- 按键：`j/k` 滚动、`n/p` 文件、`d` 切源、`m` 标记已读、`q` 关闭。
- split view 作为 stretch；首版 unified。
- 只读：不提供 apply/revert 按钮；revert 走 `/undo`。

#### 入口

- `/diff [working|turn|branch]`，缺省 `working`；无 git 时自动退到 `turn`。
- 轮末不自动弹；在状态栏提示 `[diff] 本轮改动 N 个文件`（可关）。

#### 测试

- git / 非 git 两种源；重命名、新增、删除、二进制文件（显示占位）。
- 大文件截断；导航与标记状态；空 diff。
- 确认不产生任何写入。

### 4.4 formatter-on-edit

#### 配置

```toml
[formatter]
enabled = true
# command = "dart format $FILE"   # 覆盖自动探测
# timeout_ms = 10000
# extensions = [".dart", ".md"]  # 仅对指定扩展名启用
```

#### 内置探针

| 语言/文件 | 命令 | 触发条件 |
|---|---|---|
| Dart | `dart format $FILE` | `.dart` 且 `pubspec.yaml` 存在 |
| Go | `gofmt -w $FILE` | `.go` 且 `go.mod` 存在 |
| Rust | `rustfmt $FILE` | `.rs` 且 `Cargo.toml` 存在 |
| JS/TS/JSON/MD | `prettier --write $FILE` | `package.json` 依赖含 `prettier` |
| Python | `ruff format $FILE` | `pyproject.toml` 含 ruff 配置或依赖 |

#### 执行

- 复用 `LinterService` 的模式：`ToolRegistry.use` 后置中间件，监听
  `write_file` / `edit_file` / `apply_patch` 成功结果。
- **formatter 中间件在 linter 之后注册（更内层）**：`ToolRegistry` 的中间件按
  注册顺序包裹、后置代码由内向外执行；这样 formatter 先拿到编辑结果，保证
  先格式化再 lint。
- 命令走 `'shell'` 缝（沙箱）；与 lint 一致。只对本次改动文件执行，最多 20 个。
- 内置命令加入沙箱默认可执行白名单（`dart` / `gofmt` / `rustfmt` / `ruff` /
  经 `npx` 的 `prettier`）；未命中白名单时按 skipped 处理，**不绕过沙箱**。
  自定义 `command` 由用户自行保证可执行，失败只提示。
- 失败/超时/找不到命令：不改变工具结果的成功状态，追加一行
  `[Formatter] skipped: <原因>`；不把 stderr 全量回灌。
- `apply_patch` 多文件逐文件执行；同一文件一次。
- 跳过：`.opencode/**`、工作区外、story 待定补丁（apply 后再格式化）、
  文件已删除。
- 格式化后用文件 mtime/size 更新 checkpoint 变化检测（下一轮快照自然包含）。

#### 测试

- 探测：Dart/Go/Rust/Prettier。
- 成功：内容被格式化，工具结果不变。
- 失败：工具仍成功，追加 skipped。
- 禁用/无探针/保护区/删除文件。
- formatter → lint 顺序。

## 5. B 组：自定义

### 5.1 自定义命令

#### 发现

按优先级从低到高加载，同名后者覆盖前者：

1. `~/.config/opencode/commands/**/*.md`（只读兼容）
2. `~/.nava/commands/**/*.md`
3. `<workdir>/.opencode/commands/**/*.md`（只读兼容）
4. `<workdir>/.nava/commands/**/*.md`

只读 `.opencode`：发现阶段只 `read`/`list`，不创建目录、不写缓存。

#### 格式

```md
---
description: 审查当前改动
agent: plan
model: ark/doubao-seed-2-0-lite
subagent: false
---

审查 $ARGUMENTS，重点看 $1 的错误处理。
```

- `description` / `agent` / `model` / `subagent` 可选。
- 正文是 prompt 模板；`$ARGUMENTS` 为完整参数，`$1..$9` 为分词参数
  （引号分组，缺省为空串）。
- 无占位符时，非空参数追加到模板末尾（空行分隔）。
- `!` + 反引号 shell 块：在提交前执行，输出插入模板；走 `'shell'` 缝，
  受权限规则约束；输出上限 8000 字符。
- 模板本身不展开 `@path`；附件由用户在 composer 添加。

#### 注册与执行

- `CommandRegistry` 合并内置 `tuiCommands` 与自定义命令，`/` 菜单可见。
- `/name args` 未命中内置命令时查注册表；展开后作为用户 prompt 提交。
- `agent` 指定时先切换会话 agent（见 5.2）；`model` 指定时临时构建对应
  LLM 链；`subagent: true` 在本期以**前台子 Agent**执行（阻塞），后台子
  Agent 不在范围。
- 命令执行产生的消息与会话事件与手输 prompt 一致。

#### 测试

- 发现/优先级/嵌套目录 ID。
- 参数展开、引号、缺省空串、无占位符追加。
- shell 块成功/失败/超限；权限拒绝。
- agent/model 覆盖；未知 agent/model 报错。
- `.opencode` 只读（无写入）。

### 5.2 自定义 Agent

#### 发现与格式

目录同命令：`~/.config/opencode/agents`、`~/.nava/agents`、`.opencode/agents`、
`.nava/agents`；嵌套路径成为 ID（`team/reviewer`）。

```md
---
description: 只读代码审查
mode: subagent
model: ark/doubao-seed-2-0-lite
steps: 8
hidden: false
color: "#ff6b6b"
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: read
    resource: "*"
    effect: allow
---

你是只读审查员。按严重程度列出问题，给文件与行号。
```

#### 内置 Agent

| ID | mode | 行为 |
|---|---|---|
| `build` | primary | 当前默认行为，无额外限制 |
| `plan` | primary | 进入 Plan Mode；`edit` 拒绝（计划文件除外） |
| `general` | subagent | 广工具、可写；不能再 spawn 子 Agent |
| `explore` | subagent | 只读：read/grep/glob/web，`edit` 拒绝 |

内置可被同名自定义覆盖；`hidden: true` 不进选择器与子 Agent 目录。

#### 选择与会话绑定

- `[agent] default_agent = "build"` 定新会话默认；`/agents` 浮层切换。
- 会话记录 `agentId`；切换时重建 AgentLoop 的 system prompt / model /
  权限规则；Plan agent 同时切换 Plan Mode。
- 子 Agent：`spawn_agent` 新增 `agent` 参数；未传时用当前 `subagent_permission`
  与默认白名单（保持现状）。
- Agent 的 `model` 用 `ProviderRegistry.buildLlm` 构建；构建失败则报错并
  回退当前模型（在 `/doctor` 提示）。

#### 权限合并

- 全局规则 → agent 规则（追加）→ 会话规则。
- `spawn_agent` 的子 Agent 使用 agent 自身规则；若父级显式传
  `permission_mode`，只能收紧（取交集）。
- `build` 无自定义规则时继承全局；`plan`/`explore` 自带拒绝 `edit`。

#### 测试

- 发现/覆盖/嵌套 ID；mode 过滤；hidden。
- `spawn_agent` 的 agent 参数：工具交集、模型覆盖、步数、权限。
- `/agents` 切换与 Plan Mode 联动。
- 非法 frontmatter / 未知 model 的降级与提示。

### 5.3 AGENTS.md 层级 + instructions

#### 加载顺序

1. 全局：`~/.nava/AGENTS.md`（其次 `~/.config/opencode/AGENTS.md`，只读兼容）。
2. 项目：从工作目录向上到项目根（git 根；无 git 时到 home），由远及近加载
   每级 `AGENTS.md` / `NAVA.md`。
3. 嵌套：读文件/列目录时，加载目标与工作目录之间路径上的 `AGENTS.md`
   （最近优先），每个文件每会话只注入一次。
4. `instructions` 配置：路径 / glob / URL，在 AGENTS 之后按声明顺序加载；
   URL 5 秒超时，失败跳过；glob 新匹配文件在下一次配置变更时出现。

#### 配置

```toml
instructions = [
  "CONTRIBUTING.md",
  "docs/guidelines/*.md",
  "~/rules/nava.md",
  "https://example.com/instructions.md",
]
```

#### 注入

- 合并成一个 `project` prompt section；每轮请求前重建（只做字符串拼接，成本低）。
- 单文件 16 KiB 截断并标注；总注入上限 64 KiB，超出按来源标注省略。
- 去重按 canonical path；符号链接越界（工作区外）不读，除非是显式全局路径或
  `instructions` 中声明的绝对路径。
- `.opencode` 只读：只读取，不写缓存/索引。

#### 测试

- 全局/项目/嵌套顺序；去重。
- 符号链接越界；`NAVA.md` 与 `AGENTS.md` 共存。
- `instructions` 的 glob/URL/超时/缺失。
- 截断与总上限。

### 5.4 主题与键位

#### 主题

新增 `TuiTheme` 语义 token，替换 `tui_chrome.dart` / `transcript.dart` / 各浮层
中的硬编码 `Colors.*`：

```dart
class TuiTheme {
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;
  final Color border;
  final Color background;
  final Color diffAdded;
  final Color diffRemoved;
  final Color diffContext;
}
```

- 内置 4 套：`default`（当前配色，逐像素尽量不变）、`dark`、`light`、
  `tokyonight`。
- 配置 `[tui] theme = "default"`；`/theme` 打开选择浮层，即时切换。
- 首版不支持用户自定义 JSON 主题（降低范围）；只支持内置名与 `default` 回退。

#### 键位

- 新增 `TuiAction` 常量 + `KeyBinding` 解析（`ctrl+x`、`alt+enter`、`shift+tab`、
  `f1`、`<leader>`）。
- `KeyDispatcher` 先接管全局动作：退出、新会话、切会话、切模型、切 Agent、
  命令菜单、帮助、清屏、tab 切换。
- 配置：

```toml
[tui]
theme = "default"

[keybinds]
leader = "ctrl+x"
"app.exit" = "ctrl+c,ctrl+d"
"session.new" = "ctrl+x,n"
"model.list" = "ctrl+x,m"
```

- 未配置时使用现有默认键，行为不变；冲突键启动时 `[keybinds] 冲突` 提示并
  以先声明者为准。
- 视图内局部按键（diff、浮层）首版保持硬编码，后续逐步迁移；文档标注。

#### 测试

- token 解析/回退；默认主题渲染与当前文本快照一致（关键屏）。
- 键位解析、`<leader>`、冲突、禁用。
- 主题切换不破坏布局；`/theme`/`/keybinds` 入口。

## 6. C 组：会话与生态

### 6.1 会话 title / rename / delete / tabs

#### title 与 rename

- `Session` 增加可选 `title`，写入会话元数据；缺省取首条用户消息前 40 字符。
- `/rename <title>`；`/sessions` 列表显示 title + 短 id + 更新时间。
- session picker 支持 `r` 重命名、`d` 删除（二次确认）。
- 兼容旧会话文件：无 title 时惰性派生，不回写旧文件（除非用户 rename）。

#### delete

- 删除会话 JSONL、`sessions/<id>` 相关文件、checkpoint、story-log（若存在）。
- 导出文件保留；在确认框列出将删除的路径类别与数量。
- 当前会话不可删除（先切走）。

#### tabs（视图态单活）

- `TabManager` 保存最多 8 个 `SessionTab {sessionId, title, scrollOffset, planState}`。
- 只有一个 active tab 绑定 AgentLoop；切换时保存当前滚动位置、恢复目标位置。
- 若当前 tab 正在跑，`Ctrl+Tab` 提示“当前会话运行中，Esc 中断后再切换”；
  不并发跑两个会话。
- 快捷键：`ctrl+t` 新建、`ctrl+w` 关闭、`ctrl+tab` / `ctrl+shift+tab` 切换。
- 关闭 tab 不删除会话，仅从 tab 栏移除。
- 首版不做 tab 内后台流式；后续若需要再评估多 AgentLoop。

#### 测试

- title 派生/持久化/旧文件兼容；rename/delete。
- tab 切换保存/恢复滚动；busy 阻止切换；关闭不删会话；上限 8。

### 6.2 MCP 补全

#### resources / prompts

- `conatus_mcp` 协议层新增：
  - `resources/list`、`resources/read`；
  - `prompts/list`、`prompts/get`；
  - 能力协商读取 `capabilities.resources` / `capabilities.prompts`。
- 暴露内置工具：
  - `list_mcp_resources`（可选 `server` 参数）；
  - `read_mcp_resource`（`server` + `uri`）。
- prompts 映射为命令 `/<server>:<prompt>`；参数按顺序填充，支持引号分组。
- 资源内容按 MIME 处理：文本直出，二进制返回占位/大小；单条上限 64 KiB。
- 权限 action：`<server>_list_mcp_resources` / `<server>_read_mcp_resource`，
  资源为 server 名 / `<server>:<uri>`。

#### OAuth

- 远程 HTTP server 默认尝试 OAuth；`oauth = false` 关闭。
- 流程：protected resource metadata → AS metadata → PKCE + DCR（或 CIMD /
  预注册 client）→ loopback 回调（127.0.0.1 随机端口）→ token。
- token 存储：`~/.nava/oauth/<server>.json`，0600；含 access/refresh/expiry。
- 刷新：过期前 60 秒刷新；失败标记 `needs_auth`，`/mcp` 显示可重新登录。
- 日志与错误只输出键名，不输出 token/secret。

#### CLI

```bash
nava mcp add <name> --url https://mcp.example.com/mcp
nava mcp add <name> -- <command> [args...]
nava mcp list
nava mcp auth <name>
nava mcp logout <name>
```

- 在进入 TUI 前解析子命令；`add` 写 `~/.nava/config.toml`（原子、0600），
  不写 `.opencode`。
- `auth` 运行 OAuth 流程并打印结果；`logout` 删除 token 文件。

#### 测试

- 假 MCP server（stdio/HTTP）能力协商、资源读取、prompt 参数。
- 假授权服务器：PKCE、DCR、token 刷新、过期、失败。
- token 文件权限与脱敏；`.opencode` 不被写入。

## 7. 配置变更汇总

```toml
# 权限规则（数组表，按顺序匹配，最后命中生效）
[[permissions]]
action = "shell"
resource = "git push *"
effect = "deny"

# formatter-on-edit
[formatter]
enabled = true
# command = "dart format $FILE"
# timeout_ms = 10000

# 额外指令文件
instructions = ["CONTRIBUTING.md", "docs/guidelines/*.md"]

# Agent 默认
[agent]
default_agent = "build"

# 主题与键位
[tui]
theme = "default"

[keybinds]
leader = "ctrl+x"
"app.exit" = "ctrl+c,ctrl+d"
```

- 所有新增字段可选；缺省值保持当前行为。
- `ConfigParser` 新增 `_readPermissions` / `_readFormatter` / `_readInstructions` /
  `_readTui` / `_readKeybinds`；非法值抛 `ConfigException`，指明来源。
- 配置模板 `kDefaultConfigToml` 增加注释示例。
- 不新增 `cli.toml`；不迁移现有配置。

## 8. 安全不变量

1. **`.opencode` 严格只读**：不写、不改、不删、不改元数据；checkpoint /
   formatter / story / 工具写入全部绕过或拒绝。nava 的所有持久化只写自己的
   位置（见 3.2 写回表），不借道 OpenCode 的目录。
2. **凭据不落日志**：OAuth token、API Key 只经 `Credentials`；错误只报键名。
3. **沙箱不退化**：格式化/命令仍走 `'shell'` 缝；新增能力不直接 `Process.run`
   绕过 CommandPolicy（lint 已是例外，formatter 沿用其路径并记录）。
4. **符号链接**：AGENTS/instructions/permissions 路径规范化后再判定包含关系。
5. **deny 不可被 UI 绕过**：审批弹层的“总是允许”不能覆盖显式 `deny`。
6. **headless fail-closed**：`ask` 在无人值守时按拒绝处理。

## 9. 测试策略

| 层 | 覆盖 |
|---|---|
| 单元 | 权限匹配/优先级、diff 解析、formatter 探测、命令/Agent 解析、instructions 顺序、主题/keymap |
| 集成 | 权限 deny 阻止工具、undo/redo 文件+对话、自定义命令/Agent 走完整 AgentLoop、AGENTS 注入、MCP 假 server |
| 回归 | 零配置下三种审批模式、现有 `/rewind`、lint、story、sandbox、headless |
| 安全 | `.opencode` 每个写入入口、符号链接越界、token 脱敏、headless ask→deny |
| 构建 | `dart analyze --fatal-infos`、受影响包 `dart test`、`tool/build_binary.sh` |

新增测试文件按功能命名，放对应包 `test/`；不引入 mock 框架，沿用 Fake/脚本化替身。

## 10. 实施顺序与验收

| 阶段 | 项 | 依赖 | 验收 |
|---|---|---|---|
| A1 | 权限 v2 | 无 | 规则命中/拒绝/持久化；零配置回归 |
| A2 | undo / redo | checkpoint | 文件+对话回滚、redo、提交 |
| A3 | `/diff` | checkpoint | git/非 git、导航、只读 |
| A4 | formatter | shell/lint 模式 | 成功/失败/跳过/顺序 |
| B3 | AGENTS.md + instructions | 无 | 层级/嵌套/越界/URL |
| B1 | 自定义命令 | A1 | 发现/参数/shell/agent/model |
| B2 | 自定义 Agent | A1/B1 | 发现/mode/权限/模型/spawn |
| B4 | 主题/键位 | 无 | 默认不变、切换、冲突 |
| C1 | title/rename/delete/tabs | B4 | 持久化、删除、tab 切换 |
| C2 | MCP 补全 | 无 | 资源/prompt/OAuth/CLI |

每个阶段结束：实现 + 测试 + README/配置模板/CHANGELOG 更新 + 提交推送；
阶段之间不混入无关重构。

## 11. 风险与实现默认值

| 风险 | 缓解 |
|---|---|
| 权限与现有风险级双重拦截，出现两次弹窗 | 引擎先判定；仅“无规则命中”时回退风险级；加零配置回归测试 |
| undo 与在途 checkpoint 竞争 | `flush()` 串行化；undo 前等待；测试覆盖 |
| 非 git 仓库的 `/diff` 行级差异成本高 | 单文件 5000 行 / 1 MiB 上限；超限只显示文件级 |
| 主题替换触及大量 TUI 文件，视觉回归 | 默认主题保持当前 ANSI；关键屏文本快照；分文件迁移 |
| 键位重构破坏现有快捷键 | 首版只接管全局动作；视图局部保持硬编码；默认键不变 |
| tabs 多会话 Context 隔离 | 单活视图态，不并发；每 tab 复用现有 per-session Context |
| OAuth 实现面大 | 先支持 PKCE + DCR；CIMD/预注册 client 作为可选；假 AS 测试 |
| `.opencode` 只读闸门漏入口 | 统一 guard + 每个写入入口单测；代码审查清单 |

### 实现默认值（不阻塞；如需调整在实现前提出）

1. 自定义命令的 `subagent: true` 首版按**前台阻塞**执行；后台子 Agent 需要
   `conatus_agent` 新能力，另立 spec。
2. `[tui]` 与 `[keybinds]` 放 `config.toml`，不新增 `cli.toml`。
3. `/undo N`（N>1）时输入框只放最近一条被撤回 prompt，其余以系统行提示。
4. `.opencode` 只读是**不可协商**的硬约束，不存在“允许写入”的配置开关。

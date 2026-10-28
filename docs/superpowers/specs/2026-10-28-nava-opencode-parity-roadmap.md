# nava × OpenCode 对齐路线图

> 记录 nava 继续对齐 OpenCode 的分阶段计划。每个阶段独立交付、独立验收，按 P0 → P1 → P2 顺序推进。

## 1. 当前已对齐

已经完成的部分（不再重复设计）：

- 项目注册表：`~/.nava/projects.db` + `~/.nava/workspaces/<basename>-<hash>/`
- 项目列表、重命名、切换（`/project list|open|rename`）
- 项目修复（`workspace.json` sidecar + `nava project repair`）
- OpenCode 配置导入：agents / commands / MCP / permissions / instructions / references
- 技能、`$N` 引用、`.mcp.json`、Claude Desktop MCP、`***` patch、图片/PDF
- 终端 TUI：标签、状态栏、会话面板、Plan Mode、团队视图
- 权限分级、审批、检查点、回滚、压缩、cron、后台任务

## 2. 优先级

| 优先级 | 阶段 | 价值 | 成本 |
|---|---|---|---|
| P0 | LSP 核心闭环 | 编码质量：真实类型错误、诊断进 Agent Loop | 中高 |
| P1 | LSP 导航能力 | hover / definition / references | 中 |
| P1.5 | Web 工具对齐 | fetch markdown/format、搜索 provider 选择 | 低中 |
| P2 | git worktree 管理 | 创建/删除/切换隔离工作树 | 中 |
| P3 | 项目 UX 收尾 | 图标、最近项目、归档/清理 | 低 |
| P4 | 插件系统 | 通用 JS/脚本插件运行时 | 很高 |
| P5 | 跨平台可靠性 | Linux bubblewrap、Windows SQLite | 中 |

---

## P0：LSP 核心闭环

### 目标

让 nava 能启动语言服务器，把 diagnostics 交给模型和用户；编辑文件后能自动获得真实类型错误。

### 范围

1. **配置**
   ```toml
   [lsp]
   enabled = true

   [lsp.servers.dart]
   command = ["dart", "language-server"]
   extensions = [".dart"]

   [lsp.servers.custom]
   command = ["custom-lsp", "--stdio"]
   extensions = [".custom"]
   # env / initialization 可选
   ```

   - `[lsp] enabled = false` 为默认；未配置服务器时不启动。
   - 服务器名唯一；一个服务器按需启动一次。
   - `command` 必须是数组，不经过 shell。
   - `env` 覆盖子进程环境；`initialization` 原样作为 `initialize.initializationOptions`。

2. **LSP 客户端**
   - stdio + JSON-RPC 2.0；Content-Length framing。
   - 生命周期：lazy start → initialize → initialized → didOpen/didChange/didSave → publishDiagnostics → shutdown/exit。
   - 文件 URI 使用 `file://`；workspace root 用当前 worktree 根。
   - 只实现 P0 需要的能力：
     - `textDocument/publishDiagnostics`
     - `textDocument/didOpen`
     - `textDocument/didChange`
     - `textDocument/didSave`
     - `workspace/configuration`（返回空数组即可，不能挂）
   - 超时与失败：启动/初始化超时（5s）、请求超时（10s）；失败只提示，不阻塞 Agent Loop。
   - 进程退出/崩溃：标记 server unavailable，下一轮可重启；不无限重试。

3. **工具与 Agent 集成**
   - 新增 `lsp_diagnostics` 工具：参数 `path?` / `severity?`，返回诊断列表。
   - 编辑类工具（`write_file` / `edit_file` / `apply_patch`）成功后，若该文件有 LSP 覆盖，收集 diagnostics 并附在工具结果末尾（限制条数与字符数）。
   - 诊断格式：
     ```text
     path:line:column severity code message
     ```
   - 没有 LSP 或服务器不可用时，工具返回明确提示，不影响原操作。

4. **TUI**
   - 状态栏可选显示 LSP 状态（`lsp: dart` / `lsp: off`）；P0 先不做面板。
   - `/lsp` 命令：列出已配置服务器、运行状态、错误；支持 `/lsp restart [name]`。

### 非目标

- 不做内置服务器自动安装（OpenCode 的 auto-install 不在 P0）。
- 不做 hover/definition/references（P1）。
- 不做代码补全、格式化、code action。
- 不把 LSP 请求暴露成可配置审批工具。

### 配置导入

`nava import opencode` 的 `lsp` 从“暂不支持”改为：

- OpenCode `lsp: true` → 只导入 nava 已知的内置服务器（先支持 dart）。
- OpenCode 对象形式的服务器 → 映射为 `[lsp.servers.*]`。
- 未知字段告警，不阻塞。

### 测试

- 用测试用 fake LSP server（Dart 或 Python 脚本）验证：
  - initialize / didOpen / publishDiagnostics 全链路
  - diagnostics 进入工具结果
  - 编辑后自动诊断
  - 服务器启动失败 / 初始化超时 / 崩溃后 fail-open
  - 未配置 LSP 时零副作用
- 配置解析测试：`command` 数组、`env`、`initialization`、禁用。
- `nava import opencode` 的 lsp 映射测试。

### 验收

- 在 nava 仓库内配置 dart LSP 后，故意写一个类型错误，编辑结果能看到诊断。
- 未安装 `dart language-server` 时启动不崩溃，只提示不可用。
- Agent 使用 `lsp_diagnostics` 能拿到同一份诊断。

### 风险

- LSP 服务器可能占内存/卡住；必须有超时和 kill。
- 语言服务器版本差异；诊断只作为附加信息，不改变工具成败。
- LSP 命令是本地进程，绕过工具审批；只允许用户显式配置，不从模型输入动态生成。

---

## P1：LSP 导航

在 P0 客户端稳定后增加：

- `lsp_hover`
- `lsp_definition`
- `lsp_references`
- `lsp_document_symbols`
- TUI `/lsp` 输出扩展：能力列表、最近错误

验收：Dart/TypeScript 项目里能定位定义、查引用；服务器不支持时返回明确 unsupported。

---

## P1.5：Web 工具对齐

nava 已有 `web_search` / `fetch_url`，本阶段只补 OpenCode 的高价值差距，不重写工具层。

### 范围

1. `fetch_url` 增加 `format = text | markdown | html`，默认 markdown。
   - text：现有剥标签行为。
   - markdown：HTML → Markdown。
   - html：保留 HTML。
   - 增加响应体硬上限与重定向次数上限。
2. `web_search` 增加 `provider` 参数。
   - 显式 provider 失败时不回退；未指定时沿用现有回退链。
   - provider 失败记录 cooldown，短时间内不再优先尝试。
3. `/search` 或 `/web` 状态命令，展示 provider 可用性与最近错误。
4. `fetch_url` 的 URL/域名权限单独做安全设计，不在本阶段直接放开。

### 非目标

- 不引入 OpenCode 的 Effect/TypeScript 运行时。
- 不照搬 provider 实现；优先复用 nava 已有 `SearchProvider` / `WebFetcher` 缝。
- 不默认允许任意 URL 抓取；安全策略另立 spec。

### 验收

- 模型可请求 `fetch_url(url, format=markdown)` 并拿到 Markdown。
- `web_search(query, provider="tavily")` 只走指定 provider。
- provider 失败后 cooldown，状态命令可见原因。
- 现有无 Key 源跳过、全源失败提示保持不变。

## P2：git worktree 管理

在现有项目注册表上增加真实 worktree 操作：

- `/worktree new <名字> [branch]`
- `/worktree list`
- `/worktree remove <名字>`
- `nava worktree list|new|remove`（可选）
- SQLite `worktree` 表增加 `strategy` 字段（`git` / null）
- 创建位置：`~/.nava/worktrees/<projectShort>/<name>`（不污染主仓库）
- 与 `/project open` 联动：创建后可立即切换

非目标：不自动安装 git、不管理远程 branch、不自动合并。

验收：同一 remote 创建两个 worktree，各自有独立分支、独立数据目录、项目注册表一行 project、多行 worktree。

---

## P3：项目 UX 收尾

- 项目图标/颜色（`icon_url` / `icon_color` 等价字段）
- 最近项目排序、`/project open` 最近列表
- 项目归档：worktree 路径不存在时标记 archived，而不是直接删除
- `nava project prune`：清理归档项目或孤儿记录
- `/projects` 面板：↑↓ 选择、Enter 打开、r 重命名

验收：删掉一个 worktree 路径后，项目列表显示 archived，可 prune；不会丢其他项目。

---

## P4：插件系统（暂缓）

OpenCode 的 JS 插件运行时能力大、边界复杂。nava 已有 hooks / custom tools / MCP，暂不引入通用插件运行时。

若未来要做，先定义：

- 插件发现目录
- 进程内/子进程模型
- 权限与沙箱
- 工具、事件、UI 扩展点
- 版本与兼容策略

---

## P5：跨平台可靠性

- 真实 Linux 主机验证 bubblewrap 沙箱（当前只有 macOS 参数单测）
- Windows 分发 `sqlite3.dll`，验证项目注册表、MCP、文件工具
- 目标：`nava` 在 macOS/Linux/Windows 三端启动、项目注册表、基础工具可用

---

## 3. 实施顺序

```text
P0 LSP 核心
  ↓
P1 LSP 导航
  ↓
P1.5 Web 工具对齐
  ↓
P2 worktree 管理
  ↓
P3 项目 UX
  ↓
P5 跨平台（可与 P2/P3 并行）
  ↓
P4 插件系统（长期）
```

每个阶段独立写 spec / plan / 测试；不把多个阶段混在一个提交里。每个阶段开始前先清上一阶段 review 留下的 Deferred minors。

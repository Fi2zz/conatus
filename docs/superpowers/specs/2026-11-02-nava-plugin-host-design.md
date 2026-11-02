# 方案：nava 插件宿主（P4.1）

> 日期：2026-11-02 · 状态：已定稿
>
> 范围：`packages/conatus_code`。不引入 Flutter / 多平台构建；macOS 为主要验证平台。
>
> 前置：`2026-10-28-nava-opencode-parity-roadmap.md` 的 P0–P3 已完成，P5 按
> 「不做多平台」关闭。P4 拆为 P4.1（本 spec）、P4.2（配置与生态完整度）、
> P4.3（高级 hook 与 UI）。

## 1. 背景与目标

OpenCode 的插件是运行时 JS/TS 模块：V1 导出函数返回 hooks 对象，V2 导出
`{ id, setup }`，通过 `ctx.skill.transform()`、`ctx.session.hook("context")`
等域扩展宿主。nava 是 AOT 编译的 Dart 二进制，不能直接执行 JS；现有
`docs/plugin-integration.md` 只提供技能 / MCP / hooks / `[[tools]]` 的声明式映射。

目标：让 nava 能运行常见 OpenCode 插件，优先覆盖生态里真实使用的形态：
superpowers（技能 + 上下文注入）、notification（事件）、env-protection
（工具前置拦截）、custom-tools（自定义工具）。

### 成功标准

- `nava plugin add <本地目录|npm/git spec>` 后，重启 nava 能加载插件。
- 项目 `.opencode/plugins/` 与 `opencode.json(c)` 的 `plugins` 自动发现，首次
  加载前询问；拒绝则完全不执行。
- 插件注册的技能进 nava 技能目录；自定义工具可被模型调用。
- `tool.execute.before` 能拒绝，`tool.execute.after` 能改结果。
- `event` hook 能收到 `session.idle` / `tool.execute.*` / `file.edited`。
- `shell.env` 能影响模型发起的 bash 命令环境。
- 没有 `node` 时 nava 正常启动，只提示一次插件不可用。
- `.opencode` 的文件集合、内容、mtime、权限位不变。
- `dart analyze --fatal-infos` + 全量测试 + 重新构建 `dist/nava`。

### 非目标（P4.1）

- 不实现 OpenCode 的 TUI/GUI/rpc/server SDK 域。
- 不实现 `command` / `agent` / `mcp` 的 config 注入（P4.2）。
- 不实现 compaction、chat params/headers、permission hook（P4.2）。
- 不实现插件的热重载、`check` / `update`（P4.2）。
- 不支持 TypeScript 文件的即时编译；`.ts` 插件只提示需要转成 `.js` 或用 `bun`。

## 2. 关键决策

| 决策点 | 结论 | 理由 |
|---|---|---|
| 运行时 | 单个长期 Node supervisor 子进程，JSON-RPC over stdio | 插件状态跨轮保留；与 OpenCode PluginSupervisor 同构；崩溃可整体重启 |
| Node 缺失 | 插件整体跳过，stderr 提示一次 | 保持单二进制默认体验；插件是可选能力 |
| 宿主代码 | 内嵌为 Dart 常量，首次使用写到 `~/.nava/plugins/host-<hash>.mjs` | 不引入额外 npm 依赖；单二进制可分发 |
| 包安装 | `nava plugin add` 优先 `bun add`，否则 `npm install --prefix ~/.nava/plugins` | 与 OpenCode 的 Bun 安装行为接近；Node 环境通常自带 npm |
| 项目插件 | 自动发现 + 首次审批；信任记录按内容指纹失效 | 用户选择；兼顾迁移与「克隆不等于执行」 |
| 全局插件 | `~/.nava/config.toml` 的 `[[plugins]]` 默认信任 | 用户显式配置 |
| headless | 默认拒绝项目插件，除非 `--trust-plugins` 或 `trust_project_plugins = true` | 无交互不能弹审批 |
| hook 失败 | 默认 fail-open；`tool.execute.before` 抛错视为拒绝 | 与 OpenCode 语义一致，不阻塞主流程 |
| 超时 | init 10s；普通 hook 5s；工具执行使用工具自身超时 | 防止插件卡死 Agent Loop |

## 3. 架构

```
bin / TuiApp
  └─ PluginService (Dart, 服务键 'plugins')
       ├─ PluginConfig / PluginDiscovery / PluginTrust
       ├─ PluginInstaller (bun/npm)
       └─ PluginHost
            └─ node ~/.nava/plugins/host-<hash>.mjs
                 ├─ 加载 [[plugins]] 与项目插件
                 ├─ V1 导出函数 → hooks 对象
                 └─ V2 default.setup(ctx) → 域调用
```

### 3.1 Dart 模块

| 文件 | 职责 |
|---|---|
| `lib/src/plugins/plugin_types.dart` | `PluginSpec` / `PluginCandidate` / `PluginInitResult` / hook 名称常量 |
| `lib/src/plugins/plugin_config.dart` | `[[plugins]]` 解析与序列化 |
| `lib/src/plugins/plugin_discovery.dart` | 项目 `.opencode/plugins/**` 与 `opencode.json(c)` 的发现 |
| `lib/src/plugins/plugin_trust.dart` | 信任记录、内容指纹、过期判定 |
| `lib/src/plugins/plugin_installer.dart` | `bun` / `npm` 安装、卸载、本地目录解析 |
| `lib/src/plugins/plugin_protocol.dart` | JSON-RPC 编解码、请求超时、错误映射 |
| `lib/src/plugins/plugin_host.dart` | Node 进程生命周期、stdout/stderr、崩溃与重启 |
| `lib/src/plugins/plugin_host_source.dart` | 内嵌宿主脚本（raw string） |
| `lib/src/plugins/plugin_service.dart` | 装配：技能根、工具注册、工具中间件、事件、上下文、shell env |
| `lib/src/plugins/plugin_cli.dart` | `nava plugin add|list|remove` |

### 3.2 宿主协议

stdout 只走协议；插件的 `console.*` 重定向到 stderr。

- Dart → 宿主请求：`init`、`hook`、`tool.execute`、`shutdown`
- 宿主 → Dart 请求：`tool.register`、`skill.register`、`log`
- 宿主 → Dart 通知：`event`
- `init` 参数：`cwd`、`worktree`、`plugins[]`（`id` / `source` / `options` /
  解析后的入口路径或包名）、`hostVersion`
- `init` 结果：`skills[]`、`skillRoots[]`、`tools[]`、`hooks[]`、`context`、
  `shellEnv`、`warnings[]`

JSON-RPC 2.0，一行一条 JSON。请求 id 为整数或字符串；超时后丢弃迟到响应。

### 3.3 插件加载

- 本地目录：`package.json` 的 `main` / `exports` 或 `index.js` / `index.mjs`；
  按 ESM 动态 `import()`。
- npm/git 包：Node 从 `~/.nava/plugins/node_modules` 解析。
- V1：模块的命名导出函数与 `default` 函数逐个调用，参数为
  `{ project, directory, worktree, client, $, options }`，合并返回的 hooks。
- V2：`default.setup` 存在时优先调用，参数为兼容 `ctx`：
  - `ctx.skill.transform(fn)`：draft 提供 `list/add/update/remove`；
  - `ctx.session.hook("context", fn)`：保存并在初始化后调用一次；
  - `ctx.tool.transform(fn)`：P4.1 只接受 `add`，映射到自定义工具；
  - `ctx.log` / `ctx.options`；
  - 未实现的域返回一个惰性对象，调用时记录 warning，不抛。
- 同一插件内 V1 与 V2 只执行一种：有 `default.setup` 走 V2，否则走 V1；
  `SuperpowersPlugin` 这类同时提供两者的包由 V2 路径服务。

### 3.4 hook 映射

| OpenCode hook | nava 接线 |
|---|---|
| `config`（V1） | 只读取 `config.skills.paths` 作为技能根；其余键 warning |
| `ctx.skill.transform`（V2） | 收集 `add/update/remove` 后的技能列表，注册到 nava 技能库 |
| `tool`（V1） / `ctx.tool.transform`（V2） | `ctx.tools.register`；Zod schema 转常见 JSON Schema，失败退化为宽松 object |
| `tool.execute.before` | `tools.use` 中间件；抛错 → 拒绝。P4.1 **不替换参数**：现有中间件合约的 `next()` 绑定原 `ToolCall`，替换需改框架管线（P4.2） |
| `tool.execute.after` | 同上；返回的 `output.output` / `metadata` 可改结果 |
| `event` | nava 事件总线通知；P4.1 发 `session.created` / `session.idle` / `session.error` / `tool.execute.before` / `tool.execute.after` / `file.edited` |
| `shell.env` | 初始化时调用一次，合并进 bash 的 `ShellExecRequest.env` |
| `experimental.chat.messages.transform` | P4.1 以合成消息调用一次，取追加文本进 prompt；失败 fail-open |
| `ctx.session.hook("context")` | 初始化后调用，取返回文本进 system prompt 段 |
| `experimental.session.compacting` | 不接线（P4.2） |
| `permission.*` / `chat.*` / `tui.*` | 不接线（P4.2/P4.3） |

### 3.5 工具 schema

V1 `tool()` 返回的 `args` 是 Zod schema。宿主按以下顺序尝试：

1. 若 `args` 已是 JSON Schema（有 `type`），直接使用；
2. 若 Zod 对象有 `shape`，逐字段读取 `_def.typeName` 映射 string/number/boolean/
   array/object/enum/optional/default；未知类型退化为 `{}`；
3. 失败则 `{ "type": "object", "additionalProperties": true }`。

不追求 Zod 全量语义；参数校验仍由插件 `execute` 自己承担。

### 3.6 生命周期与错误

- `PluginService.start()` 在 `provideTools` / 权限 / shell 之后、技能装配之前。
- 启动失败（无 Node / init 超时 / 全部插件失败）：记录 warning，服务保留为
  no-op；不抛异常，不阻塞 TUI。
- 单个插件加载失败：跳过该插件，其余继续；`/doctor` 与启动提示可见。
- 宿主崩溃：标记 unavailable，当前轮 fail-open；下一轮首次 hook 时按 1s/5s
  退避最多重启 2 次。
- `close()` 发送 `shutdown`，2s 后强杀；随根 Context dispose。

### 3.7 发现与信任

项目候选：

- `<workdir>/.opencode/plugins/*.{js,mjs,cjs}`；
- `<workdir>/.opencode/plugins/*/`（含 `package.json` 或 `index.js`）；
- `<workdir>/opencode.json(c)` 与 `<workdir>/.opencode/opencode.json(c)` 的
  `plugins`（字符串或 `{package, options}`）。

全局候选：

- `~/.nava/config.toml` 的 `[[plugins]]`。

信任：

- 项目候选在首次加载前询问：`always` / `once` / `deny`；默认 deny。
- 记录写入 `$baseDir/plugin-trust.json`（0600）：
  `{ "<key>": { "fingerprint": "...", "approvedAt": "..." } }`。
- 指纹：本地目录取入口文件 + `package.json` 的内容 SHA-256；包取
  `name@version`。指纹变化重新询问。
- 交互模式在 TUI 启动前用一行 stdin 提示；测试注入 `PluginTrustPrompter`。
- headless 默认 deny；`--trust-plugins` 或 `trust_project_plugins = true`
  视为 always（不写记录）。

### 3.8 CLI 与导入

- `nava plugin add <spec>`：本地路径直接写配置；包 spec 安装到
  `~/.nava/plugins`，再写 `[[plugins]]`。
- `nava plugin list`：全局配置项 + 项目候选 + 安装状态。
- `nava plugin remove <spec>`：移除配置项；`--purge` 同时卸载包。
- `nava plugin check|update`：P4.1 打印「P4.2 再实现」。
- `nava import opencode`：`plugins` 从 warning 改为映射为 `[[plugins]]`；
  相对路径按配置文件目录解析，包 spec 原样保留。

## 4. 配置

```toml
# 全局插件；默认信任
[[plugins]]
source = "superpowers@git+https://github.com/obra/superpowers.git"
# enabled = true
# options = { agent = "reviewer" }

[[plugins]]
source = "./my-plugin"

# 项目插件自动发现后的默认策略；headless 下仍默认拒绝
trust_project_plugins = false
```

`[[plugins]]` 与 `[[permissions]]` 一样是 array-of-tables；`source` 必填，
`enabled` 缺省 true，`options` 必须是表。

## 5. 测试

- 单元：配置解析、发现、指纹、信任过期、安装命令选择、JSON-RPC 编解码。
- 集成（Node 可用时）：fixture 插件覆盖 V1 技能根、V2 skill transform、
  自定义工具、before/after、event、shell.env；验证工具结果与 prompt 文本。
- 失败：无 Node、插件抛错、init 超时、宿主崩溃重启、headless 拒绝。
- 安全：`.opencode` 快照（路径/内容/mtime/权限）前后一致。
- 回归：现有 1572 个测试全绿；`dart analyze --fatal-infos`；重建二进制。

## 6. 风险

- OpenCode V2 的 Effect 化域比文档大；P4.1 只覆盖真实插件用到的子集。
- Zod → JSON Schema 不完整，复杂工具参数可能退化。
- Node 版本差异（ESM / fetch）；启动失败按 no-op 处理。
- 插件是任意代码执行；信任提示与内容指纹是唯一防线，文档必须写明。

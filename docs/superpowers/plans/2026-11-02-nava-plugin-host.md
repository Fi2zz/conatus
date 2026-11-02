# nava 插件宿主 P4.1 实施计划

> **状态：已实施（2026-11-02）。** 本文件记录任务拆分、接口与验证命令，供复审与后续 P4.2 使用。
>
> 规格：`docs/superpowers/specs/2026-11-02-nava-plugin-host-design.md`

**Goal:** 用 Node 子进程加载 OpenCode V1/V2 JS 插件，接入技能、工具、hook、事件与 shell env。

**Architecture:** `PluginAssembly` 合并配置插件与项目发现 → 信任审批 → `PluginHost`
（JSON-RPC）→ `PluginService` 注册工具/技能/中间件/事件。

**Tech Stack:** Dart 3.11、Node ESM、JSON-RPC 2.0、package:test。

## Global Constraints

- 不做多平台；macOS 为主要验证平台。
- 无 node 时插件 no-op，不阻塞 TUI。
- `.opencode` 只读；安装/缓存只落 `~/.nava`。
- 插件工具默认 `ToolRisk.high`，进入审批。
- 单文件 ≤ 200 行；新文件按职责拆分。

## Review Focus

- 项目插件首次审批：拒绝后不得执行任何插件代码。
- 插件内容变化：指纹失效并重新询问。
- 宿主崩溃/超时：当前轮 fail-open，不拖死 Agent Loop。
- 插件工具与内置工具同名：注册失败只警告，不覆盖内置。
- `.opencode` 快照：路径/内容/mtime/权限不变。

---

### Task 1: 配置模型与解析

**Files:** `lib/src/config/config_schema.dart`, `config_parser.dart`, `test/plugins/plugin_config_test.dart`

**Interfaces:**
- Produces: `PluginConfig(source, enabled, options)`；`ConatusCodeConfig.plugins`、
  `trustProjectPlugins`；`pluginSpecFromConfig` / `pluginTomlSnippet`。

- [x] 解析 `[[plugins]]`、缺 source 报错、TOML 片段可回读。
- [x] 验证：`dart test test/plugins/plugin_config_test.dart`。

### Task 2: 项目插件发现

**Files:** `lib/src/plugins/plugin_discovery.dart`, `test/plugins/plugin_discovery_test.dart`

**Interfaces:**
- Produces: `PluginDiscovery(workdir).discoverProject()`；`localPluginCandidate`；
  `pluginEntryOf`；`PluginCandidate`。

- [x] 扫描 `.opencode/plugins/*.{js,mjs,cjs}` 与目录入口。
- [x] 解析 `opencode.json(c)` 的 `plugins`（字符串 / `{package, options}`）。
- [x] `.ts` 告警跳过；内容 SHA-256 指纹。

### Task 3: 信任与审批

**Files:** `lib/src/plugins/plugin_trust.dart`, `test/plugins/plugin_trust_test.dart`

**Interfaces:**
- Produces: `PluginTrustStore.filter`；`PluginTrustDecision`；
  `stdinPluginTrustPrompter`。

- [x] 首次审批 allowOnce / allowAlways / deny。
- [x] 信任记录 0600；指纹变化重新询问；headless 默认拒绝。

### Task 4: 安装器与 CLI

**Files:** `lib/src/plugins/plugin_installer.dart`, `plugin_cli.dart`,
`test/plugins/plugin_installer_test.dart`, `plugin_cli_test.dart`

**Interfaces:**
- Produces: `PluginInstaller.add/remove/installed`；`runPluginCli`。

- [x] 本地目录不安装；包优先 `bun add`，回退 `npm install --prefix`。
- [x] `nava plugin add|list|remove [--config|--workdir]`。
- [x] `removePluginBlock` 只删匹配块，保留其余 `[[plugins]]`。

### Task 5: JSON-RPC 与宿主进程

**Files:** `lib/src/plugins/plugin_protocol.dart`, `plugin_host.dart`,
`plugin_host_source.dart`, `test/plugins/plugin_protocol_test.dart`

**Interfaces:**
- Produces: `PluginRpcCodec` / `PluginRpcMessage`；`PluginHost.start/hook/executeTool/notifyEvent/close`；
  `PluginHost.ensureHostScript`。

- [x] 一行一条 JSON；stdout 只走协议，console 转 stderr。
- [x] init 10s、hook 5s、tool 60s 超时；shutdown → 2s 强杀。
- [x] 宿主源码内嵌并写到 `~/.nava/plugins/host-<hash>.mjs`。

### Task 6: V1/V2 加载

**Files:** `plugin_host_source.dart`, `test/plugins/plugin_host_integration_test.dart`

- [x] V1 命名导出函数 → hooks；`config.skills.paths` → 技能根。
- [x] V2 `default.setup(ctx)`；`ctx.skill.transform`、`ctx.session.hook("context")`。
- [x] 自定义工具、`tool.execute.before/after`、`event`、`shell.env`。
- [x] 真实 superpowers 兼容测试（`using-superpowers` 技能 + bootstrap 上下文）。

### Task 7: 服务接线

**Files:** `lib/src/plugins/plugin_service.dart`, `plugin_tool.dart`,
`plugin_assembly.dart`, `test/plugins/plugin_service_test.dart`,
`plugin_assembly_test.dart`

- [x] `PluginEnvShell` 注入 `shell.env`。
- [x] 工具注册（`PluginTool`，默认 high risk）。
- [x] before 拒绝 / after 改结果；`file.edited` 事件。
- [x] 项目插件审批；headless 默认拒绝，配置插件仍加载。

### Task 8: TUI / headless / 导入

**Files:** `lib/src/tui/tui_app.dart`, `tui_controller.dart`, `tui_options.dart`,
`bin/conatus_code.dart`, CLI 导入文件

- [x] 装配顺序：工具/权限 → 插件 → shell → 技能 → prompt。
- [x] `session.created` / `session.idle` 事件。
- [x] `--trust-plugins`；`nava import opencode` 映射 `plugins`。

### Task 9: 文档与验证

**Files:** `README.md`, `CHANGELOG.md`, `docs/plugin-integration.md`

- [x] README 插件章节、CHANGELOG 条目、导入支持列表。
- [x] `dart analyze --fatal-infos` 无问题。
- [x] `dart test` 全绿（1601+）。
- [x] `bash tool/build_binary.sh`；`nava plugin add/list/remove` 手工冒烟。

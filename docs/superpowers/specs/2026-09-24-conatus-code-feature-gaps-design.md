# conatus_code（nava）功能缺口盘点 — 设计

日期：2026-09-24
状态：一期已实施（M1–M5 完成，见实现计划）；后续项待排期
范围：`packages/conatus_code` 子模块；涉及接线时触及框架包（`conatus_mcp` / `conatus_intent` / `conatus_asr` / `conatus_observability`）

## 背景

nava 当前已具备：TUI 会话（斜杠命令、流式思考渲染、@-refs、图片/文件附件、计划面板、权限模式）、
文件与搜索工具（read/write/edit/rg/glob/list_files/apply_patch）、git 只读工具（status/diff）、
run_command / run_tests / run_code、macOS 双层沙箱（Seatbelt + fs jail）、审批链、预算护栏
（TurnBudget + CostTrackerImpl）、Plan Mode、Goal、cron/提醒、记忆、压缩、技能、团队多智能体、
会话持久化与恢复快照、多提供商注册表（config.toml `[providers.*]`）。

对照 conatus 框架已有能力与主流编码智能体（Claude Code / Codex CLI / OpenCode / Gemini CLI）
的标配，存在三档缺口。本文档只做盘点与优先级建议，单项实施前各自出 plan。

## 决策记录

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 盘点口径 | 只列「缺口 + 依据」，不做实现设计 | 各项独立性高，合并设计会互相阻塞 |
| 优先级排序标准 | 框架现成 > 用户可见价值 > 实现成本 | 伞包生态位要求先吃框架红利 |
| README 宣传与实现不符（意图路由） | 视为缺陷处理：接线或改文档，二选一 | 文档失真是 bug |

## 缺口清单

### 一档：框架已有、未接线（成本最低、价值最高）

| # | 缺口 | 现状与依据 | 实施要点 |
|---|------|-----------|----------|
| 1 | **MCP 客户端** | `conatus_mcp` 完整实现（stdio/HTTP/SSE + 工具接入），nava 零引用（pubspec 仅在 dependency_overrides 传递解析出现）。相对所有主流 coding agent 的最大生态位缺口 | config.toml 加 `[mcp.servers.*]`；`provideMcp*` 挂根上下文；MCP 工具风险映射走既有审批链（未声明缺省 medium）；`${KEY}` 占位符经 Credentials 解析，禁写日志 |
| 2 | **意图路由** | README 特性表宣传「⚡ 意图路由（高频命令零模型调用）」，但 `conatus_intent` 不在依赖、零 import——**文档与实现不符** | 接线（高频命令如「跑测试」「git 状态」直映射工具调用）或删 README 条目 |
| 3 | **检查点 / 回滚（/rewind）** | 可逆效应是 conatus_core 核心卖点，nava 无用户可见的文件级 checkpoint/rewind（现仅 RecoveryService 会话快照）。差异化功能未利用 | 每轮前对工作区做轻量快照（git stash 式或 fs 快照），`/rewind` 回到指定轮次；与 EffectScope LIFO 语义对齐 |
| 4 | **后台任务** | `[background]` 配置表已解析（`config_schema.dart:228` 注明「供未来执行器消费」），执行器未实现 | `run_command` 支持后台挂起 + 任务列表/取输出工具；可与 `conatus_tasks` 任务中心复用 |
| 5 | **ASR 语音输入** | TTS 播报（VoiceReporter）已有，输入侧 `conatus_asr` 未接 | 输入框快捷键触发语音录入，转写后作为一轮输入 |
| 6 | **可观测性导出** | 仅 `InMemoryTelemetry`，`/telemetry` 只看最近 8 个事件名；`conatus_observability` 未接 | 按需接 OTLP/文件导出；`TeamCostSource` 注入点已预留（`team_subscription.dart:16`） |

### 二档：编码智能体标配、缺失

| # | 缺口 | 现状与依据 | 实施要点 |
|---|------|-----------|----------|
| 7 | **Headless / 非交互模式** | `TuiOptions` 仅 `--session/--config/--help`，无 `nava -p "<任务>"` / `--output-format json`。CI 与脚本化不可用（Codex `exec`、Claude `-p`、OpenCode `run` 均有） | 新增 `bin` 分支或独立入口：单轮跑完输出 reply 即退出；权限模式默认 never_ask + 沙箱全开；JSON 输出含工具调用轨迹 |
| 8 | **项目上下文文件自动加载** | 不读 `AGENTS.md` / `NAVA.md` 进 system prompt（父仓库自身即 AGENTS.md 重度用户）；无 `/init` 生成命令 | SystemPrompt 新增项目段：启动时沿 workdir 向上找 AGENTS.md/NAVA.md 注入；`/init` 让模型总结仓库生成该文件 |
| 9 | **`/compact` 手动压缩** | 压缩引擎已装配（自动触发），缺手动命令 | 一条斜杠命令调 `CompactionEngine`，可选附指令 |
| 10 | **`/cost` / `/usage`** | `CostTrackerImpl` 持续累计 `todayCost`，无展示出口 | 斜杠命令读 `'costTracker'` 服务，展示今日成本/轮次/token 估算 |
| 11 | **`--version`** | 无任何版本查询途径 | 编译期注入版本号（build_binary.sh 写入），`--version` 打印 |
| 12 | **`--continue` / `--resume`** | 仅 `--session <session_uuid>` 精确恢复，无「恢复最近一次」 | SessionStore 按 mtime 取最近会话；`--continue` 恢复之 |
| 13 | **Git 工作流** | 仅 `git_status` / `git_diff` 只读；无 `/commit`、无 commit/push 工具 | `/commit` 让模型基于 staged diff 写提交信息并提交（走审批）；push 保持经 run_command |
| 14 | **Hooks** | 无用户自定义钩子（PreToolUse/PostToolUse/Stop 跑 shell） | config.toml `[hooks.*]`；挂工具中间件链与轮次收口点；效应系统天然支持注销 |
| 15 | **消息排队** | busy 时输入被拒（「正在回复，请稍候」），不能排队追问 | 输入入队，当前轮收口后依次投递；Esc 打断时清空或保留可选 |
| 16 | **`/doctor` 诊断** | 沙箱 probe、rg 定位、Key 检查分散存在，无集中命令 | 汇总：沙箱后端 smoke、rg 可用性、provider 连通、凭据脱敏展示、配置路径 |
| 17 | **Linux/Windows 沙箱** | Layer 2 仅 macOS（README 已列已知边界） | Linux 评估 landlock/bwrap；Windows 降级策略。单独立项 |

### 三档：较小项

- **OAuth 登录**：config 保留字段（`oauth.key`），明确未实现，启动仅提示不可用。
- **`/export`**：导出会话记录为 Markdown/JSON。
- **会话 fork**：从某轮分叉新会话。
- **配置热重载**：config.toml 变更免重启。
- **自定义斜杠命令目录**：技能体系已部分覆盖（`/skill:<名>`），视需求补 `.nava/commands/*.md`。

## 建议优先级

1. **MCP 接入**（#1）——框架现成，补齐生态位。
2. **Headless 模式**（#7）——解锁 CI/脚本场景，亦是 nava 进父仓库 CI 自举的前提。
3. **AGENTS.md 加载 + `/init`**（#8）——小改动，体验提升大。
4. **小命令批**（#9/#10/#11/#12）——基础设施全有，只差命令面，可一个 plan 打包。
5. **Checkpoint/rewind**（#3）——差异化卖点，值得单独设计（快照策略、与 Plan Mode/审批的交互）。
6. **意图路由**（#2）——先消除文档失真，再评估接线收益。
7. 其余按需求驱动排期。

## 已知边界（不改变本文结论）

- `tool/version.sh` 把子模块纳入版本一致性检查会报不一致（AGENTS.md 第 10 节已记）。
- Layer 2 沙箱 macOS 限定是 README 明示的既定边界，#17 属新立项而非补漏。

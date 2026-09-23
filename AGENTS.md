# AGENTS.md — conatus 项目指南

> 面向接手本项目的 AI 编码代理与开发者。读完本文档应能独立构建、测试、修改本仓库。
> 本文档聚焦**操作层面**：命令、约定、边界。完整 API 文档见仓库根 `README.md`（1861 行，
> 每个插件都有用法与 API 速查表），此处不重复。

## 1. 项目概述

conatus 是**时空可组合性（Spatiotemporal Composability）编程范式**的 Dart 实现，基于论文
*A Programming Paradigm for Spatiotemporal Composability*（arXiv:2608.25512）。它同时是
一个**通用 Agent 框架**：可逆效应（时间可组合性）+ 反应式共效应（空间可组合性）统一在
`Context` 类型上，之上构建了 LLM 接入、工具系统、会话、记忆、MCP、任务中心等一整套
Agent 能力。

三个核心性质（改动 `conatus_core` 前必须理解）：

- **可逆效应**：每次副作用登记撤销函数，`EffectScope` 按 **LIFO** 顺序回滚；幂等、迟到登记安全、抗异常。
- **反应式共效应**：组件用 `ctx.inject([...], (child) {...})` 声明依赖，运行时比对当前上下文，依赖满足时激活、消失时停用（子上下文隔离，`dispose()` 一次性撤销全部效应）。
- **上下文树**：服务沿父链向下可见，子级服务对父级不可见；父级释放级联释放子树。`Reactor` 用「脏标记 + 重跑」把连锁反应在一次 `notify()` 内收敛，无法收敛（循环依赖）抛 `StateError` 快速失败。

仓库：https://github.com/Fi2zz/conatus（镜像：https://gitee.com/fitzy/conatus）

## 2. 仓库结构（pub workspace monorepo）

根包 `conatus` 是**伞包（umbrella）**：自身不含实现（`lib/conatus.dart` 只有 export），
统一再导出 `packages/` 下的模块包。`import 'package:conatus/conatus.dart';` 即完整公开 API；
也可只依赖某个模块包以缩小依赖面。

```
├── pubspec.yaml            # 伞包；workspace: packages/*（glob，SDK ^3.11.0 起支持）
├── lib/conatus.dart        # 伞包入口：只 re-export，不写实现
├── packages/               # 23 个目录（见下方分类）
├── test/                   # 根包测试：integration/（跨包集成）+ integration_e2e_test.dart
├── example/                # 演示：main.dart（交互式 Agent，需 API Key）、
│                           #        demo.dart（离线脚本化模型）、voice_plan_mode.dart
├── tool/                   # 版本管理、子模块 filter、可逆性验证脚本
├── .github/workflows/      # integration-test.yml + mirror-to-gitee.yml
├── .conatus/               # 本地运行数据（sessions/database/providers.json），已 gitignore
├── .handoffs/              # 交接文档（HANDOFF.md、HANDOFF-<N>.md），跨轮次上下文
└── docs/superpowers/       # superpowers 工作流的 plans/ 与 specs/
```

### packages/ 分类（23 个目录）

| 类别 | 包 | 说明 |
|------|----|------|
| **稳定模块包 ×14**（进伞包，可发布） | `conatus_core` | 核心范式：Context / EffectScope / Reactor，零运行时依赖 |
| | `conatus_foundation` | 基础设施：timer / logger / loader / tools / shell / fs / session / session-log / system-prompt / memory / database / ask-user |
| | `conatus_credentials` | 凭据能力缝：env / 内存 / 文件 / Vault KV v2 / AWS Secrets Manager |
| | `conatus_llm` | 大模型接入（豆包 / DeepSeek，chat 与 responses 两种形态，FallbackLlm 回退链） |
| | `conatus_search` | 搜索能力缝 + `web_search` / `fetch_url` |
| | `conatus_skill` | 技能加载：发现 `SKILL.md` 指令集、目录注入、`skill` 工具 |
| | `conatus_asr` / `conatus_tts` | 语音识别 / 合成能力缝 |
| | `conatus_mcp` | MCP 客户端：stdio / HTTP / SSE 传输 + 工具接入 |
| | `conatus_schedule` / `conatus_cron` | 会话本地提醒 / 定时任务 |
| | `conatus_compaction` | 压缩能力缝：滚动摘要 + `compaction/*` 日志事件 |
| | `conatus_agent` | Agent Loop 与产品化：plan / sub-agent / reflection / telemetry / eval / approval / skill / recovery |
| | `conatus_tasks` | 任务中心：运行时任务追踪（任务树 + `list_tasks` / `cancel_task`） |
| **实验性包 ×7**（`publish_to: none`，不进伞包，API 可能破坏性变更） | `conatus_alerting` / `conatus_browser_use` / `conatus_computer_use` / `conatus_intent` / `conatus_observability` / `conatus_team` / `conatus_workflow` | 告警 / 浏览器操作 / 桌面操作 / 意图路由 / 可观测性导出 / 多智能体协作 / 流程编排 |
| **新实验性包 ×1** | `conatus_ontology` | 自进化本体层（EvoOntology，arXiv:2609.15779 适配）：Term / Mapping / Constraint / Evidence，接地构建 + TypedEdits 局部更新 + 配对评估门控。0.16.0 新加入，**尚未进伞包、未进 README 表格**；自述实验性，勿在生产依赖 |
| **子模块 ×1** | `conatus_code` | 独立仓库（github.com/Fi2zz/conatus_code）的终端编码智能体；根包仅在 `dev_dependencies` 以 git 源引用，workspace 内解析到本地成员。不开发它时无需拉取 |

依赖方向自上而下无环：`conatus` → `conatus_agent` → `conatus_llm` / `conatus_foundation` /
`conatus_compaction` → `conatus_core`（公共底座）。稳定包不反向依赖实验性包。

## 3. 技术栈与依赖约束

- **Dart SDK**：根包 `^3.11.0`（workspace glob 语法要求），模块包 `^3.6.0` 起；**纯 Dart，不含 Flutter SDK 依赖**，Flutter 项目也可用。
- **零运行时依赖是卖点**：`conatus_core` 仅用 Dart 核心库；`llm` / `credentials` / `mcp` / `search` 依赖 `http`；`foundation` 依赖 `timezone`（IANA 时区）。**新增依赖需谨慎**，先确认是否真的必要。
- 静态分析：`package:lints/recommended.yaml` + 自定义规则（见第 4 节）。
- 测试：`package:test`（不用 mock 框架，用手写 Fake / 脚本化替身）。

## 4. 常用命令

所有命令在仓库根执行（workspace 解析在根一次完成）：

```bash
dart pub get                                   # 根目录一次完成 workspace 解析
dart analyze                                   # 全仓静态检查（CI 用 --fatal-infos）
dart format .                                  # 格式化
dart test                                      # 伞包自身测试（根 test/）
for d in packages/*/; do (cd "$d" && dart test); done   # 按包跑测试（pub 暂不支持一次跑完 workspace）
dart test test/integration/ --reporter=expanded # 集成测试（CI 单独跑）
```

专项验证与工具：

```bash
bash tool/version.sh                    # 检查：所有包版本号一致、包间约束指向它
bash tool/version.sh 0.16.0             # 统一升版（改 version + 同步包间约束；fail-closed）
bash tool/verify_reversibility.sh       # conatus_core 可逆性验证：静态检查 + 单元 + 随机顺序(3种子) + 行覆盖率 + 变异测试
git submodule update --init             # 首次拉取 conatus_code 子模块
bash tool/setup_code_filter.sh          # 子模块 workspace filter（开发 conatus_code 前必跑）
```

注意：pub workspace 会在解析期校验成员间版本约束，**任何一处版本漏改，`dart pub get` 直接失败**（这是特性不是 bug）。

## 5. 代码组织与风格

### 组织约定

- **每包一个入口**：`lib/conatus_<name>.dart`（library + export），实现全在 `lib/src/`。`lib/src/` 内**单文件单职责**，超长就拆分（有单文件行数约束，见下）。
- **装配模式**：每个能力是一个 `provide*` 顶层函数（如 `provideLlm(app)`、`provideAgentLoop(app, ...)`），注册服务键（如 `'llm'`、`'agentLoop'`）并提供 `ctx.xxx` 快捷访问。改动/新增能力时保持这个模式。
- **能力缝（seam）模式**：契约接口 + 内置本地实现 + 可注入替换。例：`ShellExecutor` / `LocalShellExecutor`、`FileSystem` / `LocalFileSystem`、`CredentialsSource` 家族。消费方只依赖接口。
- **工具**：继承 `Tool` 声明 `name` / `description` / `params`（`ParamSpec` 自动生成 JSON Schema）/ `call`；经 `ctx.tools.register` / `ctx.tools.fn` 注册，`ctx.tools.call` 走「校验 → 守卫 → 中间件 → 执行体」管线。`Tool.toSchema()` 只投影 name/description/parameters，宿主字段永不下发模型。
- **服务与效应都返回 `Disposer`**，交给 `ctx.effect(...)` / `ctx.onDispose(...)` 随上下文卸载自动撤销；`provide` 返回的 Disposer 可提前撤销并级联停用依赖方。
- 测试文件按功能命名 `*_test.dart`，放 `packages/<name>/test/`；集成测试 helpers 共享在 `test/integration/helpers/`。

### 硬性约束（仓库实际执行）

- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、函数参数 ≤ 4 个（超出封装对象）——git 历史里有「拆分到独立文件，满足单文件行数约束」的提交，新增代码默认遵守。
- 每个函数内 `if / else / switch / case` 总数 ≤ 3，最大嵌套深度 ≤ 2，单个条件连续 `&& / ||` ≤ 2；禁止嵌套三元；优先 early return。
- 布尔变量 / 布尔函数用状态词或形容词，禁止 `is / has / can / should` 前缀；禁止 `flag` / `temp` 等弱语义命名；函数名 `动词 + 名词`。
- 例外（算法实现、第三方 SDK 固定格式回调、超长静态映射表）需加 `// REASON: ...` 说明。

### lint 规则（analysis_options.yaml）

`strict-casts` / `strict-inference` / `strict-raw-types`（analyzer 语言层全开）；
`always_declare_return_types` / `prefer_final_locals` / `prefer_single_quotes` /
`unawaited_futures` / `prefer_relative_imports`（**包内用相对导入**）/ `sort_pub_dependencies`
/ `directives_ordering` / `prefer_const_constructors` / `avoid_redundant_argument_values` /
`use_super_parameters` / `unnecessary_lambdas`。`todo: ignore`。

## 6. 测试策略（三层）

| 层级 | 位置 | 关注点 | 替身程度 |
|------|------|--------|----------|
| 单元测试 | `packages/*/test/` | 单组件逻辑正确性 | 大量 Fake / 脚本化替身 |
| 集成测试 | `test/integration/` | 跨包链路组合行为 | 只 Mock 外部 IO |
| 端到端 | `test/integration_e2e_test.dart` | 全栈装配跑真实 Agent Loop | 脚本化模型 |

- 集成测试用 `TestHarness` 构建完整 Context 树 + `ScriptedLlm`（预设响应序列）+ 外部 IO 替身
  （`fake_search.dart` / `fake_shell.dart` / `fake_browser.dart` / `terminal_io.dart`），覆盖场景：
  终端订票、多 Agent 审查、定时提醒、Plan Mode、预算告警、意图路由、目标延续、失败重试。
- **ASR / TTS 不进集成测试**（音频硬件与网络不稳定、CI 无音频设备），由各自单元测试覆盖。
- `conatus_core` 有专项可逆性验证（`tool/verify_reversibility.sh`）：随机测试顺序（3 个种子）、
  行覆盖率（`effect_scope.dart` / `context.dart`）、**变异测试**（`tool/mutate_reversibility.sh`
  注入 7 个真实 bug，含 2 个元检查，要求全部被杀掉；fail-closed）。改 `conatus_core` 的
  效应/上下文机制后必须跑它。
- 提交前必须通过：`dart analyze --fatal-infos` + 受影响包的 `dart test`；CI 全量执行。

## 7. 开发约定

**完成一项功能 / 更改 / 修复之后需要提交并推送**：任何改动收尾（测试通过、按需重建
二进制）后，立即按「提交信息」规范提交到对应仓库，并 `git push` 到远端；子模块与父
仓库按依赖顺序推送（先 conatus_code，再根仓库 gitlink）。

### 提交信息

Conventional Commits + 中文描述 + scope：`feat(foundation): ...` / `fix(llm): ...` /
`chore(code): ...` / `docs(...): ...`。**子模块 conatus_code 的每次更新**在父仓库表现为
`chore(code): 同步子模块 gitlink（<改动简述>）` 的 gitlink 提交。

### 子模块工作流（开发 conatus_code 时）

1. `git submodule update --init` 拉取；2. `bash tool/setup_code_filter.sh`。
filter 的作用：checkout 时恢复 `pubspec.yaml` 的 `resolution: workspace`（本地走 workspace、
依赖解析到本地 `packages/*`），`git add` 时自动注释掉（独立 clone 仍按 git 源解析）；并生成
`pubspec_overrides.yaml`（已 gitignore）清空 `dependency_overrides`。**不要手动改子模块的
`resolution:` 行与 override**，交给 filter 管理。

- **每次完成 conatus_code 相关改动并通过 `dart test` 后，必须重新构建二进制**：
  在 `packages/conatus_code` 下运行 `bash tool/build_binary.sh`，产出 `dist/nava`
  （`/Users/fitz/bin/nava` 是它的符号链接，PATH 里的 `nava` 随之生效）。只改源码不
  重建、或交付旧二进制，视为改动未完成。

### 版本管理

所有包**共用同一版本号**（0.x 下 `^0.15.0` 等价 `>=0.15.0 <0.16.0`），升版一律走
`bash tool/version.sh <新版本>`，它会同步改全部 `pubspec.yaml` 的 `version:` 与包间约束，
校验失败自动还原。

### 其他

- `.handoffs/` 存放轮次交接文档；长任务被压缩前先写 HANDOFF 再结束。
- 面向用户的文案用中文（项目无 i18n 系统，直接写中文字符串）。
- 不做「顺手优化」混入当前任务：功能 / 修复 / 重构分开提交。

## 8. 发布与部署

1. `bash tool/version.sh <新版本>` 统一升版并过检查。
2. 按依赖顺序发布（依赖在前），14 个可发布包 + 伞包：

```bash
for p in conatus_core conatus_foundation conatus_compaction conatus_cron \
         conatus_credentials conatus_llm conatus_mcp conatus_schedule \
         conatus_search conatus_skill conatus_asr conatus_tts conatus_agent \
         conatus_tasks; do
  dart pub publish -C "packages/$p"
done
dart pub publish            # 最后发布伞包 conatus
```

3. 7 个实验性包（alerting / browser_use / computer_use / intent / observability / team /
   workflow）是 `publish_to: none`，不在发布之列；`conatus_code` 是独立仓库，独立发版。
4. CI（`.github/workflows/integration-test.yml`）：push / PR 触发，ubuntu-latest +
   `dart-lang/setup-dart@v1`，跑根测试 + 各包测试（跳过无 pubspec.yaml 的目录）+ 集成测试。
5. push 会自动触发镜像到 Gitee（`mirror-to-gitee.yml`，force push，无需人工干预）。

## 9. 安全注意事项

- **凭据脱敏是硬约束**：`Credential` 对外只暴露 `masked`（前 4 + `...` + 后 4，≤ 8 全星号），
  `toString()` 只含脱敏值；结构化日志交给 `conatus_core` 的 `redactSecrets`。新增任何会打印
  凭据/密钥的代码都是违规。
- MCP 的 `env` / `headers` 支持 `${KEY}` 占位符（经 `Credentials` 解析），**解析结果不得写进日志**
  （排查用键名）；Dart 源码里写 `r'...'` 原始字符串或转义 `\$`。
- 工具风险分级：`Tool.riskLevel` + `ctx.tools.guardRisk(max)` 能力分级；MCP 工具风险映射，
  未声明缺省 `medium`（默认需要审批）。高危工具（`approval`）默认走审批链，`AskUserApproval`
  超时视为拒绝。
- `shell` / `fs` 是能力缝：默认 `LocalShellExecutor`（`bash -c`）与 `LocalFileSystem`
  （原子写入 + 版本守卫）。生产替换为沙箱实现时消费方代码不变。
- 提交时注意不要带入真实 API Key（`.conatus/` 已 gitignore；`providers.json` 只存键名）。

## 10. 已知边界与注意事项

- **`tool/version.sh` 与子模块**：脚本遍历 `packages/*/pubspec.yaml`，会把 submodule
  `conatus_code`（独立版本号，当前 0.1.0）也纳入版本一致性检查，因此**当前会报「版本号不一致」**。
  发布 14 个模块包 + 伞包时按第 8 节流程即可；如需 version.sh 通过，需先排除子模块目录
  （脚本当前未排除，属已知缺口）。
- `conatus_ontology` 是新实验性包：不进伞包、不在根 `pubspec.yaml` 依赖、未进 README 表格，
  但已在 workspace 内并被 version.sh 纳入。改它之前先读其 README 与 `docs/superpowers/` 相关 spec。
- 未拉取子模块时 `dart pub get` 照常工作（glob 自动跳过无 pubspec.yaml 的目录）；
  拉取后根包 dev 依赖 `conatus_code` 解析到本地成员。
- 实验性包 API 可能在无 major 版本号变更的情况下破坏性变更，勿在生产依赖。
- 本文件为仓库级指南；更细的 API 用法、参数表、设计取舍一律以根 `README.md` 与各包 README 为准。

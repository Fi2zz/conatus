# HarnessPro 移植：成本感知的 harness 自改进

- 日期：2026-10-23
- 状态：已实现（S1–S3）
- 来源：[HarnessPro](https://github.com/pzs19/HarnessPro)（MIT）、
  *HarnessPro: Recursive Harness Self-Improvement with Pareto Optimization for
  Performance-Cost Trade-offs*（arXiv:2610.26770v2，CC BY 4.0）
- 相关：`conatus_agent` 的 `telemetry` / `eval` / `prompt_evolver` / `router` /
  `tool_result_eviction`、`conatus_context`、`conatus_code` 的 `budget` / `hooks` /
  `checkpoint`、`conatus_foundation` 的 `tools` / `system_prompt`

## 1. 背景

HarnessPro 把 agent harness（指令、工具、技能、hooks、验证策略）当作可搜索的制品，
用执行轨迹诊断驱动修改，并把**执行成本**与通过率一起作为优化目标。实验结论（GPT-5.5 +
Codex，Terminal-Bench 2）：heavy 档相对 RHO 通过率 76.3 → 80.8，单任务成本
$1.09 → $0.72；同批次还给出了两条对移植决策至关重要的事实：

1. **单独移植会掉分**。只加「动态档位路由」或「预算钩子」，成本都降到 $0.92，但
   SWE-Bench Pro 通过率从 80.0 掉到 76.0 / 75.0；统一降 reasoning effort 更差
   （80.0 → 59.0）。收益来自多机制协同，所以切片必须成组上线。
2. **评测质量比进化算法更重要**。去掉 test synthesizer 掉 3.4–10.0 个百分点，
   比去掉 planner 影响更大。用 LLM 直接判轨迹的失败召回率是 41.7%，合成测试是 83.3%。

本设计不从「复刻 HarnessPro」出发，而是从 conatus 已有的原语出发，挑出**能补齐成本
维度**、且与现有分层不重复的部分。

## 2. 现状盘点

| 能力 | 现有实现 | 缺口 |
|---|---|---|
| 用量采集 | `conatus_agent` 的 `AgentTurn.usage` 原样收 `LlmResult.usage`；`session_log_llm` 落日志 | 只是原始 map，没有统一口径 |
| 成本计算 | `conatus_code/lib/src/budget/cost_tracker.dart`：两种 token 键名归一 + models.dev 费率 + cached 折扣 + 「费率未知」显式报未知 | 锁在子模块；只有进程累计，无单任务成本，无 Cost-of-Pass；成本没进 telemetry |
| 预算护栏 | `TurnBudget`（墙钟 + 上下文 token）、`AgentLoop.maxSteps` | 没有阶段化（经济/收敛/收口），没有工具调用数维度 |
| 档位选择 | nava 的 `ThinkingConfig.effort` 是静态配置；`conatus_agent` 的 `router` 是确定性快路径（reply/tools/pass） | 没有「按任务文本选档」；`chat(options:)` 能透传 effort 但无抽象 |
| 上下文压缩 | `conatus_context` 按内容类型结构化压缩 + 去重折叠 + CCR 可逆取回（`minChars` 4000） | 缺**源头压缩**：命令改写；`tool_result_eviction` 默认 80k 字符阈值过高 |
| 评测 | `Evaluator` + `EvalCase`（expectedTools 子集 + 输出关键词） | 判据弱，正是论文指出的「过度乐观」来源；无生成式测试、无冻结集 |
| 目标函数 | 无帕累托、无多档 | `prompt_evolver` 单目标 + 阈值晋升 + 人工审批 |
| 候选隔离 | nava 的 shadow-git checkpoint / revert | 无并行候选的 workspace 隔离 |
| 制品化 | 装配散在 TOML / SystemPrompt 段 / hooks / skills | 无一棵可 diff、可 A/B 的 harness 描述 |

## 3. 目标与非目标

### 目标

1. 成本成为一等可观测量：单次调用、单轮、单任务都可归因，可算 Cost-of-Pass。
2. 预算从「单点上限」升级为「阶段策略」：经济 → 收敛 → 收口，且**不破坏 prefix cache**。
3. 支持按任务特征选择执行档位（reasoning effort + 工具预算），可关、可回退。
4. 为后续三档（lite/medium/heavy）选型提供纯函数级的帕累托与加权距离实现。
5. 全程纯 Dart、零新增运行时依赖、默认行为可关。

### 非目标

- 不做 Terminal-Bench / SWE-Bench / ProgramBench 评测基建，不引入 Docker / Python / pier。
- 不做 Codex / Claude Code 适配层与宿主专有开关（`model_verbosity`、`disabled_features`）。
- 不搬 RTK 全量改写注册表（作者自己踩过：`rg --files`、`find -print` 被改坏）。
- 不搬 9 个冻结 harness 的具体阈值。
- 不做 DPP coreset（需要 train/val 语料分割，当前不存在）。
- 不做自动晋升：三档选型只产出候选，发布仍走 `Approval` / 人工。
- 不把硬 deny 作为默认策略（无人值守 benchmark 的收口策略在交互式 agent 里会误伤）。

## 4. 设计

### 4.1 成本口径

新增 `conatus_agent/lib/src/cost.dart`（≤200 行，纯计算）：

- `TokenUsage`：`prompt` / `cachedPrompt` / `completion`，归一并存两种键名
  （`prompt_tokens`/`input_tokens`、`prompt_tokens_details.cached_tokens`/
  `input_tokens_details.cached_tokens`）。移植 `conatus_code` 现有实现对账，避免两套口径。
  注意命名冲突：`conatus_code` 的 `budget/cost_tracker.dart` 已有同名类型，落地时由子模块
  改为复用本类型（保留 `costWith(ModelProfile)` 作为 nava 侧扩展），否则两处 import 会歧义。
- `ModelRate`：`inputPerMillion` / `cachedPerMillion` / `outputPerMillion`，
  由调用方注入（费率来源不进入本层，保持零依赖）。费率缺失时 `cost` 返回 `null`，
  **不返回 0**（沿用 nava「一个错的 $ 数字比没有数字更糟」的约定）。
- `CostAccumulator`：`add(usage)` → `calls` / `tokens` / `cost`，区分 `attributed` 与
  `unknownRateCalls`。
- `CostOfPass`：`totalCost / passedTasks`，`passedTasks == 0` 时返回 `null` 而非无穷。

数据流：`TelemetryLlmProvider` 在 `llm.request` 事件里补 `cost`（可空）与 `cachedTokens`；
`AgentLoop` 收口时在 `agent.finished` 里补本轮 `cost`。这样成本既进事件流，也进 turn 结果。

### 4.2 阶段预算钩子

新增 `conatus_agent/lib/src/tool_budget.dart`，形态是 `ToolRegistry.use` 中间件，
与 `tool_result_eviction` / `conatus_context` 同层（后注册者在内层）。

策略对象 `ToolBudgetPolicy`：

```dart
class ToolBudgetPolicy {
  final int economyAfter;   // 进入经济阶段
  final int strictAfter;    // 进入收敛阶段
  final int finalizeAfter;  // 收口：拒新工具调用
  final int strictEvery;    // 收敛阶段提醒间隔
  final Set<String> finalizeAllowed; // 收口阶段仍放行的工具
}
```

三个阶段的行为：

- **经济**：提醒批量独立检查、禁止重复读、抑制过程叙述，明确「不得以省略验证换省钱」。
- **收敛**：只在 `strictAfter` 及之后每 `strictEvery` 次触发，要求只查与当前失败/交付物
  直接相关的证据，并要求收口前复核路径、接口、行为、最终状态。
- **收口**：`count > finalizeAfter` 时拒绝**不在白名单**的调用，返回可解释的拒绝理由；
  白名单默认含 `read_file` 类只读工具与收口工具。拒绝是软约束（返回错误结果），不抛异常。

**关键约束：提醒追加在工具结果尾部，不改写 system prompt。** 理由：system prompt 一变，
整个前缀的 KV cache 失效，省下的 token 会被缓存命中率下降吃掉。实现上中间件在
`next()` 返回后把 `\n\n[budget] ...` 追加到 `ToolResult.content`，其余字节不动。

计数的载体是 `Context` 里的一个 `ToolBudgetState`（随 `ctx.effect` 撤销），不写进程全局，
避免多会话互相污染；并发工具的计数用单线程事件循环内的同步递增即可，不加锁。

### 4.3 档位路由

新增 `conatus_agent/lib/src/execution_profile.dart` + 一份 rubric 资源文本：

- `ExecutionProfile`：`name` / `reasoningEffort` / `ToolBudgetPolicy`。
- `ProfileSelector`：`Future<ExecutionProfile?> select(String task)`；未配置、超时、解析失败
  一律返回 `null`，调用方落回 `defaultProfile`。**路由失败绝不阻断主流程**。
- 选择器本身是一次 tool-free 小调用（论文用 medium effort、2048 输出 token、120s 超时、
  3 次重试），返回一个档位名，`ProfileSelector` 负责把名字映射回策略对象；模型给了未知
  名字也落回默认。

rubric 文本直接取自 `harnesses/*/runtime/profile_rubric.md` 的结构（档位定义 + 证据规则 +
按序门控），但**必须保留两条防泄漏约束**：只用任务文本里显式描述的证据；禁止使用历史结果
或先前评测分数。档位阈值（`economy/strict/finalize`）随项目标定，不照抄 TB2 的数字。

装配侧（nava）需要能关：配置项缺省关闭，开启后选择结果按会话缓存一次，不每轮重选。

### 4.4 三档选型（纯函数）

新增 `conatus_agent/lib/src/pareto.dart`：

- `paretoFrontier(List<Candidate>)`：过滤被支配项。支配定义严格照论文——两项都不差且
  至少一项更好。
- `selectRepresentative(frontier, weights)`：`J = α·d_perf² + β·d_cost²`，
  其中 `d_perf = (Pmax − P)/(Pmax − Pmin)`、`d_cost = (C − Cmin)/(Cmax − Cmin)`；
  权重 lite `(1,2)`、medium `(1,1)`、heavy `(2,1)`。
- 边界情况必须显式处理：单元素集合返回自身；`Pmax == Pmin` 或 `Cmax == Cmin` 时该维度
  偏差记 0（否则除零）；空集合返回 `null`。

这一层只吃 `(passRate, meanCost)`，不依赖 evaluator 实现，便于单测穷举。

### 4.5 harness 制品（暂缓，方向记录）

HarnessPro 的 harness 是目录：`model_instructions.md` + `policy.json` + `hook.py` +
`bin/` + `checklists/`，可 git diff、可并行评测。conatus 的对应物是「一棵可重建的 Context
子树」：`provide*` 装配 + `ctx.inject` 依赖 + `EffectScope` 回滚。

方向：新增实验包 `conatus_harness`，`HarnessManifest` 描述段、工具集、钩子策略、技能与
验证清单，`apply(ctx, manifest)` 幂等地装出一棵子树，撤销即回滚。这样三档 harness 就是
三份 manifest 的 diff，而不是三份分叉的启动脚本。

**本设计不实现该包**，只在切片之外记录方向；它依赖 4.1–4.4 的指标与策略类型先稳定。

## 5. 关键取舍

1. **为什么提醒不写进 system prompt**：见 4.2。cache 命中率是成本模型里权重很大的一项，
   任何每轮变动的系统前缀都会把它打掉。
2. **为什么路由与钩子必须同批上线**：论文 ablation 显示两者单独引入都会降通过率；
   只有「动态选档 + 按档位执行预算」组合才推进帕累托前沿。因此切片 S2 与 S3 要么一起发，
   要么 S3 默认关闭。
3. **为什么评测升级排最后**：合成测试需要可执行环境与语料，`conatus` 现在没有评测集；
   先做会被迫把 benchmark 基建一起搬进来，与零依赖目标冲突。等到 nava 有了稳定的任务回放
   再启动。
4. **为什么只搬 RTK 的 allowlist**：作者实测通用改写会改变命令语义（`rg --files` 被改成
   非法 grep、`find -print` 语义丢失），最后收缩成高价值白名单。移植时改写在 shell 工具
   执行前进行，命中白名单才改，且可审计、可关。
5. **为什么成本未知返回 null**：沿用 nava 现有约定，避免用写死费率造假；下游聚合时把
   `unknownRateCalls` 一起报出来。

## 6. 落地切片

每个切片独立可提交、独立可回滚，遵循仓库单文件 ≤200 行 / 函数 ≤40 行的约束。

### S1 成本可观测（不改行为）

- 新增 `conatus_agent/lib/src/cost.dart` 与对应测试。
- `telemetry.dart`：`llm.request` 事件补 `cost` / `cachedTokens`（可空）。
- `agent_loop.dart`：`agent.finished` 补本轮聚合成本。
- 验收：给定固定 usage 与费率，`CostAccumulator` 数值与 `conatus_code` 的
  `TokenUsage.costWith` 对账一致；费率未知时成本为 `null` 且计数进 `unknownRateCalls`。

### S2 阶段预算钩子

- 新增 `tool_budget.dart`（策略 + 状态 + 中间件 + `provideToolBudget`）。
- `tool_result_eviction.dart`：阈值本已可配（参数或 `toolResultThreshold`），只下调默认值并在
  文档里说明 4k–80k 区间的取舍——压缩层已由 `conatus_context` 在 4000 字符起接管，
  驱逐器只需兜住压缩后仍过大的剩余部分。
- 验收：构造 50 次工具调用的脚本化 loop，断言 economy/strict 各触发一次起步、
  finalize 后非白名单调用被拒且白名单放行；断言追加提醒后**工具结果前缀字节不变**。

### S3 档位路由（与 S2 同批发布，默认关闭）

- 新增 `execution_profile.dart` + rubric 资源 + `provideProfileSelector`。
- nava 侧接入配置项与开关。
- 验收：选择器超时/异常/未知档位名都落回默认；关闭开关时行为与当前完全一致（回归测试）。

### 后续（不在本设计范围）

三档选型的装配、harness manifest 包、合成测试评测升级、命令级压缩 allowlist。

## 7. 风险与失败模式

| 风险 | 表现 | 缓解 |
|---|---|---|
| cache 反噬 | 加了预算提醒反而更贵 | 提醒只追加工具尾部；用 cache 命中率做验收指标 |
| 误伤收口 | 交互式场景里提前拒绝必要工具 | finalize 默认只拒高成本工具；白名单可配；默认关闭 |
| rubric 漂移 | 选择器偏好某类任务，评测集上过拟合 | 只用任务文本证据；禁止历史结果；每轮记录选择理由便于审计 |
| 假成本 | 费率缺失时按 0 计 | 返回 `null` + 单独计数，聚合时显式披露 |
| 计数污染 | 多会话共享工具计数 | 状态挂在 `Context`，随效应撤销 |
| 过度设计 | 三档 / manifest 在无评测语料时先落地 | 切片顺序固定，S1→S2→S3，后续项以语料就绪为前置 |

## 8. 测试策略

- 纯函数层（成本、帕累托、加权距离）用表驱动单测覆盖边界：空集、单元素、极值相等、
  费率缺失、两种 token 键名混用。
- 中间件层用脚本化工具替身跑固定调用序列，断言阶段切换点与拒绝/放行集合。
- 回归：所有新增能力默认关闭时，现有集成测试（`test/integration/`）输出不变。
- 不引入网络与真实模型调用；选择器测试用脚本化 `LlmProvider`。

## 9. 开放问题

1. 成本费率来源：`conatus_agent` 不引 models.dev 客户端（零依赖），由 nava 注入费率表；
   纯框架用户需自己提供。是否需要在 `conatus_llm` 里提供一张可覆盖的静态价目表？
2. 工具预算的计数口径：是否把失败的参数校验、被守卫拒绝的调用计入？倾向计入
   （它们同样消耗上下文与轮次）。
3. 档位选择是否按对话轮次重选：目前倾向每会话一次；长会话跨任务时需要重新评估。
4. 三档选型是否需要持久化候选（git 提交 / manifest 存档）后才能接 `Approval`，
   这取决于 4.5 的包是否落地。

## 10. 落地记录

- S1：`conatus_agent/lib/src/cost.dart` + `AgentTurn.cost` / `.tokens` +
  `llm.request` 的 `cost` 字段；费率经服务键 `'modelRate'` 注入，缺省关闭。
- S2：`tool_budget_policy.dart` + `tool_budget_hooks.dart`；中间件 tag `toolBudget`，
  事件 `tool.budget`；未调 `provideToolBudget` 时零影响。
- S3：`execution_profile.dart` + `execution_profile_rubric.dart`；缺 llm 或档位表时
  `provideProfileSelector` 返回 `null`（等于关闭）。
- S4（4.4 的纯函数部分）：`pareto.dart`——帕累托过滤 + 归一化加权平方距离三档选型；
  退化（极值相等、空集、全部相同）都有测试覆盖。
- 偏差：未调整 `tool_result_eviction` 默认阈值（见计划文档「范围修正」）；nava 侧
  配置开关未接入，后续按需接。

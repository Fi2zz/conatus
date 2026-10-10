# conatus_agent

conatus 的 Agent Loop 与产品化能力层：在 `conatus_llm` /
`conatus_foundation` / `conatus_compaction` 之上组装完整 Agent。每个能力
都是可独立启用的 `provide*` 装配点，未提供时对应能力缺省关闭或降级。

## 用法

```dart
import 'package:conatus_agent/conatus_agent.dart';

final agent = provideAgentLoop(app, session: session);
final turn = await agent.run('现在几点？');
print(turn.reply);
for (final step in turn.steps) print('${step.call.name}: ${step.result.content}');
```

一轮 `run(userInput)`：写入用户事件并压缩上下文 → 组装 system +
会话事件派生的历史 → 调 `LlmProvider.chat`（带工具 schema）→ 有工具调用
就执行、结果回填继续 → 纯文本收口。依赖 `llm` + `tools` 两个服务；
`systemPrompt` / `compaction` / `memory` / `sessions` / `sessionLogRecorder` /
`contextCache` 存在时自动接入。

## 能力一览

| 能力 | 入口 | 说明 |
|------|------|------|
| Agent Loop | `provideAgentLoop`（服务键 `'agentLoop'`） | 会话事件 + prompt 装配 + 压缩 + 记忆 + 工具闭环；循环有界（`maxSteps` 默认 8） |
| 规划 | `providePlanTool` / `providePlanMode` / `runPlanningPhase` | `plan` 工具读写持久计划；Plan Mode 只读规划→`exit_plan_mode` 批准后执行 |
| 子 Agent | `provideSpawnAgent` | `spawn_agent` 委托：独立 Session + 受限 ToolRegistry，只回传结论；白名单按风险过滤，复用宿主审批/中间件管线 |
| 自省与重试 | `provideReflection` | 失败轮次反思，`reflectAndRetry` 按策略重试 |
| 目标延续 | `provideGoal` | 长期目标（`Goal`）驱动多轮延续，`GoalRoundDriver` 按轮推进 |
| 审批 | `provideApproval` / `instrumentApproval` | `Approval` 契约 + `AskUserApproval` / `AutoApproval` / `RuleBasedApproval`；中间件形式挂进工具管线 |
| 遥测 | `provideTelemetry` | `Telemetry` 契约 + console / in-memory 实现；`instrumentTools` 埋点，`TelemetryLlmProvider` 包模型调用 |
| 评估 | `EvalRunner` / `Evaluator` / `EvalJudge` | 固定用例跑一轮 Agent，产出 `EvalReport` 对比 |
| 压缩 | `provideLayeredCompaction` | 在 `conatus_compaction` 契约上分层折叠（工具结果压成指针、用户偏好留原文），`RuleBasedContentClassifier` 分类 |
| 缓存 | `provideContextCache` | 可缓存前缀指纹与命中度量（`LlmMessage.cacheable` 不进请求体） |
| 大结果驱逐 | `provideToolResultEviction` | 超阈值工具结果落盘，上下文只留预览 |
| 技能沉淀 | `SkillTool` / `provideSkillLibrary` | 对话中沉淀可复用技能步骤 |
| 恢复 | `provideRecovery` | `SnapshotStore`（内存 / database 后端）保存与恢复会话状态 |
| 路由 | `provideRouter` | 确定性路由 seam：`RouteReply` / `RouteTools` / `RoutePass`（`conatus_intent` 接这里） |
| 自主运行 | `provideAutonomousRunner` | 无人值守多轮运行，`AutonomousPolicy` 限成本 / 限时窗 |
| prompt 演化 | `providePromptEvolver` | 按失败模式生成 prompt 变体，`PromptStore` 管理 |

## Session Log 集成

`provideSessionLogRecorder`（`SessionLogRecorder`）镜像业务事件并追加
`llm/request` / `llm/response` / `tool/call` 派生事件；
`checkModelVisibleInvariant` 校验「模型可见即已记录」不变式。
`conatus_observability` 的 trace 派生、`conatus_tasks` 的任务树都建立在这层
事件流上。

## 注意

- 工具失败作为失败结果回填，**不中断循环**；会话在循环中被关闭会中止
  （`StateError`）。
- 每一轮 `run()` 都是真实模型调用，消耗 token；子 Agent 按成员数放大。
- 所有依赖可注入（LLM / 工具 / 会话 / 时钟），测试用手写 Fake 与脚本化
  替身，不依赖 mock 框架。
- 依赖方向：`conatus_agent → conatus_llm / conatus_foundation /
  conatus_compaction → conatus_core`，反向不成立；本包不依赖任何实验性包。

完整机制（Plan Mode、子 Agent 权限、反思策略等）与各能力的详细用法见仓库根
[README](../../README.md) 的「内置插件」章节；贡献与约定见
[AGENTS.md](../../AGENTS.md)。

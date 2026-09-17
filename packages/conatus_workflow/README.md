# conatus_workflow

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的编排引擎：把多 Agent 协作**沉淀为可复用的流程资产**。`conatus_team` 回答
「一次协作会话怎么做」，本包回答「把成功的协作过程变成可复用、可命名的流程」——
流程是**数据**（声明式 JSON），不是代码，可被模型生成、被用户编辑、被版本管理。

## 用法

```dart
// 依赖：team（成员/工具节点执行）与 tools（工具节点）必需，其余 seam 可选
provideAgentTeam(app, session: session, ...);
provideWorkflow(
  app,
  team: app.team,
  tools: app.tools,
  taskCenter: ...,   // 节点执行作为 Task
  session: ...,      // 运行图持久化
  approval: ...,     // 高危节点审批（缺省自动批准）
  telemetry: ...,    // 埋点
);
final WorkflowEngine engine = app.workflow;

// 8 个面向模型的流程工具
provideWorkflowTools(app);

// 注册一个声明式流程并启动
await engine.register(WorkflowDefinition(
  name: 'code-review',
  version: 1,
  nodes: <WorkflowNode>[ /* ToolNode / AgentNode / SubWorkflowNode */ ],
));
final WorkflowRun run = await engine.start('code-review', inputs: {...});
```

## 流程定义

- `WorkflowDefinition`：`name`（唯一）+ `version` + `nodes` + 输入/输出声明，
  纯 JSON 可序列化（`toJson` / `fromJson`）。
- 三种节点（`WorkflowNode` 密封类，按 `type` 分派反序列化）：
  - `ToolNode` — 调用已注册工具；
  - `AgentNode` — 委派一个成员（`AgentTeam`）执行；
  - `SubWorkflowNode` — 嵌套运行另一个流程（递归深度受 `maxDepth` 限制，默认 5）。
- 节点可声明 `dependsOn`（DAG，全部依赖完成才执行）与 `when` 条件
  （`evaluateCondition`，基于可序列化状态求值——**确定性 guard**，不能依赖随机数 /
  时间戳等不确定因素）。

## 运行与状态机

- `WorkflowRun` / `RunNode`：每次 `start` 产生一次独立运行记录，运行图可序列化，
  支持暂停 / 恢复 / 重跑 / 取消。
- `RunStatus`：`pending → running ⇄ paused → completed` / `failed` / `cancelled`。
- `RunNodeStatus`：`pending → ready → running → completed` / `skipped`（条件不满足）/
  `failed`。
- 引擎 `changes` 是事件流：`WorkflowRegistered` / `RunStarted` / `RunNodeStarted` /
  `RunNodeCompleted` / `RunNodeFailed` / `RunNodeSkipped` / `RunCompleted` / `RunFailed`。

## 模型工具（8 个）

`provideWorkflowTools` 一次性注册：

- 创建与执行：`workflow_create` / `workflow_list` / `workflow_run` /
  `workflow_status`
- 运行控制：`workflow_pause` / `workflow_resume` / `workflow_rerun` /
  `workflow_cancel`

语音场景（如 TUI / 手机端）可注入 `WorkflowVoice` seam 把运行事件转成 TTS 文案
（`workflowCreatedMessage` 等纯函数，本包不直接依赖 `conatus_tts`）；语音审批由装配方
把 `AskUserApproval` 的语音版注入 approval seam。

## 运行时 seam（全部可选注入）

| seam | 用途 | 缺省行为 |
|------|------|----------|
| `team` / `tools` | 成员与工具节点执行 | 必需（缺省取 `ctx.team` / `ctx.tools`） |
| `taskCenter` | 节点执行作为 Task | 不追踪 |
| `session` | 运行图持久化 | 内存状态 |
| `approval` | 高危节点审批 | 自动批准 |
| `telemetry` | 埋点 | 无埋点 |
| `store` | 流程定义存储 | `InMemoryWorkflowStore` |

## 注意与限制

- **能力约束**：流程定义只能引用**已注册的能力**（工具、成员、子流程），不能引用
  任意代码；未注册的引用在注册 / 执行时报 `WorkflowException`。
- **每次节点执行都是一轮真实模型调用**，消耗 token；子流程按 `maxDepth` 限制递归
  深度。
- 运行控制（暂停 / 恢复 / 重跑）在节点边界生效：暂停在当前节点完成后停下，重跑
  级联重置下游节点。
- 依赖方向：`conatus_workflow → conatus_team → conatus_agent → conatus_core`，
  反向不成立；`conatus_agent` / `conatus_team` 不依赖本包。
- 设计细节见仓库根 `handoff-workflow.md`。

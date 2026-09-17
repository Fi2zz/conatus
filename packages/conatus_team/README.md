# conatus_team

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的多智能体协作包：当任务需要多个 Agent 配合时，回答「谁创建谁、谁跟谁说话、
怎么同步进度、什么时候停」。与单次委托 `spawn_agent` 的区别——成员有**独立的上下文
窗口**，不共享消息历史，只经任务板与直达消息交换**结论**、不交换**过程**；可并行
探索、互相审查、动态分工。

## 用法

```dart
// 基础设施：工具 / 模型 / 队长会话（demo 见 example/demo.dart，完全离线）
final ToolRegistry tools = provideTools(app);
provideLlm(app, llm: ...);

// 装配团队：四条 seam 全可选，缺省 no-op
provideAgentTeam(
  app,
  session: session,        // 队长记录团队事件
  telemetry: telemetry,    // 记录 team.* 埋点
  approval: ...,           // 高危成员创建 / 打断走审批（缺省自动批准）
  taskTracker: ...,        // 成员工作作为 subAgent 任务落进任务树
);
final AgentTeam team = app.team;

// 10 个面向模型的团队工具，一键注册
provideTeamTools(app, team: team, tools: tools);
```

完整端到端示例（并发审查 → Maker-Checker 修订 → 任务板 DAG → 中途移除）：
`cd packages/conatus_team && dart run example/demo.dart`，无需 API Key。

## 核心概念

**角色与成员状态**

- `TeamRole`：`lead`（队长，创建成员、分配任务）/ `member`（成员，领取任务、汇报结果）
- `TeammateStatus`：`idle → working → waiting → finished`（非终态，可再接任务）→
  `done` / `failed`（终态）

**任务板 `TeamBoard`**：唯一的同步点。成员不直接读写彼此状态，所有协调经任务板；
任务有 `dependsOn` 依赖（DAG），只有依赖完成的任务才能被领取，更新用 CAS 乐观锁防
互相覆盖。任务状态：`pending → claimed → done` / `failed`。

**成员运行时 `MemberRuntime`**：每个成员是队长下的一棵子 Context，持有独立
`Session` + `AgentLoop` + 取消信号。**成员生命周期绑定队长**——队长释放时所有成员
自动终止（与 `EffectScope` 可逆效应语义一致）。

**协作模式 `TeamPattern`**（`patterns/`，策略层，复用同一套机制）：

| 模式 | 说明 |
|------|------|
| `sequential` | 顺序执行，前一个成员的结果喂给下一个 |
| `concurrent` | 多个独立成员并行工作（如从性能/安全/产品三角度审查同一段代码） |
| `group_chat` | 成员群聊，互相交流结论 |
| `maker_checker` | 一个提案、另一个挑毛病，循环直到满意 |

## 模型工具（10 个）

成员与任务板各一组，`provideTeamTools` 一次性注册：

- 成员：`spawn_teammate` / `send_message` / `followup_task` / `list_agents` /
  `wait_agent` / `interrupt_agent`
- 任务板：`team_task_create` / `team_task_list` / `team_task_get` /
  `team_task_update`

`spawn_teammate` 与 `interrupt_agent` 为 medium 风险，审批在
`AgentTeam.spawn` / `interrupt` 内部经 `TeamHooks.approval` 完成，工具层不重复拦截。

## 运行时 seam（`TeamHooks`，全部可选）

| seam | 用途 | 缺省行为 |
|------|------|----------|
| `taskTracker` | 成员工作作为 Task 落进任务树 | 不追踪 |
| `session` | 队长记录团队事件 | 内存状态，不持久化 |
| `approval` | 高危成员创建 / 打断走审批 | 自动批准 |
| `telemetry` | 记录 `team.*` 事件 | 无埋点 |

## 注意与限制

- **每次成员轮次都是一轮真实模型调用**，消耗 token；并发模式按成员数放大。
- 成员只交换结论，不共享过程——需要全量上下文的任务不适合拆给多个成员。
- 依赖方向：`conatus_team → conatus_agent → conatus_llm → conatus_core`，
  `conatus_agent` 不依赖 `conatus_team`，实验包不污染稳定包依赖面。
- 设计细节见仓库根 `handoff-team.md`。

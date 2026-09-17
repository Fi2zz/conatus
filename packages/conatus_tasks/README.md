# conatus_tasks

conatus 的任务中心（Task Center）：运行时的**任务追踪中枢**——只回答「现在有哪些
任务在跑、各自什么状态、能不能取消」，**不负责调度与执行**。任务由运行时组件
（Agent Loop / sub-agent / shell / schedule）自动创建，模型侧只有只读与治理工具。

## 用法

```dart
// 装配任务中心：服务键 'tasks'（ctx.tasks）
final TaskCenter tasks = provideTaskCenter(
  ctx,
  session: session,      // 可选：task/changed 事件持久化到会话
  approval: approval,    // 可选：cancel_task 对 shell 类任务的确认（缺省自动批准）
  telemetry: telemetry,  // 可选：task.* 埋点
  // registerTools: false  // 关闭模型工具注册
);

// 挂运行时追踪：Agent Loop / spawn_agent / shell / schedule 现有代码零改动
provideTaskTracking(ctx);
```

TUI 场景经会话装配钩子接线（见 `conatus_tui` 的 `configureSession`）：

```dart
controller.configureSession = (Context ctx, Session session) {
  provideTaskCenter(ctx, session: session);
  provideTaskTracking(ctx); // ctx.inject(['agentLoop']) 立即可激活
};
```

## 状态机与类型

**状态** `TaskStatus`：`pending → running ⇄ paused`，任一非终态可转
`completed` / `failed` / `cancelled`；**终态不可再变更**。

**类型** `TaskKind`：

| 类型 | 来源 |
|------|------|
| `agentTurn` | Agent Loop 的一轮（`AgentLoop.turnTracker`，metadata 关联 goalId / planMode） |
| `subAgent` | `spawn_agent` 委托（中间件按结果值 `status` 判定成败） |
| `shell` | 后台 / 前台 shell 执行（`TrackingShellExecutor`） |
| `schedule` | 定时提醒交付（`trackScheduleDelivery`） |
| `custom` | 宿主自定义 |

任务按 `parentTaskId` 组成**任务树**（Goal → Agent Turn → Sub-Agent → Shell），
`cancel` 级联取消活跃子任务并执行注册的取消回调。

## 模型工具

`provideTaskCenter` 默认注册两个工具（不暴露 `create`——任务由运行时自动创建）：

- `list_tasks`（low，只读）— 按 `status` / `kind` / `parent_id` 过滤，输出口语化
  播报文本（`describeTasks`，面向语音场景）。
- `cancel_task`（medium）— 取消任务；shell 类任务走 `approval` 确认。

## 持久化与恢复

- 每次状态变更以 `task/changed` 事件**整值替换**写入会话（append-only，按任务 id
  折叠最后一个），会话落盘后重启即可重建任务树。
- 恢复时未完成的活跃任务统一标记 `failed`（原因：`进程重启，执行环境已丢失`）。
- 派生状态只折叠会话自身后缀（`Session.ownEvents`）——fork 出的会话**不继承**父
  会话的任务树。

## 运行时 seam（全部可选，缺省降级）

| seam | 用途 | 缺省行为 |
|------|------|----------|
| `session` | `task/changed` 事件持久化 | 内存状态 |
| `approval` | `cancel_task` 确认 | 自动批准 |
| `telemetry` | `task.*` 埋点 | 无埋点 |
| `tools` | 模型工具注册目标 | `ctx.tools` |

依赖方向：`conatus_tasks → conatus_agent / conatus_core / conatus_foundation /
conatus_schedule`，反向不成立；中心不依赖任何运行时组件，追踪器由
`provideTaskTracking` 一次性挂好。

## 注意

- **每次轮次都是真实模型调用**：`agentTurn` 任务覆盖整个 Agent Loop 轮次
  （beginTurn 创建并置 running，endTurn 收 completed / failed）。
- 设计细节见仓库根 `handoff-tasks-center.md`；TUI 接线见
  `handoff-tasks-tui-wiring.md`。

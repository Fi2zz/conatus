# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——多智能体协作：成员有独立上下文窗口，只交换结论、不交换过程：

- `AgentTeam`（经 `provideAgentTeam` 装配）+ `MemberRuntime`：每个成员是
  队长下的一棵子 Context（独立 Session + AgentLoop + 取消信号），
  成员生命周期绑定队长——队长释放时全部自动终止（与 `EffectScope`
  可逆效应语义一致）
- `TeamBoard` 任务板：唯一同步点，任务 `dependsOn` 组成 DAG，
  依赖完成才能领取，CAS 乐观锁防互相覆盖
- 协作模式 `TeamPattern`：`sequential` / `concurrent` / `group_chat` /
  `maker_checker`（曾修复驳回被误判为通过的缺陷）
- `provideTeamTools`：10 个面向模型的团队工具（成员 6 个 + 任务板 4 个）；
  `spawn_teammate` / `interrupt_agent` 为 medium 风险，审批在
  `AgentTeam.spawn` / `interrupt` 内部完成
- 运行时 seam（`TeamHooks`，全部可选）：`taskTracker`（成员工作落进任务
  树）/ `session`（队长记录团队事件）/ `approval` / `telemetry`
- 成员活动事件 + 实时泳道视图（TUI 泳道、子 Agent 并入同一视图）；
  端到端离线 demo（`example/demo.dart`，无需 API Key）

# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——任务中心（Task Center）：运行时任务追踪中枢，只回答「现在有
哪些任务在跑、各自什么状态、能不能取消」，不负责调度与执行：

- `TaskCenter`（服务键 `'tasks'`）+ `provideTaskCenter`：任务按
  `parentTaskId` 组成任务树（Goal → Agent Turn → Sub-Agent → Shell），
  `cancel` 级联取消活跃子任务并执行取消回调
- 状态机 `TaskStatus`：`pending → running ⇄ paused`，任一非终态可转
  `completed` / `failed` / `cancelled`，终态不可再变更
- `provideTaskTracking`：一次性挂上 Agent Loop / spawn_agent / shell /
  schedule 四类运行时追踪（`agentTurn` / `subAgent` / `shell` /
  `schedule`），既有代码零改动
- 模型工具：`list_tasks`（只读，`describeTasks` 口语化播报面向语音场景）/
  `cancel_task`（shell 类任务经 `approval` 确认）；不暴露 `create`
- 持久化：`task/changed` 事件整值替换写入会话（append-only 按任务 id
  折叠），重启后重建任务树，未完成的活跃任务统一标记 `failed`
  （执行环境已丢失）；fork 会话不继承父会话任务树

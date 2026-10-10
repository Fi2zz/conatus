# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——流程编排引擎：把多 Agent 协作沉淀为可复用、可命名的流程资产
（流程是声明式数据，不是代码）：

- `WorkflowDefinition` / `WorkflowNode`：纯 JSON 可序列化；三种节点密封类
  （`ToolNode` 调用已注册工具 / `AgentNode` 委派成员 / `SubWorkflowNode`
  嵌套子流程，`maxDepth` 默认 5）；节点 `dependsOn` 组成 DAG，
  `when` 条件是可序列化状态上的确定性 guard
- `WorkflowEngine` / `WorkflowRun` / `RunNode`：每次 `start` 产生独立运行
  记录，运行图可序列化，支持暂停 / 恢复 / 重跑 / 取消（节点边界生效）；
  `changes` 事件流（`RunStarted` / `RunNodeCompleted` / `RunFailed` 等）
- `WorkflowStore` 接口 + `InMemoryWorkflowStore` 内存实现
- `provideWorkflowTools`：8 个面向模型的流程工具（创建与执行 4 个 +
  运行控制 4 个）
- `WorkflowScheduler` / `Automation`：触发器 + 约束 + 后处理，让流程从
  「被调用的」变成「自动运行的」——触发器是数据（`CronTrigger` 复用
  `conatus_cron` 表达式、条件触发复用 `conatus_alerting` 的 `AlertRule`
  条件与冷却语义），手动触发不受 start/stop 影响
- `WorkflowVoice`：运行事件转 TTS 文案的纯函数 seam（不直接依赖
  `conatus_tts`）；运行时集成 `TaskCenter` / `Session` / `Approval` /
  `Telemetry`

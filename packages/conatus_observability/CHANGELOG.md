# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——可观测性导出器（当前落地 span 语义与 trace 派生，OTLP /
Prometheus / JSONL 导出器与成本追踪按实现方案陆续补齐）：

- `Span` / `SpanStatus`：不可变模型，字段与 OTel 对齐（`traceId` /
  `spanId` / `parentSpanId` / `name` / `startTime` / `duration` /
  `attributes` / `status`），spanId 派生自事件 id
- `TraceBuilder`：从 Session Log 事件流派生完整 trace——`user/message` →
  根 span `agent.turn`，`llm/request` × `llm/response`、`tool/call` ×
  `tool/result`、`team/spawned` × `team/removed` 按事件类型语义配对，
  不引入新埋点
- 已知近似：压缩等内部 LLM 调用派生为根级 span（不嵌套）；跨 session 的
  trace 关联尚未实现（子 Agent 的 `subagent.spawn` 只在本 session 内闭合）

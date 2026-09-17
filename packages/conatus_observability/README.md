# conatus_observability

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的可观测性导出器：把 agent 运行时的 `telemetry` 埋点与 `session_log` 事件流
**导出到真实可观测性后端**（OTel / Prometheus / JSONL），并提供分布式追踪与成本追踪
语义。当前已落地 **span 语义 + 从 Session Log 派生 trace**；OTLP / Prometheus /
JSONL 导出器、成本追踪与告警按实现方案陆续补齐。

## 用法

```dart
// 从 Session Log 为一个会话构建完整 trace
final TraceBuilder builder = TraceBuilder(sessionLog: log);
final List<Span> spans = await builder.buildTrace('session-1');

// spans 按开始时间排序；每个根 span 是 agent.turn，其下挂 llm/tool/subagent 子 span
for (final Span span in spans) {
  print('${span.name} ${span.duration} ${span.status}');
}
```

## 核心概念

**Span 语义（`Span` / `SpanStatus`）**：不可变模型，字段与 OTel 对齐——
`traceId` / `spanId` / `parentSpanId` / `name` / `startTime` / `duration` /
`attributes` / `status`（`unset` / `ok` / `error`）。spanId 派生自事件 id，根 span 的
id 即所属 trace 的 id。

**从 Session Log 派生（`TraceBuilder`）**：`session_log` 是线性因果链（每条事件的
`parentEventId` 指向前一条），树层级靠**事件类型语义配对**还原，不引入新埋点：

| 事件配对 | 派生 span | 配对键 |
|----------|-----------|--------|
| 每条 `user/message` | `agent.turn`（根） | — |
| `llm/request` × `llm/response` | `llm.request` | 最近的未闭合 llm span |
| `tool/call` × `tool/result` | `tool.call` | `callId` |
| `team/spawned` × `team/removed` | `subagent.spawn` | `teammateId` |

`startTime` / `duration` 从事件时间戳派生；`tool/result` 带 `isError` 时状态为
`error`；没有结束事件（如 `llm/request` 缺 `llm/response`）的 span 状态保持 `unset`。

## 注意与限制

- **导出失败不阻塞主流程**：后续 OTel 导出器失败只记录 stderr，不抛异常。
- **跨 session 的 trace 关联尚未实现**：子 Agent 运行在独立 session，`subagent.spawn`
  目前只在本 session 日志内闭合。
- **压缩等内部 LLM 调用**也落 `llm/request` 事件，派生为根级 `llm.request` span
  （不嵌套），属已知近似。
- 依赖方向：`conatus_observability → conatus_agent → conatus_llm → conatus_core`，
  反向不成立；`conatus_agent` 不依赖本包。
- 设计细节见仓库根 `handoff-observability.md` 与 `.handoffs/HANDOFF-8.md`。

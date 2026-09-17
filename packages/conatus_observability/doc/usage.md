# conatus_observability 使用文档

> 面向使用方：如何把 agent 运行时的事件流变成可观测的 trace。
> 本包当前已落地 **span 语义 + `TraceBuilder`**（从 `session_log` 派生 trace）；
> OTel / Prometheus / JSONL 导出器、成本追踪与告警按 `.handoffs/HANDOFF-8.md`
> 陆续补齐。

## 1. 安装

本包为实验性包（`publish_to: none`），不进入 `conatus` 伞包，需显式依赖。
仓库内使用方在 `pubspec.yaml` 声明：

```yaml
dependencies:
  conatus_observability: ^0.15.0
```

依赖方向：`conatus_observability → conatus_agent → conatus_llm → conatus_core`，
`conatus_agent` 不依赖本包。

## 2. 两条使用路径

`TraceBuilder` 从 `SessionLog` 读事件、派生出 `Span` 列表。事件可以来自：

- **真实装配**（推荐）：`provideSessionLog` + `provideSessionLogRecorder` 在 agent
  运行时自动落盘 `llm/request`、`llm/response`、`tool/call` 等派生事件；
- **离线/测试**：用 `InMemorySessionLog` 手工喂事件，验证派生逻辑（见
  `example/observability_demo.dart`）。

## 3. 真实装配示例

```dart
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_observability/conatus_observability.dart';

Future<void> main() async {
  final Context app = Context();

  // 1) 会话日志：默认 InMemorySessionLog；传 persistence 可换追加式 JSONL 后端
  provideSessionLog(app);
  // 2) 记录器：镜像业务会话，并补记 llm/tool 派生事件
  provideSessionLogRecorder(app);
  // 3) 业务会话 + Agent Loop：recorder 存在时自动 attach 并挂工具埋点
  final Session session = app.sessions.create();
  provideAgentLoop(app, session: session);

  // …… 运行若干轮 agent（app.agentLoop.run(...)）……

  // 4) 从日志派生完整 trace
  final TraceBuilder builder = TraceBuilder(sessionLog: app.sessionLog);
  final List<Span> spans = await builder.buildTrace(session.id);

  for (final Span span in spans) {
    print('${span.name} ${span.startTime} +${span.duration} ${span.status}');
  }
}
```

## 4. Span 语义

`Span` 是不可变模型，字段与 OTel 对齐：

| 字段 | 含义 |
|------|------|
| `traceId` | 所属 trace 标识（根 span 的 id） |
| `spanId` | 本 span 标识（派生自事件 id） |
| `parentSpanId` | 父 span 标识；根 span 为 `null` |
| `name` | `agent.turn` / `llm.request` / `tool.call` / `subagent.spawn` |
| `startTime` / `duration` | 从事件时间戳派生；负时长钳为 0 |
| `attributes` | 事件负载（如 provider / model / callId） |
| `status` | `unset` / `ok` / `error` |

`session_log` 是**线性因果链**（`parentEventId` 指向前一条），因此层级靠事件类型
语义配对还原，不依赖 `parentEventId`：

| 事件配对 | 派生 span | 配对键 |
|----------|-----------|--------|
| 每条 `user/message` | `agent.turn`（根） | — |
| `llm/request` × `llm/response` | `llm.request` | 最近的未闭合 llm span |
| `tool/call` × `tool/result` | `tool.call` | `callId` |
| `team/spawned` × `team/removed` | `subagent.spawn` | `teammateId` |

## 5. 状态与边界

- `tool/result` 带 `isError: true` → `tool.call` 状态 `error`；其余配对闭合 → `ok`。
- 没有结束事件（如 `llm/request` 缺 `llm/response`）→ 在日志末尾闭合，状态
  `unset`，时长为到日志末尾的间隔。
- 根 span 在**下一条 `user/message` 或日志末尾**闭合，覆盖一次完整轮次；
  每次 `user/message` 生成一个独立 trace（`traceId` 各不相同）。
- 无 `user/message` 的会话（如纯团队会话）：子 span `parentSpanId` 为 `null`、
  `traceId` 为空。

## 6. 已知限制

- **跨 session 的 trace 关联未实现**：子 Agent 在独立 session 运行，
  `subagent.spawn` 目前只在本 session 日志内闭合。
- **压缩等内部 LLM 调用**也会落 `llm/request` 事件，派生为根级 `llm.request`
  span（不嵌套）。
- 导出器（OTel / Prometheus / JSONL）、成本追踪与告警尚在规划中，届时
  `TraceBuilder` 的 `Span` 直接作为 OTLP span 的数据源。

## 7. 可运行示例

`cd packages/conatus_observability && dart run example/observability_demo.dart`
（完全离线，不需要 API Key，输出派生 span 的层级与耗时）。

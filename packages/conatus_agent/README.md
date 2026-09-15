# conatus_agent

conatus 的 Agent Loop 与产品化能力：

- `AgentLoop` — 会话事件 + prompt 装配 + 压缩 + 记忆 + 工具闭环
- Session Log 集成 — `SessionLogRecorder` 镜像业务事件并追加 `llm/request` /
  `llm/response` / `tool/call` 派生事件；`checkModelVisibleInvariant` 校验「模型可见即已记录」
- `compaction` / `layered-compaction` + `content-classifier` — 滚动摘要，或按内容类别分层压缩
- `context-cache` — 可缓存前缀指纹与缓存命中度量（`LlmMessage.cacheable` 不进请求体）
- `plan` / `sub-agent` / `reflection`
- `telemetry` / `evaluation` / `approval` / `skill` / `recovery` / `tool-result-eviction`

```dart
import 'package:conatus_agent/conatus_agent.dart';

final agent = provideAgentLoop(app, session: session);
final turn = await agent.run('现在几点？');
print(turn.reply);
```

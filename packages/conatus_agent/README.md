# conatus_agent

conatus 的 Agent Loop 与产品化能力：

- `AgentLoop` — 会话事件 + prompt 装配 + 压缩 + 记忆 + 工具闭环
- `compaction` / `plan` / `sub-agent` / `reflection`
- `telemetry` / `evaluation` / `approval` / `skill` / `recovery` / `tool-result-eviction`

```dart
import 'package:conatus_agent/conatus_agent.dart';

final agent = provideAgentLoop(app, session: session);
final turn = await agent.run('现在几点？');
print(turn.reply);
```

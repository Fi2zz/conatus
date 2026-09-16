# conatus_foundation

conatus 的基础设施插件（仅依赖 `conatus_core`，零外部依赖）：

- `timer` — 定时器即可逆效应（`timeout` / `interval` / `sleep` / `throttle` / `debounce`）
- `logger-console` — 分级日志服务 + 控制台导出
- `loader` — 按名注册的插件工厂 + 配置树
- `tools` — `Tool` 基类 + `ParamSpec` + 注册表 / 受控执行管线 / 分组 / 分级
- `shell` / `fs` — 命令执行与文件系统能力缝 + 本地实现
- `session` — append-only 事件日志 + 会话仓库 + JSONL 持久化（`SessionEvent` 带 `id` / `sessionId` / `parentEventId`，`toJson()` 对负载自动脱敏；`Session` 支持 `read` / `fork` / `replay`）
- `session-log` — 多会话只追加日志（内存 / 追加式 JSONL / Database 三后端），支持 `fork` / `replay`
- `system-prompt` — prompt 段与动态上下文装配（`render` / `renderContexts`）
- `time-context` — 日粒度日期锚点（`provideTimePrompt`：日期 + 星期 + 时区）
- `memory` — 长记忆库（`remember` / `recall` / `forget` / `forgetByText` / `forgetMatching`），另有 `remember` / `forget` 工具
- `database` — KV 存储 hub + 可插拔后端
- `ask_user` — 声明式提问

```dart
import 'package:conatus_foundation/conatus_foundation.dart';

final tools = provideTools(app);
app.effect(() => tools.fn('get_time', handler: (ctx) async {
  final now = DateTime.now();
  return ToolResult.success(
      '${now.toIso8601String()}${formatClockOffset(now.timeZoneOffset)}');
}));
```

## 日期锚点

模型没有时钟，相对日期与带本地语义的时刻都需要外部锚点。`provideTimePrompt` 把
「今天」注册成一份 system prompt 动态上下文（日粒度：`2026-09-16 周三 · Asia/Shanghai
(UTC+08:00)`），每轮装配重新求值：

```dart
final prompt = provideSystemPrompt(app);
provideTimePrompt(app);                         // 本地时区名
provideTimePrompt(app, zoneName: 'Asia/Shanghai');
provideTimePrompt(app, clock: () => fixedNow);  // 固定时钟，便于测试
```

它要排在 `provideSystemPrompt` 之后（否则抛 `StateError`）。精确到秒请交给时间工具，
偏移格式化用 `formatClockOffset`。完整说明见根 README 的 `time-context` 小节。

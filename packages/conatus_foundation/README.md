# conatus_foundation

conatus 的基础设施插件（仅依赖 `conatus_core`，零外部依赖）：

- `timer` — 定时器即可逆效应（`timeout` / `interval` / `sleep` / `throttle` / `debounce`）
- `logger-console` — 分级日志服务 + 控制台导出
- `loader` — 按名注册的插件工厂 + 配置树
- `tools` — `Tool` 基类 + `ParamSpec` + 注册表 / 受控执行管线 / 分组 / 分级
- `shell` / `fs` — 命令执行与文件系统能力缝 + 本地实现
- `session` — append-only 事件日志 + 会话仓库 + JSONL 持久化
- `system-prompt` — prompt 段装配
- `memory` — 长记忆库
- `database` — KV 存储 hub + 可插拔后端
- `ask_user` — 声明式提问

```dart
import 'package:conatus_foundation/conatus_foundation.dart';

final tools = provideTools(app);
app.effect(() => tools.fn('get_time', handler: (ctx) async {
  return ToolResult.success(DateTime.now().toIso8601String());
}));
```

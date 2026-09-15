# conatus_tui

基于 [nocterm](https://pub.dev/packages/nocterm) 的 conatus 文本 TUI：用
Agent Loop 驱动多轮对话，把会话事件投射为屏上消息，并提供斜杠命令菜单、
会话选择面板与顶栏 / 状态栏。

## 运行

```bash
# 在仓库根目录
export ARK_API_KEY="你的火山方舟 API Key"       # 豆包（首选）
export DEEPSEEK_API_KEY="你的 DeepSeek Key"     # DeepSeek（备选）
dart run conatus_tui
```

可选参数：

```bash
dart run conatus_tui --session tui --first "现在几点？"
```

`--session <id>` 指定启动会话（对应 `.conatus/sessions/<id>.jsonl`）；
`--first <文本>` 挂载后自动发一轮，便于冒烟验证。

## DeepSeek Demo

`example/deepseek_demo.dart` 用 conatus 的 `DeepSeekProvider` 驱动 TUI；
未设置 `DEEPSEEK_API_KEY` 时退回离线脚本模型（时间类问题仍会走 `get_time` 工具），
无 Key 也能预览界面：

```bash
# 真实调用 DeepSeek
export DEEPSEEK_API_KEY="sk-..."
dart run packages/conatus_tui/example/deepseek_demo.dart

# 指定模型 / 会话 / 首轮
dart run packages/conatus_tui/example/deepseek_demo.dart \
  --model deepseek-chat --session demo --first "现在几点？"
```

## 功能

- **对话 + 工具闭环**：`AgentLoop` 自动接入 llm / tools / system-prompt /
  memory / compaction / reflection，工具调用与结果实时回显到记录区。
- **斜杠命令**：输入 `/` 弹出命令菜单（`↑↓` 选择、`Enter` 运行、`Tab` 补全）：
  `/help` `/new` `/session <id>` `/sessions` `/tools` `/remember <内容>` `/forget <id 或 关键字>` `/telemetry` `/clear` `/exit`。
- **会话选择面板**：`/sessions` 打开，`↑↓` 选择、`Enter` 切换、`Esc` 关闭；
  会话事件以 JSONL 持久化到 `.conatus/sessions`，重启后 `open` 即恢复历史。
- **长记忆**：`.conatus/memory.json` 跨会话召回。
- **状态栏**：思考动画、按键提示与 Ctrl+C 连按两次退出。

## 作为库使用

```dart
import 'package:conatus_tui/conatus_tui.dart';

final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create();
final ConatusTuiController controller = runtime.createController(
  initialSession: 'tui',
  onExit: shutdownApp,
);
await runApp(AgentTui(controller: controller));
await runtime.dispose();
```

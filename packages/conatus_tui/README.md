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
`--first <文本>` 挂载后自动发一轮，便于冒烟验证；`--help` / `-h` 打印用法。

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
- **技能加载**：从 `.conatus/skills`、`.agents/skills` 与用户技能目录发现
  `SKILL.md` 指令集，目录注入 system prompt，模型按需用 `skill` 工具取回正文；
  `ConatusTuiRuntime.create(skills: false)` 可关闭。注意它与 `provideSkillLibrary`
  （把重复工具序列沉淀成新工具）不是同一件事。
- **技能直接调用**：每个已发现的技能同时是一条 `/<技能名> [补充要求]` 命令，
  跟着 `/` 菜单一起过滤与补全。执行时把技能正文展开成一轮用户输入交给模型
  （照常进 `user/message` 事件），屏上折回一行 `/<技能名> …`。
  `disable-model-invocation` 的技能不进模型目录，但用户仍能这样手动触发。
- **状态栏**：思考动画、按键提示与 Ctrl+C 连按两次退出；左侧常显当前权限模式。
- **选项浮层**：`↑↓` 选择、`Enter` 确认、`Esc` 取消。模型可用 `ask_user` 工具
  把候选选项交给你选；工具审批复用同一浮层。

## 权限模式

三档审批强度，由模型经 `ask_user(purpose: permission_mode)` 询问后切换：

| 模式 | 拦截阈值 | 行为 |
| --- | --- | --- |
| 始终询问 `alwaysAsk` | `ToolRisk.medium` | 只读操作自动放行，其余都要先批准 |
| 按需询问 `askWhenNeeded` | `ToolRisk.high` | 常规改动自动执行，高危操作仍会询问（默认） |
| 从不询问 `neverAsk` | 不挂审批 | 不打断，所有操作自动执行 |

被拦截时弹出「允许一次 / 信任此文件夹 / 总是允许该工具 / 拒绝」；选「总是允许」
会在**当前会话**内记住该工具（切会话即清空）。

**信任此文件夹**（仅对声明了路径参数的工具出现，如 `read_file`）按「工具 + 目录」
记住授权：之后该工具访问该目录及其子孙都不再询问，目录之外仍会问，换一个工具
也会重新问。判定用 `FileSystem.contains`，因此是真正的目录包含关系而非字符串前缀。

> 声明路径参数的工具（`Tool.pathParams`）即使风险为 `low` 也会进入审批——
> 这正是「读文件也要按目录授权」的落点。

模式**按会话持久化**：以 `permission/mode` 事件追加到会话日志（append-only，折叠
最后一条），因此切回某个会话即恢复它自己的模式，重启 TUI 后依然生效。fork 出的
会话不继承父会话的模式（与 `plan/mode` 同款语义）。信任记录与权限模式不同，是
**内存态**、随会话切换清空。

## 作为库使用

`conatus_tui` 把 `nocterm` 的 API 一并再导出：挂载界面用的 `runApp` /
`shutdownApp`、自定义视图用的 `Component` / `Text` 都在其中，因此调用方的
`pubspec.yaml` 只需要声明 `conatus_tui`，不必再装一份 `nocterm`。

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

唯一例外是 nocterm 自带的两个终端 matcher（`isEmpty` / `isNotEmpty`）：它们与
`package:test` 的同名 matcher 冲突，已从再导出里屏蔽，需要时直接依赖 nocterm
用前缀引入。

## 复用命令行解析

`TuiOptions` 就是可执行入口用的那套解析，自己的入口可以直接复用，不必再抄一遍
`--session` / `--first` 的处理：

```dart
final TuiOptions options = TuiOptions.parse(args);
if (options.helpRequested) {
  stdout.write(TuiOptions.usage);   // 解析本身不打印也不退出
  return;
}
final ConatusTuiController controller = runtime.createController(
  initialSession: options.session,
  onExit: shutdownApp,
);
await runApp(AgentTui(controller: controller, firstInput: options.first));
```

缺省会话 id 是 `kTuiDefaultSession`（`tui`）。

## 自定义命令表

`TuiCommandMenu` 的命令来源可以注入，缺省是静态表 `tuiCommands`：

```dart
final TuiCommandMenu menu = TuiCommandMenu(commands: () => controller.commands);
```

`ConatusTuiController.commands` 就是「静态命令 + 技能命令」的合并结果，技能注册表
变化后下一次过滤即生效。

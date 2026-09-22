# conatus

> 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
>
> 基于论文 *A Programming Paradigm for Spatiotemporal Composability*
> （arXiv:2608.25512）的核心机制。

本仓库是一个 [pub workspace](https://dart.dev/tools/pub/workspaces) monorepo。
**根包 `conatus` 是伞包（umbrella）**：自身不含实现，统一再导出 `packages/` 下的
14 个模块包，因此 `import 'package:conatus/conatus.dart';` 是完整公开 API；也可以
只依赖某个模块包（如 `conatus_core`、`conatus_agent`），以获得更小的依赖面。
仓库另有 7 个**实验性包**（`publish_to: none`，不导出到伞包，API 可能随时变更），
需显式依赖，见下方「实验性包」小节。

`packages/conatus_code` 是独立的**子模块**（[Fi2zz/conatus_code](https://github.com/Fi2zz/conatus_code)）：
基于本仓库构建的终端编码智能体，不在下表内、不进伞包。不开发它时无需拉取 ——
根 `pubspec.yaml` 的 `workspace` 用 glob，没有 `pubspec.yaml` 的目录会被跳过。

要开发它，先拉取子模块并安装 workspace filter：

```bash
git submodule update --init
tool/setup_code_filter.sh
```

filter 让子模块 `pubspec.yaml` 里的 `resolution: workspace` 在工作区保持生效（本仓库
的 pub workspace 因此把 conatus_code 当成员，依赖落到本地 `packages/*`，改框架对应用
立即生效），`git add` 时又自动把它注释掉 —— 推送出去的内容仍让独立 clone 按 git 依赖
解析。

| 包 | 说明 | 依赖 |
|----|------|------|
| [`conatus`](.) | 伞包（umbrella）：再导出以下全部，保持 `package:conatus/conatus.dart` 兼容 | 全部 |
| [`conatus_core`](packages/conatus_core) | 核心范式：`Context` / `EffectScope` / `Reactor`（零运行时依赖） | — |
| [`conatus_foundation`](packages/conatus_foundation) | 基础设施插件：timer / logger / loader / tools / shell / fs / session / session-log / system-prompt / memory / database / ask-user | `conatus_core` |
| [`conatus_credentials`](packages/conatus_credentials) | 凭据能力缝：环境变量 / 文件 / 内存 / Vault KV v2 / AWS Secrets Manager | `conatus_core`、`http` |
| [`conatus_llm`](packages/conatus_llm) | 大模型接入（豆包 / DeepSeek，chat 与 responses 两种形态） | `conatus_core`、`conatus_credentials`、`http` |
| [`conatus_search`](packages/conatus_search) | 搜索能力缝 + `web_search` / `fetch_url` | `conatus_core`、`conatus_foundation`、`http` |
| [`conatus_skill`](packages/conatus_skill) | 技能加载：发现 `SKILL.md` 指令集、目录注入 system prompt、`skill` 工具按需取正文 | `conatus_core`、`conatus_foundation`、`yaml` |
| [`conatus_asr`](packages/conatus_asr) | ASR 能力缝（豆包/火山流式识别）+ `transcribe_audio` + 可替换音频源 | `conatus_core`、`conatus_foundation` |
| [`conatus_tts`](packages/conatus_tts) | TTS 能力缝（豆包/火山语音合成）+ 可替换音频输出接口 | `conatus_core`、`http` |
| [`conatus_mcp`](packages/conatus_mcp) | MCP（Model Context Protocol）客户端：stdio / HTTP / SSE 传输 + 工具接入 | `conatus_core`、`conatus_credentials`、`conatus_foundation`、`http` |
| [`conatus_schedule`](packages/conatus_schedule) | 会话本地持久提醒：`schedule_create` / `schedule_list` / `schedule_delete` + 到期交付 | `conatus_core`、`conatus_foundation`、`timezone` |
| [`conatus_cron`](packages/conatus_cron) | 定时任务（dsh-cron 移植，不含 web）：at / every / daily / cron 规则 + `cron_list` / `cron_add` / `cron_update` / `cron_remove` / `cron_history` + 运行历史持久化 | `conatus_core`、`conatus_foundation` |
| [`conatus_compaction`](packages/conatus_compaction) | 压缩能力缝：滚动摘要契约 + `compaction/*` 日志事件 + 工具配对平衡切点 | `conatus_core`、`conatus_foundation` |
| [`conatus_agent`](packages/conatus_agent) | Agent Loop 与产品化：plan / sub-agent / reflection / telemetry / eval / approval / skill / recovery | `conatus_compaction`、`conatus_core`、`conatus_foundation`、`conatus_llm` |
| [`conatus_tasks`](packages/conatus_tasks) | 任务中心（Task Center）：Agent Loop / sub-agent / shell / schedule 运行时任务追踪（任务树 + `task/changed` 持久化 + `list_tasks` / `cancel_task` 工具） | `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_schedule` |
| [`conatus_tui`](packages/conatus_tui) | 基于 [nocterm](https://pub.dev/packages/nocterm) 的文本 TUI：对话 + 工具闭环、斜杠命令（含 `/skill:<技能名>` 直接调用技能）、会话选择面板、选项浮层与权限模式（再导出 nocterm，调用方无需另装） | `conatus_agent`、`conatus_compaction`、`conatus_cron`、`conatus_llm`、`conatus_schedule`、`conatus_search`、`conatus_skill`、`nocterm` |

### 实验性包（不进伞包，`publish_to: none`）

| 包 | 说明 | 依赖 | 文档 |
|----|------|------|------|
| `conatus_alerting` | 告警：订阅遥测事件流，声明式规则判定后主动通知 | `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_tts`、`http` | [README](packages/conatus_alerting/README.md) |
| `conatus_browser_use` | 浏览器操作：经 MCP 接 Playwright / Chrome DevTools，检查与交互网页 | `conatus_agent`、`conatus_core`、`conatus_credentials`、`conatus_foundation`、`conatus_mcp`、`conatus_tasks` | [README](packages/conatus_browser_use/README.md) |
| `conatus_computer_use` | 桌面操作：经 MCP 接 Cua Driver，截屏 / 鼠标 / 键盘 | `conatus_agent`、`conatus_core`、`conatus_credentials`、`conatus_foundation`、`conatus_mcp`、`conatus_tasks` | [README](packages/conatus_computer_use/README.md) |
| `conatus_fs_tools` | 文件系统工具：`read_file` / `write_file` / `edit_file` / `rg` / `glob`，对齐 DSH `dsh-tool-fs` | `conatus_agent`、`conatus_core`、`conatus_foundation`、`glob` | [README](packages/conatus_fs_tools/README.md) |
| `conatus_intent` | 意图路由：正则 + 向量本地匹配，命中走确定性动作，未命中落回 Agent Loop | `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_llm` | [README](packages/conatus_intent/README.md) |
| `conatus_observability` | 可观测性导出器：span 语义 + 从 Session Log 派生 trace | `conatus_agent`、`conatus_foundation` | [README](packages/conatus_observability/README.md) |
| `conatus_team` | 多智能体协作：任务板（DAG + CAS）+ 成员运行时 + 协作模式 | `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_llm` | [README](packages/conatus_team/README.md) |
| `conatus_workflow` | 编排引擎：声明式流程（数据，非代码）+ 运行状态机 | `conatus_agent`、`conatus_core`、`conatus_foundation`、`conatus_tasks`、`conatus_team` | [README](packages/conatus_workflow/README.md) |

依赖方向自上而下，无环：

```
conatus ─▶ conatus_agent ─▶ conatus_llm ─▶ conatus_core
                │           └▶ conatus_credentials ─▶ conatus_core
                ├▶ conatus_foundation ─▶ conatus_core
                └▶ conatus_compaction ─▶ conatus_foundation
conatus_mcp ────▶ conatus_foundation、conatus_credentials
conatus_schedule ▶ conatus_foundation、timezone
conatus_cron ────▶ conatus_foundation
conatus_search ─▶ conatus_foundation
conatus_skill ──▶ conatus_foundation
conatus_asr ────▶ conatus_foundation
conatus_tts ────▶ conatus_core
conatus_tasks ──▶ conatus_agent
conatus_tui ────▶ conatus_agent、conatus_compaction、conatus_cron、conatus_schedule、conatus_search、conatus_skill
conatus_observability ▶ conatus_agent
conatus_alerting ────▶ conatus_agent、conatus_tts、conatus_foundation
conatus_browser_use ─▶ conatus_mcp、conatus_tasks、conatus_credentials、conatus_foundation
conatus_computer_use ▶ conatus_mcp、conatus_tasks、conatus_credentials、conatus_foundation
conatus_team ────────▶ conatus_agent、conatus_llm、conatus_foundation
conatus_intent ──────▶ conatus_agent、conatus_foundation
conatus_workflow ────▶ conatus_team、conatus_tasks、conatus_foundation
```

（`conatus_core` 为所有包的公共底座，各行从略。）后 7 行是实验性包：只被上层装配
依赖，稳定包不反向依赖它们（`conatus_agent` / `conatus_mcp` / `conatus_tasks` 都
不知道它们的存在）。

用于构建**可动态加载、卸载、热替换**的插件化系统。核心解决两个正交维度的问题：

- **时间可组合性（Temporal Composability）**：组件被移除时，其副作用必须能被完整撤销。本项目用**可逆效应**实现——每次副作用都伴随一个撤销函数，由 `EffectScope` 以 LIFO 顺序统一回滚。
- **空间可组合性（Spatial Composability）**：组件之间的依赖必须能被声明式管理，并在依赖变化时自动响应。本项目用**反应式共效应**实现——组件声明“我需要服务 A 和 B”，运行时持续比对当前上下文，据此驱动组件的激活与停用。

两者统一在同一个 `Context` 类型上。

---

## 特性

- 🧩 **可逆效应**：LIFO 撤销、幂等、抗异常、迟到登记安全
- 🔄 **反应式共效应**：依赖变化自动激活/停用，级联响应
- 🌳 **上下文树**：服务沿父链向下可见，天然支持作用域隔离
- ⚡ **重入收敛**：服务变更引发的连锁反应在一次 `notify` 内稳定
- 🛡️ **循环依赖检测**：无法收敛时快速失败，而非死循环
- 📦 **零运行时依赖**：核心仅用 Dart 核心库（`llm` / `credentials` / `mcp` / `search` 插件依赖 `http`，`foundation` 的 IANA 时区解析依赖 `timezone`）
- 🧰 **基础设施插件**：`timer`（定时器即效应）、`logger-console`（分级日志）、`loader`（注册表 + 配置树）、`tools`（`Tool` 基类 + `ParamSpec` + 注册表/执行管线/分组/分级）、`shell` / `fs`（能力缝 + 本地实现）、`search`（搜索能力缝 + web 工具）、`asr`（语音识别能力缝 + `transcribe_audio`）、`tts`（语音合成能力缝 + 音频输出接口）
- 🔐 **凭据管理**：`credentials`（统一凭据契约 + 五种来源：环境变量 / 内存 / 文件 / Vault KV v2 / AWS Secrets Manager）——`get` / `require` / `validate` 同步读内存快照，远端来源用 `refresh()` 拉取并可定时轮换，对外只出现 `masked`
- 🗂️ **会话与上下文**：`session`（事件日志 + 仓库 + JSONL 持久化）、`session-log`（多会话只追加日志：fork / replay / 轨迹重建，附「模型可见即已记录」不变式）、`schedule`（会话本地持久提醒：创建 / 列出 / 取消，重启后自动重建）、`cron`（定时任务：at / every / daily / cron 规则调度 + 运行历史持久化 + cron_* 管理工具）、`system-prompt`（prompt 段装配 + 动态上下文）、`time-context`（日粒度日期锚点）、`compaction`（压缩能力缝：滚动摘要 + `compaction/*` 日志事件）、`memory`（长记忆库 + 显式记住/遗忘能力与工具）
- 🗄️ **持久化**：`database`（KV 存储 hub + 可插拔后端 + JSON 本地实现）
- 🤖 **Agent Loop**：`agent`（会话事件 + prompt 装配 + 压缩 + 记忆 + 工具闭环）、`tool-result-eviction`（大结果落盘）、`plan`（结构化计划）、`sub-agent`（`spawn_agent` 隔离委托）、`reflection`（工具后自省重试）
- 🔌 **MCP 生态**：`mcp`（MCP 客户端：stdio / HTTP / SSE 传输 + 握手与工具发现），外部 server 的工具以 `server__tool` 接入同一张工具表，风险缺省 `medium` 走审批
- 🗜️ **分层压缩与缓存度量**：`content-classifier`（内容分类器能力缝）、`layered-compaction`（按类别分层折叠：工具结果压成指针、用户偏好留原文）、`context-cache`（可缓存前缀指纹 + 命中遥测）
- 🔭 **产品化**：`telemetry`（事件导出 + 埋点）、`evaluation`（用例评估 + 基线对比）、`approval`（高危工具审批）、`skill`（技能沉淀）、`skill-catalog`（技能加载：发现 `SKILL.md` 指令集 + 目录注入 + `skill` 工具）、`recovery`（会话快照恢复）
- 🕹️ **实验性能力包**（`publish_to: none`，不进伞包）：`alerting`（订阅遥测按规则主动告警）、`browser_use` / `computer_use`（经 MCP 驱动浏览器与本地桌面）、`team`（多智能体协作：任务板 + 成员运行时）、`workflow`（把协作沉淀为声明式流程资产）、`observability`（span 语义 + 从 Session Log 派生 trace）
- ✅ **完整测试覆盖**：1350 个测试（21 个模块包 + 根包，CI 全量执行）

---

## 安装

根包 `conatus` 依赖同一仓库内的 `conatus_*` 兄弟包（目前尚未发布到 pub.dev）。
因此从 git 引入时，伞包直接指向仓库根，兄弟包放进 `dependency_overrides`，
否则 pub 会按 hosted 源去 pub.dev 查找不存在的 `conatus_search` 等：

```yaml
dependencies:
  conatus:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: master        # 建议 pin 到 release tag 或 commit SHA，避免 master 漂移

dependency_overrides:
  conatus_agent:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_agent}
  conatus_asr:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_asr}
  conatus_core:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_core}
  conatus_compaction:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_compaction}
  conatus_credentials:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_credentials}
  conatus_cron:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_cron}
  conatus_foundation:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_foundation}
  conatus_llm:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_llm}
  conatus_mcp:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_mcp}
  conatus_schedule:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_schedule}
  conatus_search:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_search}
  conatus_skill:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_skill}
  conatus_tasks:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_tasks}
  conatus_tts:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_tts}
```

实验性包（`conatus_alerting` / `conatus_browser_use` / `conatus_computer_use` /
`conatus_intent` / `conatus_observability` / `conatus_team` / `conatus_workflow`）
不在伞包依赖内，
要用就单独声明，并同样把它们依赖的兄弟包放进 `dependency_overrides`：依赖
`conatus_workflow` 时要额外补 `conatus_team`（workflow → team），依赖
`conatus_browser_use` / `conatus_computer_use` 时要补 `conatus_mcp` 与
`conatus_tasks`（上面的列表已含）；`conatus_intent` 只依赖 `conatus_agent` 与
`conatus_foundation`，无需额外补装。

```yaml
dependencies:
  conatus_workflow:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_workflow}

dependency_overrides:
  # ...上面的兄弟包列表...
  conatus_team:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_team}
```

各包发布到 pub.dev 后即可简化为 `conatus: ^0.15.0`。

> 包是纯 Dart（不含 Flutter SDK 依赖），Flutter 项目同样可用，只是用 `flutter pub get`。

本地开发时把上面的 `git: {...}` 换成 `path:`：伞包写仓库根
（`path: /你的路径/conatus`），兄弟包写 `path: /你的路径/conatus/packages/<name>`。

只依赖叶子包 `conatus_core`（无任何依赖）时不需要 override：

```yaml
dependencies:
  conatus_core:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_core}
```

从源码使用：

```bash
git clone https://github.com/Fi2zz/conatus.git
cd conatus
dart pub get
dart test
```

---

## 快速开始

```dart
import 'package:conatus/conatus.dart';

class Logger {
  void info(String msg) => print('[LOG] $msg');
}

void main() {
  final app = Context.root(name: 'app');

  // 1. 提供服务：logger（服务对 app 及其后代可见）
  final stopLogger = app.provide('logger', Logger());

  // 2. 加载 greeter 插件：声明依赖 'logger'
  app.plugin('greeter', (ctx) {
    ctx.inject(['logger'], (child) {
      final logger = child.require<Logger>('logger');
      logger.info('greeter 已激活');
      child.onDispose(() => print('[LOG] greeter 已停用'));
    });
  });

  // 3. 卸载 logger —— greeter 会自动停用
  stopLogger();

  // 4. 重新提供 logger —— greeter 会自动以全新上下文重新激活
  app.provide('logger', Logger());

  // 5. 卸载整个应用
  app.dispose();
}
```

运行示例：

```bash
dart run example/main.dart   # 交互式 Agent（需要 ARK_API_KEY / DEEPSEEK_API_KEY）
dart run example/demo.dart   # 离线 Demo，脚本化模型，无需 Key
```

`example/demo.dart` 用脚本化模型跑通「提问 → 工具调用 → 回填 → 收口」，并演示
telemetry 埋点、技能沉淀与快照恢复。

---

## 内置插件

### `ask_user` — 声明式提问

```dart
// 服务只对提供者及其后代可见，因此需注册在共同祖先（app）上
provideAskUser(app);

app.plugin('chat', (ctx) {
  ctx.inject(['askUser'], (child) {
    final ask = child.require<AskUser>('askUser');
    ask.ask('你的名字是？').then(print);
  });
});
```

- `AskUser` 是接口，`CliAskUser` 只是默认实现，可注入自定义提问器；
- 提问本身是可逆效应——上下文释放时自动取消，避免悬挂 Future。

### `llm` — 大模型接入（豆包首选，DeepSeek 备选）

```dart
provideLlm(app);

app.plugin('chat', (ctx) {
  ctx.inject(['llm'], (child) async {
    final llm = child.require<FallbackLlm>('llm');
    final result = await llm.chat([
      LlmMessage('user', '你好'),
    ]);
    print(result.content);
  });
});
```

环境变量（二选一或都设）：

```bash
export ARK_API_KEY="你的火山方舟 API Key"      # 豆包
export DEEPSEEK_API_KEY="你的 DeepSeek Key"    # DeepSeek（可选）
```

| 提供商 | Base URL | 默认模型 | 环境变量 |
|--------|----------|----------|----------|
| 豆包（首选） | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-seed-1-8-251228` | `ARK_API_KEY` |
| DeepSeek（备选） | `https://api.deepseek.com` | `deepseek-flash` | `DEEPSEEK_API_KEY` |

两种形态由 `apiStyle` 选择（默认 `chat`）：

| apiStyle | 端点 | 消息载荷 |
|----------|------|----------|
| `LlmApiStyle.chat`（默认） | `/chat/completions` | `messages` |
| `LlmApiStyle.responses` | `/responses` | `input`（`store: false`） |

```dart
// 走 Responses 形态
final llm = OpenAiCompatibleProvider(
  name: 'doubao',
  baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
  model: 'doubao-seed-1-8-251228',
  apiKey: '...',
  apiStyle: LlmApiStyle.responses,
);

// 非流式
final result = await llm.chat([const LlmMessage('user', '你好')]);
print(result.content);

// 流式：正文 / 思考增量 + 终态用量与工具调用
await for (final event in llm.chatStream(
  [const LlmMessage('user', '现在几点？')],
  tools: app.tools.describe(), // 与非流式一致，可下发工具 schema
)) {
  switch (event) {
    case LlmTextDelta(:final text):
      stdout.write(text);
    case LlmReasoningDelta(:final text):
      break; // 思考增量
    case LlmStreamDone(:final finishReason, :final usage, :final toolCalls):
      print('\n[$finishReason] $usage ${toolCalls.length} 次工具调用');
  }
}
```

`chat` / `chatStream` 的 `tools` 参数语义一致：非空时以原生 function calling 下发，`chat` 的结果与 `chatStream` 的终态都在 `toolCalls` 里给出。流式下工具参数是 JSON 分片，攒到流结束才完整，故由 `LlmStreamDone.toolCalls` 一次性给出。

非流式与流式都支持自动回退：任一提供商失败即尝试下一个，全部失败时抛出汇总了各提供商错误的 `LlmException`。流式回退只在该提供商**尚未产出任何增量**时生效；已产出增量后中途失败会直接抛出。

### `credentials` — 统一凭据管理（环境变量 / 文件 / Vault / AWS）

服务键 `'credentials'`（`ctx.credentials`）。`Credentials` 把「值从哪来」与「值怎么
被消费」解耦：**读取是同步的**（`get` / `require` / `validate` 读内存快照），远端
来源用 `refresh()` 把值拉进快照，轮换经 `changes` 广播。这样需要在构造函数里同步
解析 Key 的 `LlmProvider` 不必改成异步形状。

| 来源 | 类型 | 用途 | 可写 |
|------|------|------|:---:|
| 环境变量 | `EnvCredentials()` | 进程环境，默认来源 | 否 |
| 内存 | `InMemoryCredentials({initial})` | 进程内临时凭据 / 测试替身 | 是 |
| 文件 | `FileCredentials({path, fallback, refreshInterval})` | 本地 JSON | 否 |
| Vault | `VaultCredentials({config: VaultConfig(...)})` | HashiCorp Vault KV v2 | 否 |
| AWS | `AwsSecretsCredentials({config: AwsSecretsConfig(...)})` | Secrets Manager `GetSecretValue`（`SigV4Signer` 手写签名） | 否 |

```dart
final credentials = provideCredentials(app);          // 缺省 EnvCredentials
final llm = OpenAiCompatibleProvider(
  name: 'doubao',
  baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
  model: 'doubao-seed-1-8-251228',
  credentialKey: 'ARK_API_KEY',
  credentials: credentials,
);

print(credentials.require('ARK_API_KEY').masked);     // sk-1...cdef
credentials.validate(<String>['ARK_API_KEY']);        // 缺失抛 CredentialsException('missing')
```

- 只读来源（env / file / vault / aws）调 `update` 抛 `CredentialsException('read-only')`，
  只有 `InMemoryCredentials` 可写；`Credential.expired` 为真时 `get` 返回 `null`；
- 各来源共用 `parseCredentialMap` 解析 `"KEY": "值"` 与
  `"KEY": {"value": ..., "expiresAt": ...}` 两种形态；
- 对外只暴露 `Credential.masked`（前 4 + `...` + 后 4，长度 ≤ 8 时整串星号），
  `toString()` 也只含脱敏值；结构化日志交给 `conatus_core` 的 `redactSecrets`；
- OpenAI 兼容 provider 可传 `credentials` 与 `credentialKey`（如 `ARK_API_KEY`），
  解析顺序是「显式 `apiKey` → 凭据服务」，**不直接读环境变量**，并订阅 `changes`
  做运行时轮换——Header 每次请求重算，不重建 HTTP client；具体提供商
  （`DoubaoProvider` / `DeepSeekProvider`）与默认回退链 `defaultFallbackLlm`
  在 `conatus_providers`；
- 不传 `credentials` 时行为与从前完全一致。

### `timer` — 定时器即可逆效应

定时器登记在调用方上下文上，随上下文释放自动清理（`TimerContext` 扩展，导入即可用）：

```dart
ctx.timeout(() => print('1s 后执行一次'), const Duration(seconds: 1));

final Disposer tick =
    ctx.interval(() => print('每秒一次'), const Duration(seconds: 1));
tick(); // 提前取消

await ctx.sleep(const Duration(milliseconds: 500)); // 上下文释放时以 StateError 结束

final Throttled onScroll = ctx.throttle(() => print('节流'), const Duration(milliseconds: 200));
final Debounced onInput = ctx.debounce(() => print('防抖'), const Duration(milliseconds: 300));
onScroll();
onInput();
```

### `logger-console` — 分级日志

自带 `LoggerService`（分级、命名 logger、可插拔导出器）并默认挂 `ConsoleExporter`：

```dart
final logger = provideLogger(app);          // 提供 'logger' 服务 + 控制台输出
logger.info('服务已启动');

final chat = logger.logger('chat');         // 命名 logger
chat.warn('会话超时', error, stackTrace);

logger.addExporter(MyExporter());           // 自定义 sink
logger.level = LogLevel.debug;              // 全局级别
```

### `loader` — 注册表 + 配置树

Dart 没有动态 `import()`，loader 用**按名注册的插件工厂**代替模块解析：

```dart
final loader = provideLoader(app, plugins: <String, PluginFactory>{
  'logger': (ctx, config) => provideLogger(ctx),
  'ask': (ctx, config) => provideAskUser(ctx),
});

loader.apply(<LoaderEntry>[
  const LoaderEntry(id: 'logger', name: 'logger'),
  const LoaderEntry(
    id: 'group',
    children: <LoaderEntry>[LoaderEntry(id: 'group:ask', name: 'ask')],
  ),
]);

loader.reload('logger'); // 重启单个 entry
loader.remove('group');  // 卸载分组及其所有后代（级联撤销）
```

配置树支持 `LoaderEntry.toJson()` / `LoaderEntry.fromJson()` 与 `applyJson`，可从 JSON 加载。

### `tools` — 工具基类 + 注册表 + 受控执行管线

服务键 `'tools'`（`ctx.tools` 快捷访问）。作者继承 `Tool` 声明形状与执行体，用
`ParamSpec` 声明参数（自动生成 JSON Schema，不再手写）；`ctx.tools.call` 先校验
参数，再经过守卫与中间件，最后调用执行体并广播结果。

```dart
class EchoTool extends Tool {
  const EchoTool();
  @override String get name => 'echo';
  @override String get description => '回显输入';
  @override List<ParamSpec> get params =>
      <ParamSpec>[ParamSpec.string('text', required: true)];
  @override Future<ToolResult> call(ToolContext ctx) async =>
      ToolResult.success(ctx.str('text'));
}

final tools = provideTools(app, timeout: const Duration(seconds: 10));
app.plugin('echo', (ctx) => ctx.effect(() => ctx.tools.register(const EchoTool())));

final result = await ctx.tools.call(
  const ToolCall(name: 'echo', arguments: <String, Object?>{'text': 'hi'}),
  timeout: const Duration(seconds: 5),
);
```

- `ToolContext` 提供类型安全取参（`str` / `integer` / `number` / `boolean` /
  `array` / `object` / `require<T>`），缺失或类型不符抛 `ToolArgumentException`；
- `ParamSpec` 覆盖 string / integer / number / boolean / enum / array / object，
  `parameterSchema` 自动编译；`Tool.toSchema()` 只投影 `name` / `description` /
  `parameters`，执行体等宿主字段永不下发模型；
- `ctx.tools.fn(...)` 一行注册简单工具；`ctx.tools.group(name, [...])` 按领域分组，
  `Tool.riskLevel` + `ctx.tools.guardRisk(max)` 做能力分级；
- 失败码：参数不合法 `INVALID_ARGS`、超时 `TOOL_TIMEOUT`、未知工具 `UNKNOWN_TOOL`、
  守卫拒绝 `TOOL_DENIED`、执行体异常 `TOOL_ERROR`，都收敛为失败结果而非外抛；
- 所有登记返回 `Disposer`，交给 `ctx.effect(...)` 即可随上下文卸载自动撤销。

### `mcp` — MCP 客户端与工具生态

服务键 `'mcp'`（`ctx.mcp`）。把外部 [MCP](https://modelcontextprotocol.io) server
的工具接进 `ctx.tools`，模型看到的仍是同一张工具表。装配是异步的（要握手与发现
工具），因此 `provideMcp` 返回 `Future<McpRegistry>`。

```dart
provideTools(app);
await provideMcp(app, <McpServerConfig>[
  McpServerConfig(
    name: 'fs',
    type: McpTransportType.stdio,
    command: 'npx',
    args: <String>['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
  ),
  McpServerConfig(
    name: 'remote',
    type: McpTransportType.http,
    url: 'https://mcp.example.com/mcp',
    headers: <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
  ),
], credentials: credentials, aliases: <String, String>{'read_file': 'fs__read_file'});
```

- 三种传输 `McpTransportType.stdio` / `.http` / `.sse`，对应 `StdioTransport` /
  `HttpTransport` / `SseTransport`；`McpClient` 负责握手、`tools/list` 分页、
  `tools/call` 按 id 关联，超时（默认 30s）只失败本次调用；
- 工具注册名是 `server__tool`，`group` 为 `mcp:<server>`；入参 schema 由服务端下发，
  `McpToolAdapter.toSchema()` 直通 `inputSchema`；
- 风险映射：非标准 `riskLevel`（`readonly` / `read` → `low`，`write` / `mutating` →
  `medium`，`destructive` / `admin` → `high`）、`annotations.destructiveHint` → `high`、
  `annotations.readOnlyHint` → `low`，**什么都没声明则缺省 `medium`**（默认需要审批）；
- `env` / `headers` 的值支持 `${KEY}` 占位符，用 `Credentials` 解析（Dart 源码里要写成
  原始字符串 `r'...'` 或转义 `\$`，否则会被当成字符串插值）；解析不了时
  占位符原样保留，且**解析结果不得写进日志**（要排查就用键名）；
- `McpToolAlias` 给已注册工具加短名；连接登记为可逆效应，`ctx.dispose()` 断开全部
  连接并注销工具，某个 server 崩溃只注销它自己的工具，其余 server 不受影响。

### `search` — 搜索能力缝 + web 工具

服务键 `'search'`（`ctx.search`）。多个 `SearchProvider` 顺序回退：默认
DuckDuckGo（无需 Key），传 `exaApiKey` 时 Exa 优先。`provideWebTools` 把
`web_search` / `fetch_url` 两个只读工具注册进 `ctx.tools`。

```dart
provideSearch(app, exaApiKey: Platform.environment['EXA_API_KEY']);
provideWebTools(app); // 注册 web_search / fetch_url
```

### `asr` — 语音识别能力缝 + `transcribe_audio`

服务键 `'asr'`（`ctx.asr`）。把「音频字节 → 文本」作为可插拔能力，与音频来源
解耦：`AsrProvider` 抽象识别服务（默认豆包/火山 SAUC 双向流式 WebSocket），
`AsrAudioSource` 抽象音频来源（桌面用 `FfmpegMicSource`，Flutter 用录音插件）。
`provideAsrTools` 把 `transcribe_audio` 注册进 `ctx.tools`。

```dart
provideAsr(app);      // 读 VOLC_ASR_API_KEY 或 VOLC_ASR_APP_KEY + ACCESS_KEY
provideAsrTools(app); // 注册 transcribe_audio

// 任何 Stream<List<int>> 都能识别（文件 / 麦克风 / 网络）
final text = await ctx.asr.transcribeText(audioBytes, language: 'zh-CN');
```

### `tts` — 语音合成能力缝 + 音频输出接口

服务键 `'tts'`（`ctx.tts`）。把「文本 → 音频字节」作为可插拔能力，音频写到哪由
`TtsAudioSink` 决定（扬声器 / 文件 / 网络）：CLI / 桌面写本地播放器，Flutter 写
平台播放插件。默认 provider 是 `DoubaoStreamingTtsProvider`，走火山 v3
`wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream`。

```dart
provideTts(app); // 读 VOLC_TTS_API_KEY，或 VOLC_TTS_APP_KEY + VOLC_TTS_ACCESS_TOKEN

final bytes = await ctx.tts.synthesize('你好，世界'); // 收进内存
await ctx.tts.speak('你好', myAudioSink);            // 写入自定义输出
```

### `shell` — 命令执行能力缝

服务键 `'shell'`。`ShellExecutor` 只定义契约（`resolve` / `run` / `start`），
内置 `LocalShellExecutor` 通过 `dart:io` 的 `Process` 用 `bash -c`（Windows 为
`cmd /c`）执行，采集有上限的 stdout / stderr，支持前台超时与后台进程句柄。

```dart
provideShellLocal(app); // 提供 'shell'（可传 executor 注入自定义实现）

app.inject(['shell'], (ctx) async {
  final ShellExecutor shell = ctx.require<ShellExecutor>('shell');
  final result = await shell.run(shell.resolve(const ShellExecRequest(command: 'ls')));
  print(result.stdout.text);
});
```

替换为沙箱 / 远程 / PowerShell 执行器时，消费方代码不变。

### `fs` — 文件系统能力缝

服务键 `'fs'`。`FileSystem` 只定义契约（`resolve` / `stat` / `lstat` /
`readText` / `listDir` / `writeText` / `editText` / `contains` / `fileUrl` /
`processPath`），内置 `LocalFileSystem` 基于 `dart:io` 实现：realpath 派生稳定
目标身份、写入经临时文件 + rename 原子发布、编辑在版本守卫后做字面替换。

```dart
provideFileSystemLocal(app);

final fs = app.require<FileSystem>('fs');
final target = await fs.resolve('notes.txt');
await fs.writeText(target, 'hello');
await fs.editText(target, const FsEditRequest(oldString: 'hello', newString: 'hi'));
```

- 写入守卫：`FsCreateIfAbsent`（已存在 → `FS_NOT_OBSERVED`）/ `FsReplaceIfVersion`（版本不符 → `FS_STALE_VERSION`）；
- 错误统一由 `FsError` 携带 `FsErrorCode`（`FS_NOT_FOUND` / `FS_NOT_TEXT` / `FS_AMBIGUOUS_EDIT` …），便于上层按码分支；
- `provideFsTools(app)`（`conatus_fs_tools` 包）注册 `read_file` / `write_file` / `edit_file` / `rg` / `glob` 把 fs 暴露给模型；`provideToolResultEviction` 落盘的大结果即由 `read_file` 读回。

### `tool-result-eviction` — 大结果落盘

超阈值的工具结果写入临时文件，上下文只留「前 N 字符 + `...(省略 N 字符)...` +
后 N 字符 + 路径」，模型按路径用 `read_file` 读回。失败结果不驱逐；临时文件随
上下文释放清理。

```dart
provideToolResultEviction(app, threshold: 80000); // 或先 provide('toolResultThreshold', 80000)
```

### `plan` — 规划

`plan_write` 工具把「目标 + 有序步骤」以 `plan/updated` 事件写入会话；
`AgentLoop(planning: true)`（或 `provideAgentLoop(app, planning: true)`）在无计划时
先跑一次「只允许 plan_write」的规划轮，之后每轮把 `[当前计划]` 注入 system。

```dart
providePlanTool(app, session: session); // 注册 plan_write
final agent = provideAgentLoop(app, session: session, planning: true);
```

### `sub-agent` — 子 Agent 委托

`spawn_agent` 是一个普通工具：调用时在宿主上下文下派生隔离子上下文，创建独立的
`Session` 与受限 `ToolRegistry`，跑独立的 `AgentLoop`，只把结论回传。宿主释放时
在途子 Agent 一并终止。

```dart
provideSpawnAgent(app, defaultTools: <String>['web_search', 'fetch_url']);
// 或逐次指定白名单：spawn_agent(task: '…', tools: ['get_time'], max_rounds: 5)
```

- 默认白名单 = 主注册表里非 `high` 风险、且非 `spawn_agent` 自身的工具；
- 返回 `{status, output, rounds, tool_calls}`（`value`），正文是结论简报。

### `reflection` — 自省与重试

工具执行后可选自省：`Reflector` 用一次独立 LLM 调用判断「继续 / 重试 / 重新规划」；
`retry` 有界重跑，`replan` 触发重新规划。策略：`always` / `onError`（默认）/
`onRisk` / `never`。

```dart
provideReflection(app, strategy: ReflectionStrategy.onError, maxRetries: 1);
// 或 ctx.provide('reflectionStrategy', 'onError');
final agent = provideAgentLoop(app); // 自动接入 'reflection'
```

### `telemetry` — 可观测性

服务键 `'telemetry'`（`ctx.telemetry`）。默认 `InMemoryTelemetry`（内存缓冲 +
广播流），`ConsoleTelemetry` 打控制台；可替换为 OTel / Prometheus 导出器。
埋点用装饰器：`instrumentTools` 挂工具中间件，`TelemetryLlmProvider` 包模型调用，
`AgentLoop` 经 `provideAgentLoop` 自动产出 `agent.round` / `agent.finished`。

```dart
provideTelemetry(app);
instrumentTools(app);
final agent = provideAgentLoop(app); // 自动包 llm 并接 onEvent

for (final e in ctx.telemetry.recent) print(e.name); // tool.called / llm.request / agent.round
```

### `evaluation` — 评估体系

用固定用例衡量 Agent 表现：`Evaluator` 注入 `EvalRunner`（跑一轮 `AgentLoop.run`
或子 Agent），按 `EvalJudge`（默认 `defaultEvalJudge`：期望工具子集 + 输出关键词 +
步数上限）判分，汇总 `EvalReport`，可与基线 `compareTo` 得到 `EvalDiff`。

```dart
final evaluator = Evaluator(run: (input) => agent.run(input));
final report = await evaluator.runAll(<EvalCase>[
  const EvalCase(id: 'time', input: '现在几点', expectedTools: ['get_time'], expectedOutput: '12:00'),
]);
print('通过率 ${report.passRate}');        // 0.0–1.0
print(report.compareTo(baseline));        // 通过率 +…%，平均步数 ±…
```

`EvalCase` / `EvalReport` 支持 `toJson` / `fromJson`，便于把基线持久化到数据库。

### `approval` — 高危工具审批

服务键 `'approval'`（`ctx.approval`）。`instrumentApproval` 把审批挂到工具调用链上：
风险不低于阈值的工具先经 `Approval.request` 批准再执行，拒绝或超时返回
`APPROVAL_DENIED`。内置 `AutoApproval`（测试/开发）、`RuleBasedApproval`、
`AskUserApproval`（经 `ask_user`，超时视为拒绝）；`requestPlan(plan)` 可一次性
审批整份计划。有 `'telemetry'` 时记录 `approval.requested` / `approval.decided` 审计事件。

```dart
provideApproval(app, approval: AskUserApproval(askUser: app.require<AskUser>('askUser')));
// 或 provideApproval(app, approval: AutoApproval(true));            // 开发
// 或 provideApproval(app, threshold: ToolRisk.high, timeout: Duration(minutes: 5));
```

### `skill` — 技能沉淀

服务键 `'skill'`（`ctx.skills`）。`SkillLibrary` 记录工具轨迹，同一序列出现 `threshold`
（默认 3）次后用 `SkillNamer`（`llmSkillNamer` / `deterministicSkillNamer`）命名，
构造 `SkillTool`（按序执行步骤、支持 `{{param}}` 占位符）注册到工具表。含 `high`
风险步骤的序列不沉淀；启用前若配了 `Approval` 需先获批；技能存入 `MemoryStore`
跨会话 `restore`。

```dart
final skills = provideSkillLibrary(app);                       // 自动接 memory/approval/llm
skills.record('查环境', <SkillStep>[SkillStep(toolName: 'get_weather', arguments: {'city': '{{city}}'})]);
final skill = await skills.maybeExtract(tools: app.tools);     // 达阈值时产出并注册
await skills.restore(tools: app.tools);                        // 跨会话恢复
```

### `skill-catalog` — 技能加载（可加载指令集）

服务键 `'skillRegistry'`（`ctx.skillRegistry`）。与上面的 `skill`（技能沉淀）不是
同一件事：这里加载的是磁盘上的 Markdown 指令集，那边沉淀出的是可执行的新工具。

技能放在 `<项目根>/.conatus/skills/<name>/SKILL.md`（或 `<name>.md`），
`<项目根>/.agents/skills`、`~/.conatus/skills`（`$CONATUS_HOME`）、
`~/.agents/skills`（`$CONATUS_AGENTS_HOME`）按同一优先级规则依次生效。
frontmatter 需要 `name`（kebab-case）与 `description`，可选 `whenToUse` /
`metadata` / `disable-model-invocation`；`name` 与描述会被拼成一段 system prompt
（`skills` 段——没有技能时该段不存在），模型据此调用 `skill` 工具取回正文。

```dart
final registry = await provideSkillRegistry(app);
provideSkillCatalog(app);            // 目录段：有技能才挂
provideSkillTool(app);               // 注册 skill 工具
await provideSkillFilesystem(app);   // 发现 .conatus/skills 等目录并监听变更
```

不想落盘时也可以直接传提示词：`provideSkillRegistry(app, inlineSkills: [...])`
把内联技能（[`SkillRegistration`]，不解析 frontmatter）注册进同一份目录与同一个
`skill` 工具。

注册表支持分层：`SkillRegistry(parent:, visible:)` 的子作用域继承父级技能、同名
覆盖，父级变化级联到子级；`load` 只认可见集合，被过滤的技能取不到。分层是链式的
（单 `parent`、整条覆盖），且挂载点要显式作用域化——多个作用域共用一份
`SystemPrompt` / `ToolRegistry` 时，段名与工具名不换会在装配处抛 `StateError`。

斜杠调用在 TUI 侧：`conatus_tui` 把每个技能投影成 `/skill:<技能名> [补充要求]` 命令，
`disable-model-invocation` 的技能也能由此手动触发（见其 README 的「技能直接调用」）。
本包本身只有模型侧入口。

限制：只扫发现根一层，不递归
`**/SKILL.md`；发现根在装配时确定，之后不会跟随工作目录变化；改正文不会改变目录，
模型不会被通知。

### `recovery` — 持久化与恢复

服务键 `'recovery'`（`ctx.recovery`）。`snapshot(session)` 把会话全部事件存成带版本号
的 `SessionSnapshot`（计划也在事件里），`restore(id)` 还原 `Session` 继续对话。
存储端口 `SnapshotStore`：有 `'database'` 时默认 `DatabaseSnapshotStore`（JSON 后端），
否则内存实现；版本不符抛 `unsupported-version`。

```dart
provideRecovery(app);              // 自动用 'database' 或内存
await app.recovery.snapshot(session);            // 每轮结束/释放时
final resumed = await app.recovery.restore('cli'); // 重启后继续
```

### `session` — 事件日志 + 会话仓库 + JSONL 持久化

服务键 `'sessions'`（配合可选的 `'sessionPersistence'`）。一条会话是 append-only
的 `SessionEvent` 序列（`seq` 从 0 单调递增）；`SessionStore` 负责创建/打开/关闭，
并在追加时异步落盘（`flush()` 等待在途写入）。

```dart
provideSessionPersistence(app); // 本地 JSONL（默认 <cwd>/.conatus/sessions）
final sessions = provideSessions(app);

final session = sessions.create(id: 's1');
session.append('user/message', data: <String, Object?>{'text': '你好'});
session.onEvent((e) => print(e.seq));
await sessions.flush();

final reopened = SessionStore(persistence: JsonlSessionPersistence(dir: '...'));
print((await reopened.open('s1')).events.length);
```

- `Session.onEvent` / `onClose` 返回 `Disposer`；关闭后拒绝追加；
- `SessionPersistence` 是可插拔端口（`list` / `load` / `append` / `remove`），换成数据库后端无需改调用方。

### `session-log` — 多会话只追加日志（fork / replay / 轨迹重建）

服务键 `'sessionLog'`（`ctx.sessionLog`）。`session` 是**单会话**的内存事件日志，
`SessionLog` 面向**多会话**：按 `sessionId` 归档事件、按时间窗读取、从任意事件点
分叉历史、按序重放。只追加是硬不变式——日志永不改写，fork 只产生新会话，源会话
不受影响。`seq` 由日志按会话分配（每会话从 0 起密集递增）。

```dart
provideSessionPersistence(app);       // 追加式 JSONL
final log = provideSessionLog(app);   // 三个后端按优先级自动挑选
provideSessionLogRecorder(app);       // 依赖 'sessionLog'，缺则自动补一个

final agent = provideAgentLoop(app, session: session);
// 日志 = 业务事件的超集镜像 + llm/request / llm/response / tool/call 派生事件
print(await log.list());                            // 已有会话 id

final forked = await log.fork(session.id, eventId); // 从任意事件点分叉
await log.replay(forked, (e) => print(e.type));
assertModelVisibleInvariant(await log.read(session.id).toList());
```

- 三个后端：`InMemorySessionLog()`（进程内）、`PersistenceSessionLog(persistence)`
  （复用追加式 `SessionPersistence`，**长会话无写放大，推荐**）、
  `DatabaseSessionLog(database, {unit})`（长度前缀键；`DatabaseUnit.put` 整表重写，
  长会话下有 O(n²) 写放大）；
- `provideSessionLog(ctx, {log, persistence, database})` 的后端优先级：显式 `log` →
  `persistence`（或 `'sessionPersistence'` 服务）→ `database`（或 `'database'` 服务，
  且至少注册了一个后端）→ 内存；上下文释放时关闭日志；错误经
  `SessionLogException(code, message)` 抛出；
- Agent 侧由 `SessionLogRecorder` 镜像全部业务事件，再追加 **`llm/request` /
  `llm/response` / `tool/call` 三类非模型可见的派生事件**，`parentEventId` 串成因果链；
  业务 `Session` 的事件序列分毫未动（日志只是超集）；
- `SessionLogLlmProvider` 是不改请求的装饰器，`instrumentSessionLogTools` 挂
  `tools.use` 中间件记录工具名 / 调用 id / `group` 归因与实参；`provideAgentLoop`
  只在上下文提供了对应能力时才包装（`'sessionLogRecorder'` 决定是否记轨迹、
  `'contextCache'` 决定是否度量），未提供则行为与从前完全一致，`composeLlm` 由外到内
  的叠加顺序是 `SessionLog(Caching(Telemetry(inner)))`；
- `checkModelVisibleInvariant(events)` / `assertModelVisibleInvariant(events)` 验证
  「凡进入模型的内容都能在日志里找到出处」：对日志里每条 `llm/request`，从日志重建
  该点的会话消息并逐条比对（system prompt 由运行时装配，不在比对范围）；
  `sameJson` 是配套的递归 JSON 比较工具。

`Session` 一侧的 `fork` / `replay` / `read` / `appendEvent` / `lastEventId` 与它配对，
既有签名全部保持兼容。

### `cron` — 定时任务（`conatus_cron` 包）

服务键 `'cron'`（`ctx.cron`）与 `'cronRuntime'`（`ctx.cronRuntime`）。语义移植自
dsh-cron（不含 web 部分）：任务规则四选一——`at` 一次性 / `every` 固定间隔（最小
10s）/ `daily` 本地 `HH:MM`（错过补发）/ `cron` 5 段表达式（本地时间）；到点把任务
提示以 `[cron]` framing 连同原始任务交付给宿主注入的 `CronDelivery` 端口，成功
才消费时段，拒绝则下个 tick 重试。

```dart
final service = provideCron(ctx,
    storage: JsonCronStorage(tasksPath: tasksFile, historyPath: historyFile));
provideCronTools(ctx);
provideCronRuntime(
    ctx, deliver: (recordId, framing, task) async => submit(framing));
// turn 结束后：ctx.cronRuntime.finishRun(recordId, ok: …, excerpt: …);
```

- [CronStorage] 是抽象端口（本地 [JsonCronStorage]、数据库、远程 KV 均可接入）；
  `configTasks` 可声明静态任务（运行时不可增删改）；`conatus_tui` 已默认接上
  （任务与历史落在 `<baseDir>/cron-tasks.json` / `cron-history.jsonl`）
- 运行历史 JSONL 封顶 500，`finishRun` 推进 `delivered` → `completed` / `failed`
  并截断摘要到 300 字符；conatus_tui 用 `systemCronNotifier()` 提供 macOS / Linux
  系统通知（cron 包只定义抽象 `CronNotifier` 端口）
- 模型工具：`cron_list` / `cron_add` / `cron_update` / `cron_remove` /
  `cron_history`

### `schedule` — 会话本地持久提醒

服务键 `'schedule'`（`ctx.schedule`）与 `'scheduleRuntime'`（`ctx.scheduleRuntime`）。
模型用 `schedule_create` / `schedule_list` / `schedule_delete` 三个工具管理当前会话的
提醒。提醒没有独立存储：唯一权威是会话里的 `schedule/change` 事件（协议版本 1，严格
解码 —— 未知版本、额外字段、id 复用、指向非活动记录的转换都会失败），因此会话落盘后
重启会自动重建，而 fork 出的会话不会继承父会话的活动提醒。

选择器三选一：`after_seconds`（正安全整数秒）、`at`（显式偏移的 RFC 3339 串，或
`{date, time, time_zone}` 本地日历对象；IANA 时区，夏令时缺口拒绝、重叠取较早）、
`every_seconds`（不小于 300 秒的固定间隔，与创建锚点对齐且只追赶最新一次）。读取与
变更前会等待持久化检查点，无法确认时返回 `persistence_uncertain`，而不是声称成功。

到期交付由 `ScheduleRuntime` 驱动：折叠 → 采样墙钟 → 构造固定 framing → 经注入的
交付端口投递 → **投递成功之后**才追加派发记录。端口返回 `false`（例如会话正在回答）
时不写派发记录，记录保持活动，等下一次触发（轮次结束或定时唤醒）。

```dart
final schedule = provideSessionSchedule(ctx, session: session, sessions: store);
provideScheduleTools(ctx);

// 交付端口由宿主提供：空闲时投递并返回 true，忙时返回 false
provideScheduleRuntime(ctx, deliver: (String text) async => submit(text));
```

- 一次性提醒优先于固定间隔批次；批次内每条记录只取最新一个发生时点，整批共用同一个
  决策时点；
- 交付只在原会话内进行：没有邮件 / 短信 / 推送，冷会话只会在恢复后处理逾期记录。

### `system-prompt` — prompt 段装配

服务键 `'systemPrompt'`。各插件注册 `PromptSection` / `PromptContext`（`order` 升序、
同序按名字），`assemble()` 每次求值 provider，`render()` 拼接段、`renderContexts()`
拼接动态上下文（空文本不贡献内容），两者都插值 `{{variable}}`。`AgentLoop` 组装
system 时按「段 → 上下文 → 历史摘要 → 当前计划 → 相关记忆」的顺序拼接：人设与环境
事实分开注册，各自都能每轮刷新。

```dart
final prompt = provideSystemPrompt(app);
ctx.effect(() => prompt.section(PromptSection(
  name: 'persona',
  order: 0,
  text: () => '你是{{name}}。',
)));

final text = prompt.render(prompt.assemble(variables: {'name': '助手'}));
```

人设可在运行时动态调整：`PromptSection.text` 是每次装配都重新求值的闭包，把人设文本
绑到可变状态即可；`AgentLoop` 每轮 `run()` 都会重新装配，改动在下一轮生效。

```dart
var persona = '你是助手。';
prompt.section(PromptSection(name: 'persona', text: () => persona));

persona = '你是简洁的中文翻译。'; // 下一轮 run() 生效
```

需注意：`AgentLoop` 持有的是同一个 `SystemPrompt` 实例引用，替换 `'systemPrompt'`
服务不会影响已建好的 loop，必须改原实例；同名 `section` 重复注册会抛 `StateError`。

### `time-context` — 日期锚点

模型没有时钟：相对日期（"明天""下周三"）与带本地语义的时刻（"明早九点"）都需要一个
外部锚点才能换算成绝对时间。`provideTimePrompt` 注册一份日粒度的 `PromptContext`
（名字 `time`），每轮装配重新求值，因此跨天自动更新。

```dart
final prompt = provideSystemPrompt(app);  // 必须先有
provideTimePrompt(app);                   // 本地时区名
provideAgentLoop(app, session: session);  // 自动取上面这个 prompt

// 变体
provideTimePrompt(app, zoneName: 'Asia/Shanghai'); // 指定时区名
provideTimePrompt(app, prompt: prompt);            // 显式指定注册表
provideTimePrompt(app, clock: () => fixedNow);     // 固定时钟（测试 / 回放）
ctx.effect(() => provideTimePrompt(app));          // 随上下文卸载撤销
```

顺序有约束：`provideAgentLoop` 通过 `ctx.get<SystemPrompt>('systemPrompt')` 接入，
`provideTimePrompt` 又通过 `ctx.require<SystemPrompt>('systemPrompt')` 取目标注册表，
因此它要排在 `provideSystemPrompt` 之后、`provideAgentLoop` 之前；上下文里没有
`SystemPrompt` 时 `require` 直接抛 `StateError`。

装配出的 system 形如：

```text
你是"助手"，一位耐心、务实的助手。需要实时信息或操作时调用工具；否则直接简洁回答。

[当前时间]
2026-09-16 周三 · Asia/Shanghai (UTC+08:00)
```

| 参数 | 缺省 | 说明 |
|------|------|------|
| `prompt` | `ctx.require('systemPrompt')` | 目标注册表 |
| `clock` | `DateTime.now` | 注入固定时钟，便于测试与回放 |
| `zoneName` | `clock().timeZoneName` | 本机时区名常是缩写（macOS 上会给出 `CST` 这类有歧义的值），跨时区部署请显式给 IANA 名 |

三点注意：

- 锚点只精确到日：system 是可缓存前缀，秒级变化会让前缀缓存每轮失效；"现在几点"
  这类问题交给时间工具；
- 没走 `SystemPrompt` 的装配（例如直接 `AgentLoop(defaultSystemPrompt: ...)`）不会
  有锚点，那是一条独立分支；
- 与段一样可撤销：`ctx.effect(() => provideTimePrompt(app))`。

精确到秒的时间工具由装配方提供（`conatus_tui` 已内置，见其 `tui_app.dart`）：

```dart
app.effect(() => app.tools.fn(
      'get_time',
      description: '返回当前本地时间（RFC 3339，带时区偏移）',
      handler: (ToolContext ctx) async {
        final DateTime now = DateTime.now();
        return ToolResult.success(
            '${now.toIso8601String()}${formatClockOffset(now.timeZoneOffset)}');
      },
    ));
```

锚点行为由 `packages/conatus_foundation/test/time_context_test.dart` 与装配级端到端
`packages/conatus_tui/test/tui_runtime_assembly_test.dart`（断言模型实际收到的 system
含 `[当前时间]`）守住。

### `compaction` — 会话滚动摘要

服务键 `'compaction'`（`conatus_compaction` 包）。事件数超过 `keepRecent` 时，把较早
的事件连同上一版摘要交给注入的 `Summarizer`（通常是 `llm`），产出新摘要并按会话缓存；
日志本身不被改写，压缩只在其后追加 `compaction/start` → `compaction/summary` →
`compaction/end` 三个记录事件，使摘要可从日志重建。

切点会先吸附到不劈开工具调用与结果的最近位置（`balancedCutAtOrBefore`），没有可折叠
的平衡切点时本次不压缩。

```dart
final compaction = provideCompaction(app, engine: Compactor(keepRecent: 20));
final result = await compaction.compactIfNeeded(session, (events, previous) async {
  return CompactionSummary(await summarizeWithLlm(events, previous));
});
```

### `layered-compaction` — 分层压缩与内容分类器

服务键同为 `'compaction'`（与 `provideCompaction` **二选一**，重复提供会抛错）。
`LayeredCompactor` 是 `Compactor` 的 drop-in 替身：接口与契约完全一致，区别在
`summarizeFolded` 按内容类别分别处理，而不是一律压成一段摘要。

```dart
provideContentClassifier(app);    // 服务键 'contentClassifier'
provideLayeredCompaction(app);    // 注册 'compaction'
```

- 工具结果压成「工具名 + 结果首行 + 字符数」一行，并指向会话日志中的 `tool/result`
  事件（**不**额外落盘）；用户偏好原文保留；早期对话交给注入的汇总器产出摘要；
  近期窗口不处理，留给 Agent Loop 的滑动窗口；
- `ContentClassifier` 是能力缝：`classify(message)` / `strategyFor(category)` /
  `recentWindow`，默认实现 `RuleBasedContentClassifier({recentWindow})`（角色 +
  关键词 + 位置窗口，全部可解释）；`provideContentClassifier(ctx, {classifier})`
  注册 `'contentClassifier'`；
- `MessageCategory`：systemPrompt / toolDefinition / skillList / toolResult /
  userPreference / userTask / earlyConversation / recentConversation；
  `CompressionStrategy`：none / keep / summarize / evict；
- 产出 `context.compacted` 遥测：`tokensBefore` / `tokensAfter` / `compacted` /
  `kept` / `toolResults` / `preferences`；`estimateTokens` / `estimateMessagesTokens`
  是 chars/4 的粗估，`tokensBefore` / `tokensAfter` 由它们给出。

### `context-cache` — 可缓存前缀与缓存度量

服务键 `'contextCache'`（`ctx.contextCache`）。豆包 / DeepSeek 由**服务端**按请求
前缀自动缓存，本插件因此只做度量：算前缀指纹、从回包 `usage` 派生命中，**不往请求体
塞任何非标字段**。

```dart
provideContextCache(app);            // telemetry 缺省取 'telemetry'
final agent = provideAgentLoop(app); // 提供 'contextCache' 时自动包一层度量
```

- `LlmMessage.cacheable` 是**本地标记**，不写入请求体，只用来标记稳定前缀
  （system prompt + 工具定义）；
- `CachePlan.of(messages)` 求从头的**连续**可缓存前缀，给出稳定 `cacheKey` 与
  `cacheableMessages` / `cacheableChars`（尾部增删消息不改变指纹，前缀内任何一条
  变化都会改变指纹）；
- `CachingLlmProvider` 原样透传请求，非流式 `chat` 返回后经 `ContextCache.recordHit`
  记命中并产出 `context.cache` 遥测（`cacheKey` / `cacheableMessages` /
  `cacheableChars` / `hit`，`hit` 从 provider 回包 `usage` 派生）；`hits` / `misses` 可读。

### `memory` — 长记忆库 + 显式记住 / 遗忘

服务键 `'memory'`。`remember` / `recall` / `forget` / `clear`：召回按查询词元与记忆
文本/标签的重叠数打分（英文按词、中文按二元组），同分按新→旧；超过 `maxEntries`
逐出最旧一条。存储经 `MemoryBackend` 端口，默认纯内存，`JsonMemoryBackend` 落盘。

显式遗忘另有两个方法：`forgetByText(text)`（正文完全一致）与 `forgetMatching(query)`
（正文包含，不区分大小写），均返回删除条数。这些都是**能力**，宿主/用户可直接调用；
模型侧由 `remember` / `forget` 两个工具调用同一能力（`provideRememberTool` /
`provideForgetTool` / `provideMemoryTools`）。

```dart
final memory = provideMemory(app); // 或 provideMemory(app, backend: JsonMemoryBackend(file: File('memory.json')))
await memory.remember('用户喜欢京剧', tags: {'偏好'});
for (final e in memory.recall('京剧', limit: 3)) print(e.text);

// 直接调用能力（不经模型）
await memory.forgetByText('用户喜欢京剧');
await memory.forgetMatching('京剧');
await memory.forget(id);

// 交给模型：注册 remember / forget 工具
provideMemoryTools(app);
```

### `database` — KV 存储 hub + 可插拔后端

服务键 `'database'`。hub 本身不做 IO：具名后端（默认 `JsonDatabaseBackend`，每单元
一个 JSON 文件、整表原子发布）拥有介质，`open(unit)` 载入整表并返回句柄。句柄
同步读、异步写，落盘成功后才广播 `DatabaseChange`，因此读到内存永不领先介质。

```dart
final db = provideDatabase(app, defaultBackend: 'json');
provideDatabaseJson(app);            // 注册名为 'json' 的后端

final unit = await db.open('profile');
unit.onChange((change) => print(change.key));
await unit.put('name', '助手');
print(unit.get('name'));
```

- 多个后端可并排注册，`open(unit, backend: '...')` 按次路由；未指定时用 `defaultBackend`，仅注册一个后端时自动选中，否则抛 `no-backend`；
- 错误统一由 `DatabaseException` 携带错误码（`backend-not-found` / `already-open` / `unit-closed` / `malformed-medium` …）。

### `agent` — Agent Loop

服务键 `'agentLoop'`（`ctx.agentLoop`）。一轮 `run(userInput)`：写入用户事件并压缩
上下文 → 组装 system（`SystemPrompt` 装配 + 历史摘要 + `MemoryStore` 召回）+
会话事件派生的历史 → 调 `LlmProvider.chat`（带 `tools.describe()` 的 schema）→
有工具调用就执行、把结果回填为 `tool` 消息并继续 → 纯文本收口，写入会话并记入
长记忆。

```dart
provideTools(app);
app.effect(() => app.tools.fn('get_time',
    description: '返回当前本地时间（RFC 3339，带时区偏移）',
    handler: (ctx) async {
      final now = DateTime.now();
      return ToolResult.success(
          '${now.toIso8601String()}${formatClockOffset(now.timeZoneOffset)}');
    }));
provideLlm(app);
final session = provideSessions(app).create(id: 'cli');
final prompt = provideSystemPrompt(app);
prompt.section(
    PromptSection(name: 'persona', text: () => '你是助手，需要实时信息时调用工具。'));
provideTimePrompt(app);            // 日期锚点：模型不必调工具就知道今天
provideMemory(app);
provideCompaction(app);            // keepRecent 默认 20
final agent = provideAgentLoop(app, session: session);

final turn = await agent.run('现在几点？');
print(turn.reply);                 // 已收口的文本
for (final step in turn.steps) print('${step.call.name}: ${step.result.content}');
```

- 依赖 `llm` + `tools`；`systemPrompt` / `compaction` / `memory` / `sessions` 存在时自动接入；提供了 `sessionLogRecorder` / `contextCache` 时另外叠加轨迹记录与缓存度量（见 `session-log` / `context-cache`）；
- 工具失败（`ToolResult.isError`）作为失败结果回填，不中断循环；会话在循环中被关闭会中止（`StateError`）；
- 循环有界（`maxSteps`，默认 8）；所有依赖可注入以便测试；
- 会话事件（`user/message` / `assistant/message` / `tool/result`）可用 `deriveAgentMessages` 还原为模型消息序列。

---

## 实验性能力包

以下 6 个包是 `publish_to: none` 的实验性包，不进伞包，需显式依赖
（`import 'package:conatus_alerting/conatus_alerting.dart';` 等）。API 可能在没有
major 版本号变更的情况下发生破坏性改动，请勿在生产环境依赖。

### `alerting` — 主动告警（`conatus_alerting`）

`conatus_observability` 负责**收集和导出**（被动管道），本包负责**检测和通知**：
订阅 `telemetry` 事件流，用声明式规则判断「什么不对劲」，再经控制台 / Webhook /
语音主动告诉用户。智能音箱场景下用户不在屏幕前，异常需要 Agent 主动播报。

```dart
provideTelemetry(app);
provideAlerting(app);              // 默认 8 条规则 + ConsoleNotifier

// 或：自定义规则与通知渠道（与上一行二选一）
provideAlerting(app,
    notifier: WebhookNotifier(url: Uri.parse('https://hooks.example.com/xxx')),
    rules: RuleParser.parse(jsonDecode(File('alerts.json').readAsStringSync())));
```

默认规则覆盖 LLM 慢 / 工具慢 / 工具连续失败 / Session 与当日预算 / Agent 轮次超限 /
子 Agent 卡住；规则可从 JSON 加载，冷却期防告警风暴，通知失败不阻塞主流程。
详见 [`packages/conatus_alerting/README.md`](packages/conatus_alerting/README.md)。

### `browser_use` — 浏览器操作（`conatus_browser_use`）

`web_search` 只返回搜索摘要、`fetch_url` 只返回文本，都是**只读的**；本包补上
**交互能力**（填表单、点按钮、翻页、等待异步加载）。工具由 Provider 拥有，注册进
`ctx.tools`，模型可直接调用。

```dart
provideTools(app);
provideBrowserUse(app,
    provider: PlaywrightMcpProvider(
        command: 'npx', args: <String>['-y', '@playwright/mcp@latest']),
    session: session);             // 浏览器绑定 Session，跨轮次复用
```

浏览器绑定使用它的**确切实时 Session**：Session 释放时关闭其启动的资源；fork 后用
`initializeBrowserFor` 创建全新浏览器状态（profile 与登录状态不恢复）。工具按
`browserToolRisk` 分 low / medium / high，高危操作走 `approval`。
详见 [`packages/conatus_browser_use/README.md`](packages/conatus_browser_use/README.md)。

### `computer_use` — 桌面操作（`conatus_computer_use`）

让模型观察并操作**本地桌面**（截屏、移动鼠标、点击、输入）。与 browser-use 的关键
区别：桌面是共享资源，**没有 Session 级别的所有权**，取消调用也无法撤销已送达的
输入；因此所有输入操作一律 `high` 风险，走审批。

```dart
provideTools(app);
provideComputerUse(app,
    provider: CuaDriverMcpProvider(command: 'cua-driver', args: <String>['mcp']));
```

支持图像的模型路由接收**持久化截图**（挂 `attachmentStore`），不支持的接收 MCP
图像诊断文本（`imageSupportFor`）。要把操作记进触发它的 Session 日志，用
`registerDesktopTools`。
详见 [`packages/conatus_computer_use/README.md`](packages/conatus_computer_use/README.md)。

### `team` — 多智能体协作（`conatus_team`）

回答「谁创建谁、谁跟谁说话、怎么同步进度、什么时候停」。成员有**独立的上下文窗口**，
只经任务板与直达消息交换**结论**、不交换**过程**；成员生命周期绑定队长，队长释放时
成员自动终止。

```dart
provideAgentTeam(app, session: session, telemetry: telemetry);
provideTeamTools(app, team: app.team, tools: app.tools);   // 10 个团队工具
```

协作模式：`sequential` / `concurrent` / `group_chat` / `maker_checker`。端到端示例：
`cd packages/conatus_team && dart run example/demo.dart`（无需 API Key）。
详见 [`packages/conatus_team/README.md`](packages/conatus_team/README.md)。

### `workflow` — 流程编排（`conatus_workflow`）

把多 Agent 协作**沉淀为可复用的流程资产**：流程是**数据**（声明式 JSON），不是代码，
可被模型生成、被用户编辑、被版本管理。节点分 tool / agent / sub-workflow 三类，
支持 DAG 依赖、条件 guard，以及暂停 / 恢复 / 重跑 / 取消。

```dart
provideWorkflow(app, team: app.team, tools: app.tools);
provideWorkflowTools(app);         // 8 个流程工具
await engine.register(definition);
final run = await engine.start('code-review', inputs: {...});
```

流程只能引用**已注册的能力**（工具、成员、子流程），未注册的引用在注册或执行时报
`WorkflowException`。详见 [`packages/conatus_workflow/README.md`](packages/conatus_workflow/README.md)。

### `observability` — 可观测性导出（`conatus_observability`）

把 `telemetry` 埋点与 `session_log` 事件流导出到真实可观测性后端，并提供分布式追踪
与成本追踪语义。当前已落地 **span 语义 + 从 Session Log 派生 trace**，OTLP /
Prometheus / JSONL 导出器按实现方案陆续补齐。

```dart
final spans = await TraceBuilder(sessionLog: log).buildTrace('session-1');
// 根 span 是 agent.turn，其下挂 llm / tool / subagent 子 span
```

离线示例：`cd packages/conatus_observability && dart run example/observability_demo.dart`。
详见 [`packages/conatus_observability/README.md`](packages/conatus_observability/README.md)
与 [`doc/usage.md`](packages/conatus_observability/doc/usage.md)。

### `intent` — 意图路由（`conatus_intent`）

**先用正则和向量做本地意图匹配，命中就直接执行动作，不命中才走完整 Agent Loop。**
高频请求（「开灯」「关灯」「设个闹钟」）是固定模板，完全不需要模型；正则处理固定
命令（微秒级），向量处理正则覆盖不到的同义表达（毫秒级），模型只处理真正复杂的请求。

```dart
final IntentRouter router = provideIntentRouter(app);   // 必须早于 provideAgentLoop
router.register(Intent(
  name: 'light_on',
  description: '开灯',
  patterns: <Pattern>[RegExp(r'^(开灯|把灯打开)')],
  action: const ToolAction(
    tool: 'device_control',
    argsTemplate: <String, Object?>{'device': 'light', 'op': 'on'},
  ),
));
```

接线走 `conatus_agent` 已有的确定性路由 seam（`Router` / `RouteReply` / `RouteTools` /
`RoutePass`），**不改 Agent Loop**：直接动作直接收口（零模型调用），工具动作与委托动作
预置工具调用后由模型收口，未命中落回完整 Agent Loop。意图可从 JSON 配置加载，可由
`SkillIntentBridge` / `ToolIntentGenerator` / `IntentLearner` 产出候选（都需人工确认）。

离线示例：`cd packages/conatus_intent && dart run example/demo.dart`（无需 API Key）。
详见 [`packages/conatus_intent/README.md`](packages/conatus_intent/README.md)。

---

## 核心概念

### 效应（Effect）与时间可组合性

效应是**可逆的副作用**。每一次施加都同时提供一个撤销函数：

```dart
ctx.track(() => subscription.cancel());        // 手动登记
final sub = ctx.effect(() => stream.listen(onData)); // 自动登记返回值
ctx.onDispose(() => timer.cancel());           // 语义化别名
```

卸载时，`EffectScope` 按 **LIFO** 顺序执行所有撤销函数，保证依赖逆序解除。

三个关键性质：

| 性质 | 说明 |
|------|------|
| **幂等** | 重复释放只生效一次 |
| **迟到安全** | 释放后再 `track`，撤销函数会立即执行 |
| **抗异常** | 单个撤销抛错不阻断其余撤销；错误由 `dispose()` 返回 |

### 共效应（Coeffect）与空间可组合性

共效应是**声明式依赖**。组件不主动查找服务，而是声明“我需要什么”，由运行时决定何时激活：

```dart
ctx.inject(['database', 'logger'], (child) {
  // 只有当 database 与 logger 都可用时，这里才会执行；
  // 一旦任一服务消失，child 会被释放，其所有效应自动撤销。
  final db = child.require<Database>('database');
});
```

服务通过 `provide` 注册：

```dart
final stop = ctx.provide('logger', Logger()); // 返回 Disposer，可提前撤销
stop(); // 服务消失，所有依赖它的 inject 会自动停用
```

### 上下文树

`Context` 组成一棵树，服务查找沿父链向上：

```
root ──┬── pluginA ──┬── sub1
       └── pluginB   └── sub2
```

- 子上下文**可见**父上下文提供的服务
- 子上下文提供的服务**对父级不可见**
- 父上下文释放会**级联释放**整个子树

### 重入收敛

当一个 `inject` 回调内部又 `provide` 新服务时，可能触发其他 `inject` 的激活。`Reactor` 用“脏标记 + 重跑”策略把这一连串反应在一次 `notify()` 内跑完，直到系统稳定：

```dart
// 假设 A 依赖 x，激活后提供 y；B 依赖 y
root.provide('x', 1);
// → 一次 notify 内：
//   A 激活 → 提供 y → B 激活
// 结束后系统稳定，两个组件都处于激活状态
```

若因循环依赖导致无法在 `maxRounds` 内收敛，会抛出 `StateError` 快速失败。

---

## API 速查

### `Context`

| 成员 | 说明 |
|------|------|
| `Context.root({String name})` | 创建根上下文 |
| `get<T>(String key) → T?` | 沿父链查找服务 |
| `require<T>(String key) → T` | 找不到时抛 `StateError` |
| `has(String key) → bool` | 服务是否可见 |
| `provide(String key, Object? value) → Disposer` | 提供服务 |
| `track(Disposer)` | 登记撤销函数 |
| `effect<T>(T Function()) → T` | 执行并自动登记 `Disposer` 返回值 |
| `onDispose(Disposer)` | `track` 的语义化别名 |
| `inject(List<String>, void Function(Context)) → Disposer` | 声明式依赖注入 |
| `plugin(String, void Function(Context)) → Context` | 加载插件 |
| `dispose()` | 释放上下文及所有效应、服务、子上下文 |

### `EffectScope`

| 成员 | 说明 |
|------|------|
| `track(Disposer)` | 登记撤销函数 |
| `capture<T>(T Function()) → T` | 执行并自动登记 |
| `dispose() → List<Object>` | 释放，返回捕获到的错误 |
| `disposed → bool` | 是否已释放 |
| `length → int` | 当前登记的撤销函数数量 |

### `Reactor`

| 成员 | 说明 |
|------|------|
| `Reactor({int maxRounds = 100})` | 创建反应器 |
| `add(ReactorListener)` / `remove(...)` | 增删监听器 |
| `notify()` | 触发广播（含重入收敛） |

### `LlmProvider` / `FallbackLlm`

| 成员 | 说明 |
|------|------|
| `chat(messages, {options, tools}) → Future<LlmResult>` | 非流式补全（`tools` 触发原生 function calling） |
| `chatStream(messages, {options, tools}) → Stream<LlmStreamEvent>` | 流式补全 |
| `close()` | 释放底层 HTTP 客户端 |
| `OpenAiCompatibleProvider({name, baseUrl, model, ...})` | 任意 OpenAI 兼容端点，`apiStyle` 默认 `chat` |
| `FallbackLlm(providers)` | 顺序回退链；`defaultFallbackLlm()`（豆包 → DeepSeek）在 `conatus_providers` |
| `LlmTextDelta` / `LlmReasoningDelta` / `LlmStreamDone` | 流式事件：正文增量 / 思考增量 / 终态（用量、结束原因、累积的工具调用） |

### `Credentials`（`credentials`）

| 成员 | 说明 |
|------|------|
| `provideCredentials(ctx, {credentials})` / `ctx.credentials` | 提供 `'credentials'`（缺省 `EnvCredentials`，随上下文释放关闭） |
| `get(key) → Credential?` / `require(key) → Credential` | **同步**读内存快照；缺失或已过期返回 `null` / 抛 `CredentialsException('missing')` |
| `validate(keys)` | 批量校验必填键 |
| `update(key, value) → Future<void>` | 写入；只读来源抛 `CredentialsException('read-only')` |
| `refresh()` / `changes` / `keys` / `close()` | 拉取远端 / 变更流 / 键列表 / 释放 |
| `Credential({key, value, expiresAt})` | `masked`（前 4 + `...` + 后 4，≤ 8 全星号）/ `expired`；`toString()` 只含脱敏值 |
| `EnvCredentials({environment})` / `InMemoryCredentials({initial})` | 环境变量（默认）/ 内存（唯一可写来源） |
| `FileCredentials({path, fallback, refreshInterval})` | 本地 JSON，支持定时刷新 |
| `VaultCredentials({config})` / `VaultConfig({address, token, path, mount, refreshInterval})` | HashiCorp Vault KV v2 |
| `AwsSecretsCredentials({config})` / `AwsSecretsConfig({accessKey, secretKey, region, secretId, sessionToken, endpoint, refreshInterval})` / `SigV4Signer` | AWS Secrets Manager（SigV4 手写签名） |
| `CredentialsSource` / `CredentialsException(code, message)` / `parseCredentialMap(raw)` | 来源枚举 / 稳定错误码 / 共用的 JSON 解析 |

### `TimerContext`（`timer`）

| 成员 | 说明 |
|------|------|
| `timeout(callback, delay) → Disposer` | 延迟执行一次，可提前取消 |
| `interval(callback, delay) → Disposer` | 周期执行，可提前取消 |
| `sleep(delay) → Future<void>` | 等待；上下文释放时以 `StateError` 结束 |
| `throttle(callback, delay, {trailing}) → Throttled` | 节流包装（`call()` / `dispose()`） |
| `debounce(callback, delay) → Debounced` | 防抖包装（`call()` / `dispose()`） |

### `LoggerService` / `Logger`（`logger-console`）

| 成员 | 说明 |
|------|------|
| `provideLogger(ctx, {logger, level, console, writer, showTime}) → LoggerService` | 提供 `'logger'` 服务并挂控制台导出 |
| `logger([name]) → Logger` | 命名 logger 门面 |
| `debug/info/warn/error(message, [error, stackTrace])` | 分级记录（服务方法用 `defaultName`） |
| `addExporter` / `removeExporter` | 增删导出器 |
| `level` / `recentLimit` / `recent` | 全局级别 / 最近日志缓冲 |
| `ConsoleExporter({writer, level, showTime})` | 控制台导出（`[I] name  message`） |

### `Loader`（`loader`）

| 成员 | 说明 |
|------|------|
| `provideLoader(ctx, {plugins, config}) → Loader` | 提供 `'loader'` 服务，可选预注册与初始配置 |
| `register(name, factory)` / `unregister(name)` / `has(name)` | 插件注册表 |
| `apply(entries)` / `applyJson(json)` | 全量替换配置树 |
| `load(entry, {parent}) → String` | 加载 entry（分组递归加载 children） |
| `remove(id)` | 卸载 entry 及其所有后代 |
| `reload(id)` | 重启单个 entry |
| `ids` / `isEmpty` / `contextOf(id)` / `entryOf(id)` | 查询已加载 entry |

### `ToolRegistry`（`tools`）

| 成员 | 说明 |
|------|------|
| `provideTools(ctx, {tools, timeout}) → ToolRegistry` / `ctx.tools` | 提供 `'tools'` / 快捷访问 |
| `Tool({name, description, riskLevel, group, timeout, pathParams, params, call})` | 工具基类（`toSchema()` 白名单投影；`timeout` 覆盖注册表默认超时；`pathParams` 声明路径参数供审批按目录授权） |
| `ParamSpec.string/.integer/.number/.boolean/.enumeration/.array/.object` + `parameterSchema` | 参数声明与 schema 生成 |
| `ToolContext`（`str` / `integer` / `number` / `boolean` / `array` / `object` / `require<T>`） | 类型安全取参 |
| `register(Tool) → Disposer` | 注册工具（同名重复抛 `StateError`） |
| `call(ToolCall, {timeout}) → Future<ToolResult>` | 校验 → 守卫 → 中间件 → 执行体（收敛失败；超时按 调用参数 > `Tool.timeout` > `defaultTimeout` 取用） |
| `describe()` / `describeOne(name)` | 当前可见工具的模型 schema |
| `fn(name, {...}) → Disposer`（`ctx.tools.fn`） | 一行注册简单工具 |
| `group(name, [tools]) → Disposer`（`ctx.tools.group`） | 按领域分组；`groups` / `groupOf` / `namesIn` / `describeGroup` |
| `guardRisk(ToolRisk) → Disposer` / `describeWithin(ToolRisk)` | 能力分级：拒绝/投影越级工具 |
| `guard(ToolGuard)` / `use(ToolMiddleware)` / `onChange(fn)` / `onResult(fn)` | 守卫 / 中间件 / 变更 / 结局监听 |

### `McpRegistry` / `McpClient` / `McpToolAdapter`（`mcp`）

| 成员 | 说明 |
|------|------|
| `provideMcp(ctx, servers, {aliases, credentials, transportFactory})` / `ctx.mcp` | 提供 `'mcp'`；异步装配，返回 `Future<McpRegistry>` |
| `McpRegistry`：`servers` / `clientOf(name)` / `toolsOf(name)` / `attach(ctx, client)` / `addAlias(ctx, alias, fullName)` / `close()` | 多 server 连接、别名与生命周期 |
| `McpClient({transport, serverName, timeout})` | 握手、`tools/list` 分页、`tools/call` 按 id 关联（超时默认 30s） |
| `McpTransport` / `StdioTransport` / `HttpTransport` / `SseTransport` | 传输缝与三种实现（`connect` / `disconnect` / `send` / `messages` / `diagnostics`） |
| `McpServerConfig({name, type, command, args, env, url, headers})` / `McpTransportType` / `McpException` | server 配置 / 传输类型 / 错误 |
| `McpToolAdapter({client, tool})` / `mcpToolName(server, tool)` / `mcpToolRisk(tool)` | 服务端工具 → `Tool`（`server__tool`、`group` 为 `mcp:<server>`、`toSchema()` 直通 `inputSchema`） |
| `McpToolAlias({inner, alias})` / `toolResultFromMcp(result)` / `describeMcpContent(content)` | 短别名 / 结果转换 / 内容摘要 |
| `resolveCredentialPlaceholders(raw, credentials)` | 解析 `env` / `headers` 里的 `${KEY}`（未命中原样保留） |

### `SearchService`（`search`）

| 成员 | 说明 |
|------|------|
| `provideSearch(ctx, {search, providers, exaApiKey})` / `ctx.search` | 提供 `'search'` / 快捷访问 |
| `register(SearchProvider) → Disposer` / `providers` / `get(name)` | provider 注册与查找 |
| `search(query, {limit, provider}) → Future<List<SearchResult>>` | 顺序回退查询 |
| `DuckDuckGoSearchProvider({client, endpoint})` / `ExaSearchProvider({apiKey, client, endpoint})` | 内置 provider |
| `WebSearchTool({search, defaultLimit})` / `FetchUrlTool({client, maxChars})` / `provideWebTools(ctx, {...})` | web_search / fetch_url 工具 |

### `AsrService`（`asr`）

| 成员 | 说明 |
|------|------|
| `provideAsr(ctx, {asr, providers, apiKey, appKey, accessKey, resourceId, url, auth})` / `ctx.asr` | 提供 `'asr'` / 快捷访问（凭据优先级：`auth` > 参数 > 环境变量） |
| `register(AsrProvider) → Disposer` / `providers` / `get(name)` | provider 注册与查找 |
| `start({provider, audio, language, hotwords}) → Future<AsrSession>` | 顺序回退建连 |
| `transcribe(audio, {...}) → Stream<AsrEvent>` / `transcribeText(audio, {...}) → Future<String>` | 输入源无关的识别 |
| `DoubaoStreamingAsrProvider({apiKey, appKey, accessKey, resourceId, url, auth, ...})` | 豆包/火山 SAUC 流式 provider（`auth` 为动态签名/短时令牌回调） |
| `AsrAudioSource` / `FfmpegMicSource({executable, input, device, format})` / `transcribeSource(asr, source, {...})` | 音频来源缝 + ffmpeg 麦克风 |
| `TranscribeAudioTool({asr, provider, chunkBytes})` / `provideAsrTools(ctx, {...})` | `transcribe_audio` 工具 |
| `AsrResult` / `AsrUtterance` / `AsrPartial` / `AsrFinal` / `AsrException` | 结果 / 分句 / 事件 / 错误 |

### `TtsService`（`tts`）

| 成员 | 说明 |
|------|------|
| `provideTts(ctx, {tts, providers, apiKey, appKey, accessToken, resourceId, voice, url})` / `ctx.tts` | 提供 `'tts'` / 快捷访问 |
| `register(TtsProvider) → Disposer` / `providers` / `get(name)` | provider 注册与查找 |
| `start(sink, {provider, voice, format, speed, volume, pitch}) → Future<TtsSession>` | 顺序回退建连 |
| `speak(text, sink, {...})` / `synthesize(text, {...}) → Future<List<int>>` | 合成到任意 sink / 收进内存 |
| `TtsAudioSink` / `BytesAudioSink` / `StreamAudioSink` / `CallbackAudioSink` | 音频输出接口与内置实现 |
| `DoubaoStreamingTtsProvider({apiKey, appKey, accessToken, resourceId, voice, url, ...})` | 豆包/火山 v3 WebSocket 单向流式合成 provider |
| `TtsAudioFormat` / `TtsVoice` / `TtsSession` / `TtsException` | 格式 / 音色 / 会话 / 错误 |

### `ShellExecutor`（`shell`）

| 成员 | 说明 |
|------|------|
| `provideShell(ctx, {executor})` / `provideShellLocal(ctx, {executor})` | 注入自定义 / 本地执行器 |
| `resolve(ShellExecRequest) → ShellExecSpec` | 补齐 workdir、封顶 timeout |
| `run(ShellExecSpec) → Future<ShellRunResult>` | 前台执行（非零退出/超时正常返回） |
| `start(ShellExecSpec) → Future<ShellProcess>` | 后台进程句柄（`done` / `readOutput` / `kill`） |
| `LocalShellExecutor({cwd, timeoutMs, maxTimeoutMs, maxOutputBytes})` | 本地实现 |
| `ShellRunResult` | `exitCode` / `timedOut` / `stdout` / `stderr` |

### `FileSystem`（`fs`）

| 成员 | 说明 |
|------|------|
| `provideFileSystem(ctx, {fs})` / `provideFileSystemLocal(ctx, {fs})` | 注入自定义 / 本地后端 |
| `resolve(path, {cwd}) → Future<FsTarget>` | 解析为稳定目标身份 |
| `stat(target)` / `lstat(path)` | 元数据（后者不跟随链接） |
| `readText(target)` / `listDir(target)` | 读取文本 / 稳定排序列举 |
| `writeText(target, content, {expected})` | 原子写入（可选 `FsCreateIfAbsent` / `FsReplaceIfVersion` 守卫） |
| `editText(target, edit, {expectedVersion})` | 原子字面替换（多处匹配 → `FS_AMBIGUOUS_EDIT`） |
| `contains(parent, child)` / `fileUrl(target)` / `processPath(target)` | 身份与坐标 |
| `FsError` / `FsErrorCode` | 带稳定错误码的异常 |

### `Session` / `SessionStore`（`session`）

| 成员 | 说明 |
|------|------|
| `Session({id, seed})` | 一次会话（append-only 事件日志） |
| `append(type, {data}) → SessionEvent` | 追加事件（分配 `seq`） |
| `events` / `length` / `closed` | 事件只读视图 / 条数 / 是否已关闭 |
| `onEvent(fn)` / `onClose(fn) → Disposer` | 监听追加 / 关闭 |
| `SessionStore({persistence})` / `provideSessions(ctx, {sessions, persistence})` | 提供 `'sessions'` |
| `create({id})` / `open(id)` / `get(id)` / `close(id)` / `remove(id)` | 会话生命周期 |
| `persistedIds()` / `flush()` | 已持久化 id / 等待在途写入 |
| `provideSessionPersistence(ctx, {persistence})` / `JsonlSessionPersistence({dir})` | 提供 `'sessionPersistence'` / 本地 JSONL |
| `SessionEvent.create({sessionId, type, seq, data, parentEventId, time, id})` / `nextSessionEventId()` | 构造带唯一 id 的事件（`sessionId` / `parentEventId` 表达归属与因果） |
| `appendEvent(event) → SessionEvent` / `lastEventId` | 回填已构造的事件（按本会话重盖章 id 与 seq）/ 最后一条事件 id |
| `read({from, to})` / `fork({fromEventId, id})` / `replay(handler)` | 按时间（闭区间）读取 / 从事件点分叉出新会话 / 按序重放 |
| `SessionEvent.copyWith(...)` / `toJson()` | 复制事件 / 序列化（`data` 中的敏感字段自动脱敏） |

### `SessionLog` / `SessionLogRecorder`（`session-log`）

| 成员 | 说明 |
|------|------|
| `provideSessionLog(ctx, {log, persistence, database})` / `ctx.sessionLog` | 提供 `'sessionLog'`；后端优先级：显式 → `sessionPersistence` → `database` → 内存 |
| `SessionLog`：`append(event)` / `read(sessionId, {from, to})` / `fork(sessionId, fromEventId, {newId})` / `replay(sessionId, handler)` / `list()` / `close()` | 多会话只追加日志抽象（`seq` 按会话分配） |
| `InMemorySessionLog()` / `PersistenceSessionLog(persistence)` / `DatabaseSessionLog(database, {unit})` | 三个后端；`PersistenceSessionLog` 追加写，长会话推荐 |
| `SessionLogException(code, message)` | 日志操作失败（稳定错误码） |
| `provideSessionLogRecorder(ctx, {recorder})` / `ctx.sessionLogRecorder` | 提供 `'sessionLogRecorder'`（缺 `'sessionLog'` 时自动补） |
| `SessionLogRecorder`：`attach(session)` / `detach()` / `record(type, {data})` / `sessionId` / `lastEventId` | 镜像业务事件 + 追加派生事件，串成因果链 |
| `SessionLogLlmProvider(inner, {recorder})` / `instrumentSessionLogTools(tools, recorder)` | 记录 `llm/request` / `llm/response` / `tool/call`（不改请求） |
| `checkModelVisibleInvariant(events)` / `assertModelVisibleInvariant(events)` / `sameJson(left, right)` | 「模型可见即已记录」不变式的检查 / 断言 / 递归 JSON 比较 |

### `SkillRegistry`（`skill-catalog`，`conatus_skill` 包）

| 成员 | 说明 |
|------|------|
| `provideSkillRegistry(ctx, {providers, inlineSkills, registry})` | 提供 `'skillRegistry'` 并完成首次收集；`inlineSkills` 直接把提示词当技能（不落盘） |
| `provideSkillFilesystem(ctx, {roots, watch, debounce})` | 注册目录发现 provider（缺省 `defaultSkillRoots()`）并为已存在的根起监听 |
| `provideSkillCatalog(ctx, {order, descriptionMaxLength})` | 把目录挂成 `skills` 段（空目录不注册） |
| `provideSkillTool(ctx, {tools, name})` | 注册 `skill` 工具（参数 `name`，结果是一段 `<skill_content>`）；可换目标工具表与工具名 |
| `SkillRegistry`：`available` / `modelInvocable` / `load(name)` / `register(SkillRegistration)` / `registerProvider(SkillProvider)` / `refresh()` / `invalidate()` / `onChange(fn)` | 同步快照 / 可调用技能 / 加载正文 / 运行时技能 / 来源注册 / 立即收集 / 标脏 / 变更监听 |
| `SkillRegistry({parent, visible})` | 子作用域：父级快照经 `visible` 过滤后并入 `available`，同名由子级赢下；父级变化级联 |
| `SkillCatalogSection.attach({name})` / `SkillLoadTool({registry, name})` | 段名与工具名可换，多个作用域能共用一份 system prompt 与一张工具表 |
| `SkillProvider`：`name` / `list()` / `load(summary)` | 来源契约（单 provider 失败只降级它自己） |
| `SkillRoot(path, source, rank)` / `defaultSkillRoots({projectRoot, includeUserRoots})` / `findProjectRoot()` | 发现根与项目根定位（最近含 `.git` 的祖先） |
| `SkillCatalogSection` / `renderSkillCatalog(...)` / `renderSkillContent(...)` | 目录段控制器与目录 / `<skill_content>` 渲染 |
| `parseSkillDocument(text) → SkillDocument` / `SkillFrontmatter` | frontmatter 解析（`error` 非空即丢弃该条目） |
| `SkillRootWatcher({roots, onInvalidate, debounce})` | 目录监听：变更合并成一次失效 |

### `SystemPrompt`（`system-prompt`）

| 成员 | 说明 |
|------|------|
| `provideSystemPrompt(ctx, {prompt})` | 提供 `'systemPrompt'` |
| `section(PromptSection) → Disposer` / `context(PromptContext) → Disposer` | 注册段 / 动态上下文（重名抛错） |
| `assemble({variables}) → PromptAssembly` | 按 `order` + 名字排序求值 |
| `render(assembly, {separator}) → String` | 拼接段并插值 `{{variable}}` |
| `renderContexts(assembly, {separator}) → String` | 拼接动态上下文并插值；空文本不贡献内容 |

### `provideTimePrompt`（`time-context`）

| 成员 | 说明 |
|------|------|
| `provideTimePrompt(ctx, {prompt, clock, zoneName}) → Disposer` | 注册日粒度日期锚点；`prompt` 缺省取 `'systemPrompt'`，`clock` 缺省 `DateTime.now` |
| `kTimeContextName` | 锚点在 system prompt 里的名字（`time`） |
| `formatClockOffset(Duration) → String` | 时区偏移格式化（`+08:00` / `-05:30`） |

### `CompactionEngine` / `Compactor`（`compaction`，`conatus_compaction` 包）

| 成员 | 说明 |
|------|------|
| `provideCompaction(ctx, {engine})` | 提供 `'compaction'` |
| `CompactionEngine` | 压缩能力缝：`keepRecent` / `summaryOf(id)` / `forget(id)` / `compactIfNeeded(session, summarize, {keepRecent})` |
| `Compactor({keepRecent})` | 默认实现：折叠较早事件，不足预算或无平衡切点返回 `null` |
| `CompactionResult` | `compactionId` / `startSeq` / `summarySeq` / `endSeq` / `summary` / `shadowedSeqs` / `kept`（`compacted` = 折叠条数） |
| `CompactionSummary(text, {provider, model})` / `Summarizer` | 汇总产出与汇总器签名 |
| `balancedCutAtOrBefore(session, cut)` | 把预算切点吸附到不劈开工具配对的最近位置 |
| `toolPairingBalancedBefore/After(session, seq)` | 查询某个切点是否平衡（seq 不存在或结果先于调用时抛错） |
| `kCompactionStartEvent` / `kCompactionSummaryEvent` / `kCompactionEndEvent` | 压缩记录事件名 |
| `checkCompactionInvariant(events)` / `assertCompactionInvariant(events)` | 校验三个事件成对、同身份、折叠区间是日志开头的一段 |

### `LayeredCompactor` / `ContentClassifier`（`layered-compaction` / `content-classifier`）

| 成员 | 说明 |
|------|------|
| `provideLayeredCompaction(ctx, {compaction, classifier, telemetry, keepRecent})` | 提供 `'compaction'`（与 `provideCompaction` 二选一） |
| `LayeredCompactor({keepRecent, classifier, telemetry})` | `Compactor` 的 drop-in 替身，按类别分别处理较早事件 |
| `provideContentClassifier(ctx, {classifier})` / `ctx.contentClassifier` | 提供 `'contentClassifier'`（缺省 `RuleBasedContentClassifier`） |
| `ContentClassifier`：`classify(message)` / `strategyFor(category)` / `recentWindow` | 内容分类能力缝 |
| `MessageCategory`（systemPrompt / toolDefinition / skillList / toolResult / userPreference / userTask / earlyConversation / recentConversation） | 内容类别 |
| `CompressionStrategy`（none / keep / summarize / evict） | 类别对应的压缩策略 |
| `RuleBasedContentClassifier({recentWindow})` | 角色 + 关键词 + 位置窗口的默认分类器 |
| `context.compacted` 遥测 | `tokensBefore` / `tokensAfter` / `compacted` / `kept` / `toolResults` / `preferences` |

### `CachePlan` / `ContextCache`（`context-cache`）

| 成员 | 说明 |
|------|------|
| `provideContextCache(ctx, {cache, telemetry})` / `ctx.contextCache` | 提供 `'contextCache'` |
| `CachePlan.of(messages)` | 连续可缓存前缀：`cacheKey` / `cacheableMessages` / `cacheableChars` / `empty` |
| `CachingLlmProvider(inner, {cache})` | 透传请求，按回包 `usage` 记命中（不加任何请求字段） |
| `ContextCache`：`planFor(messages)` / `recordHit({plan, usage})` / `hits` / `misses` | 前缀计划 / 命中记账 / `context.cache` 遥测 |
| `LlmMessage.cacheable` | 本地前缀标记，不写入请求体 |

### `MemoryStore`（`memory`）

| 成员 | 说明 |
|------|------|
| `provideMemory(ctx, {memory, backend})` | 提供 `'memory'` |
| `remember(text, {tags}) → Future<MemoryEntry>` / `recall(query, {limit}) → List<MemoryEntry>` | 写入 / 关键词召回 |
| `forget(id) → Future<bool>` / `forgetByText(text)` / `forgetMatching(query) → Future<int>` | 按 id / 正文精确 / 正文包含 遗忘（返回删除条数） |
| `clear()` / `load()` | 清空 / 从后端加载 |
| `entries` / `length` / `onChange(fn)` | 只读视图 / 条数 / 变更监听 |
| `RememberTool` / `ForgetTool` / `provideRememberTool` / `provideForgetTool` / `provideMemoryTools` | 给模型用的 `remember` / `forget` 工具 |
| `MemoryBackend` / `InMemoryMemoryBackend` / `JsonMemoryBackend({file})` | 存储端口与两种本地实现 |

### `Database`（`database`）

| 成员 | 说明 |
|------|------|
| `provideDatabase(ctx, {database, defaultBackend})` | 提供 `'database'` |
| `provideDatabaseJson(ctx, {database, name, dir})` | 注册 `JsonDatabaseBackend` 为具名后端 |
| `register(name, backend) → Disposer` / `backend(name)` / `backendNames` | 后端注册与解析 |
| `open(unit, {backend}) → Future<DatabaseUnit>` / `get(unit)` / `units` | 打开 / 查找单元 |
| `close(unit)` / `closeAll()` | 关闭单元 |
| `DatabaseUnit.put(key, value)` / `delete(key)` / `get(key)` / `has(key)` / `keys` / `entries()` | 单元读写 |
| `DatabaseUnit.onChange(fn) → Disposer` | 落盘后的变更广播（`DatabaseChange`） |
| `DatabaseBackend` / `JsonDatabaseBackend({dir})` | 后端端口 / 本地 JSON 实现 |

### `AgentLoop`（`agent`）

| 成员 | 说明 |
|------|------|
| `provideAgentLoop(ctx, {agent, session, maxSteps})` / `ctx.agentLoop` | 提供 `'agentLoop'` / 快捷访问 |
| `AgentLoop({llm, tools, session, systemPrompt, compactor, memory, maxSteps, memoryLimit})` | 依赖可注入 |
| `run(userInput) → Future<AgentTurn>` | 跑一轮（多步工具循环直至收口） |
| `AgentTurn.reply` / `AgentTurn.steps` / `AgentTurn.messages` | 结果 / 工具步骤 / 消息序列 |
| `deriveAgentMessages(events)` | 会话事件 → 模型消息序列 |
| `summarizeEvents(llm, events, previous)` | 压缩用的默认汇总器（返回 `CompactionSummary`） |

### 工具结果驱逐 / 规划

| 成员 | 说明 |
|------|------|
| `provideToolResultEviction(ctx, {eviction, fs, tools, threshold, previewChars, dir})` | 安装驱逐中间件，返回 `ToolResultEviction` |
| `ToolResultEviction({fs, threshold, previewChars, dir})` / `evict(content)` / `clear()` / `spilledPaths` | 驱逐器 |
| `PlanTool({session})` / `providePlanTool(ctx, {session, tools})` | `plan_write` 工具 |
| `Plan({goal, steps})` / `PlanStep` / `readPlan(session)` / `writePlan(session, plan)` / `planSection(session)` | 计划读写 |
| `runPlanningPhase({llm, tools, session, messages, systemText})` | 规划轮 |
| `AgentLoop(..., planning: true)` / `provideAgentLoop(ctx, {..., planning})` | 启用规划 |

### 子 Agent / 自省

| 成员 | 说明 |
|------|------|
| `provideSpawnAgent(ctx, {host, llm, tools, defaultTools, maxRounds, subAgentPrompt})` | 注册 `spawn_agent` |
| `SpawnAgentTool`（`spawn_agent`：`task` / `tools` / `max_rounds`） | 隔离子 Agent 委托 |
| `SubAgentResult({status, output, rounds, toolCalls})` | 委托结局 |
| `provideReflection(ctx, {reflector, llm, strategy, options, maxRetries})` | 提供 `'reflection'` |
| `Reflector({llm, strategy, options, maxRetries})` / `shouldReflect` / `reflect` | 反思器 |
| `ReflectionStrategy` / `ReflectionDecision` / `ReflectionAction` / `reflectAndRetry` | 策略 / 决策 / 应用 |

### 可观测性 / 评估

| 成员 | 说明 |
|------|------|
| `provideTelemetry(ctx, {telemetry})` / `ctx.telemetry` | 提供 `'telemetry'` |
| `Telemetry` / `InMemoryTelemetry` / `ConsoleTelemetry` | 端口 / 内存 / 控制台导出器 |
| `TelemetryEvent(name, {data, time})` | 事件 |
| `instrumentTools(ctx, {telemetry, tools})` | 工具埋点（`tool.called` / `tool.failed`） |
| `TelemetryLlmProvider(inner, {telemetry})` | 模型埋点（`llm.request` / `llm.failed`） |
| `EvalCase({id, input, expectedTools, expectedOutput, maxRounds})` | 评估用例 |
| `Evaluator({run, judge})` / `runAll(cases)` / `evaluate(case)` | 评估器 |
| `EvalResult` / `EvalReport` / `EvalDiff` / `defaultEvalJudge` | 结果 / 报告 / 差异 / 默认判分 |

### `approval`

| 成员 | 说明 |
|------|------|
| `provideApproval(ctx, {approval, tools, threshold, timeout, instrument})` / `ctx.approval` | 提供 `'approval'` + 安装拦截（`instrument: false` 时只提供服务，供阈值动态决定的装配方自行挂载） |
| `Approval` / `ApprovalRequest({id, toolName, arguments, description, pathArgs})` | 端口 / 请求 |
| `AutoApproval(bool)` / `RuleBasedApproval({allow})` / `AskUserApproval({askUser, yesWords, timeout})` | 内置 Provider |
| `preapproved(request)` | 预授权钩子：`true` 则中间件直接放行，不询问、不埋点 |
| `requestPlan(plan)` | 一次性审批计划 |
| `instrumentApproval(ctx, {approval, tools, telemetry, threshold, timeout})` | 挂审批中间件（声明 `Tool.pathParams` 的工具即使低风险也进入审批） |
| `pathArguments(tool, call)` | 取工具声明的路径参数取值（支持嵌套键） |

### 技能 / 恢复

| 成员 | 说明 |
|------|------|
| `provideSkillLibrary(ctx, {library, llm, tools, memory, approval, threshold, namer})` / `ctx.skills` | 提供 `'skill'` |
| `SkillLibrary`：`record` / `recordTools` / `maybeExtract` / `restore` / `skills` | 轨迹 → 提取 → 恢复 |
| `SkillStep` / `SkillTool` / `SkillMeta` / `SkillNamer` / `deriveSkillParams` / `resolveSkillArg` | 技能类型与执行 |
| `llmSkillNamer` / `deterministicSkillNamer` / `parseSkillMeta` / `skillNameFrom` / `toolNamesFromEvents` | 命名器与轨迹提取 |
| `provideRecovery(ctx, {recovery, store, database})` / `ctx.recovery` | 提供 `'recovery'` |
| `RecoveryService`：`snapshot(session)` / `restore(id)` / `load(id)` / `list()` / `delete(id)` | 快照与恢复 |
| `SessionSnapshot` / `SnapshotStore` / `MemorySnapshotStore` / `DatabaseSnapshotStore` / `RecoveryException` | 快照类型与存储 |

### 实验性包

以下包均为 `publish_to: none`，不进伞包，需显式依赖（详见各包 README）。

| 成员 | 说明 |
|------|------|
| `provideAlerting(ctx, {alerting, rules, notifier, telemetry})` / `ctx.alerting` | 提供 `'alerting'`：订阅 `telemetry` 事件流，按规则判定并通知（`conatus_alerting`） |
| `Alert` / `AlertRule` / `AlertContext` / `RuleParser` / `defaultAlertRules` | 告警模型 / 声明式规则 / 窗口统计与冷却 / JSON 规则解析 / 默认 8 条规则 |
| `AlertNotifier`：`ConsoleNotifier` / `WebhookNotifier` / `AskUserNotifier` / `CompositeNotifier` / `QuietHoursNotifier` | 通知渠道：控制台 / Slack 兼容 Webhook / TTS 播报 / 复合 / 静默期（critical 例外） |
| `provideBrowserUse(ctx, {provider, config, session, tools, taskCenter, approval, telemetry})` | 提供 `'browserUse'`：注册浏览器操作工具，`provider` 缺省 `PlaywrightMcpProvider`（`conatus_browser_use`） |
| `initializeBrowserFor(ctx, session)` / `BrowserUseProvider` / `SessionBrowser` / `BrowserConfig` / `browserToolRisk` | fork 后初始化新浏览器 / Provider 端口 / 绑定 Session 的浏览器 / 启动配置 / 工具风险分级 |
| `PlaywrightMcpProvider` / `ChromeDevToolsMcpProvider` / `StagehandProvider` | 浏览器 Provider（前两个走 MCP，Stagehand 为未接入骨架） |
| `provideComputerUse(ctx, {provider, tools, taskCenter, approval, telemetry})` / `registerDesktopTools(ctx, desktop, {sessionId, sessionLog})` | 提供 `'computerUse'`：注册桌面工具 / 把操作记录到触发它的 Session 日志（`conatus_computer_use`） |
| `ComputerUseProvider` / `CuaDriverMcpProvider` / `CuaDriverNativeProvider` / `DesktopSession` / `Screenshot` / `ScreenRegion` | 桌面 Provider 与值类型（Native 为未接入骨架） |
| `imageSupportFor(provider, model)` / `AttachmentStore` / `InMemoryAttachmentStore` | 图像路由（持久化截图 / MCP 图像诊断）与截图存储 |
| `provideIntentRouter(ctx, {router, embedder, intents, vectorThreshold, telemetry, session, fastPath})` / `ctx.intentRouter` / `IntentRouterAdapter` | 提供 `'intentRouter'`，并（缺省）接到 Agent Loop 的 `'router'` 快路径（`conatus_intent`） |
| `Intent` / `RoutedAction`：`DirectAction` / `ToolAction` / `DelegateAction` / `RouteResult` / `RouteSource` / `RouteContext` / `IntentEvent` / `IntentException` | 意图与三种动作、路由结果、上下文、变更事件与错误 |
| `RegexMatcher` / `VectorMatcher` / `orderByPriority` | 正则匹配 / 向量匹配 / priority 降序稳定排序 |
| `EmbeddingProvider` / `LocalEmbeddingProvider` / `LlmEmbeddingProvider` / `EmbeddingLlm` / `cosineSimilarity` | 嵌入 seam 与本地（字符 n-gram）/ 模型端点两种实现、余弦相似度 |
| `IntentLoader({required router, handlers})` / `IntentHandler` | 从 JSON 加载意图（`tool` / `builtin` / `delegate` / `respond` 四种动作） |
| `SkillIntentBridge` / `ToolIntentGenerator` / `IntentLearner` / `IntentCandidate` / `IntentSpec` | Skill 沉淀与工具描述生成候选意图、未命中学习器（均只产候选，不自动注册） |
| `provideAgentTeam(ctx, {leadId, llm, tools, defaultTools, maxMembers, taskTracker, session, approval, telemetry})` / `ctx.team` / `provideTeamTools(ctx, {team, tools})` | 提供 `'team'` 与 10 个团队工具（`conatus_team`） |
| `AgentTeam` / `TeamBoard` / `MemberRuntime` / `TeamRole` / `TeamPattern` / `TeamHooks` | 团队运行时 / 任务板（DAG + CAS）/ 成员运行时 / 角色 / 协作模式 / 运行时 seam |
| `provideWorkflow(ctx, {engine, store, team, tools, taskCenter, session, approval, telemetry, maxDepth})` / `ctx.workflow` / `provideWorkflowTools(ctx)` | 提供 `'workflow'` 与 8 个流程工具（`conatus_workflow`） |
| `WorkflowEngine` / `WorkflowDefinition` / `WorkflowNode` / `WorkflowRun` / `RunStatus` / `RunNodeStatus` | 引擎 / 声明式流程定义 / 三种节点（tool / agent / sub-workflow）/ 运行记录与状态机 |
| `TraceBuilder(sessionLog:)` / `Span` / `SpanStatus` | 从 Session Log 派生 trace 与 span 语义（`conatus_observability`） |

---

## 设计说明

### 为什么用 `inject` 而不是直接查找服务？

传统依赖注入中，组件调用 `get<Logger>('logger')` 时若服务不存在，要么返回 `null` 由调用方处理，要么抛异常。这会把“服务还没准备好”的时序问题推给每个组件。

`inject` 把“等待依赖”这件事从组件逻辑中剥离：

```dart
// 传统做法：每次都处理 null
final logger = ctx.get<Logger>('logger');
if (logger == null) return;
logger.info('...');

// inject：声明式，运行时保证激活时服务一定可用
ctx.inject(['logger'], (child) {
  child.require<Logger>('logger').info('...');
});
```

### 为什么激活时创建**新**子上下文？

因为组件的生命周期与依赖状态耦合：依赖消失时必须能精确回滚该组件产生的所有副作用。用一个独立的子上下文承载这些效应，`dispose()` 即可一次性撤销，无需组件自己追踪。

同时这也保证**纯净性**：每次激活都是全新的、没有历史残留的状态。

### 为什么服务对父级不可见？

这是有意的隔离。若子上下文可以向上“污染”父级服务表，两个插件同名服务会互相覆盖，且父级无法可靠地卸载它们。沿父链向下查找是更符合直觉的层级作用域语义（类似词法作用域）。

若确实需要跨子树上通信，可以用事件总线或“提升”模式：

```dart
// 在父级提供一个可变的槽位，子级写入
final slot = <String, Object?>{};
ctx.provide('shared-slot', slot);
```

---

## 与相关方案的对比

| 方案 | 时间可组合性 | 空间可组合性 | 依赖 Dart |
|------|:---:|:---:|:---:|
| `package:provider` | ❌ 需手动管理 | ⚠️ 静态声明 | ✅ |
| `package:get_it` | ⚠️ 手动 reset | ⚠️ 静态注册 | ✅ |
| `package:riverpod` | ⚠️ 部分 | ✅ 反应式 | ✅ |
| **conatus** | ✅ LIFO 回滚 | ✅ 反应式共效应 | ✅ |

核心差异在于 `conatus` 把**组件的加载/卸载**与**依赖的满足/失效**统一到同一套机制：组件的激活是一个可逆的上下文变换，依赖变化直接驱动这个变换的执行与回滚。

---

## 贡献

欢迎提交 Issue 与 Pull Request。

开发流程（`dart pub get` 与 `dart analyze` 在仓库根目录一次完成）：

```bash
dart pub get
dart analyze
dart format .

# 测试按包执行（pub 暂不支持一次跑完整工作区）
dart test                                   # 伞包自身的集成测试
for d in packages/*/; do (cd "$d" && dart test); done
```

提交前请确保 CI 通过。

## 发版

所有包共用同一个版本号，包间依赖也用同一约束（`^0.15.0` 在 0.x 下等价于
`>=0.15.0 <0.16.0`，所以每升一次版本，22 个 `pubspec.yaml`（21 个模块包 + 根伞包）
必须一起改）：

```bash
bash tool/version.sh            # 检查：23 个包版本号一致，且包间约束都指向它
bash tool/version.sh 0.16.0     # 统一升版：改 version 行 + 同步所有包间约束
```

漏改任何一处，`dart pub get` 会在 workspace 内解析阶段直接失败（不会悄悄发出去）。

发布按依赖顺序进行（依赖在前）；15 个可发布包如下，7 个实验性包
（`conatus_alerting` / `conatus_browser_use` / `conatus_computer_use` /
`conatus_intent` / `conatus_observability` / `conatus_team` / `conatus_workflow`）
是 `publish_to: none`，不在发布之列：

```bash
for p in conatus_core conatus_foundation conatus_compaction conatus_cron \
         conatus_credentials conatus_llm conatus_mcp conatus_schedule \
         conatus_search conatus_skill conatus_asr conatus_tts conatus_agent \
         conatus_tasks conatus_tui; do
  dart pub publish -C "packages/$p"
done
dart pub publish            # 最后发布伞包 conatus
```

---

## 致谢

核心概念来自论文 *A Programming Paradigm for Spatiotemporal Composability*
（arXiv:2608.25512），由北京大学与 DeepSeek 团队完成，
其参考实现 [Cordis](https://github.com/cordiverse/cordis) 使用 TypeScript 编写。

本项目是其在 Dart 生态中的独立实现。

---

## 许可证

[MIT](LICENSE)

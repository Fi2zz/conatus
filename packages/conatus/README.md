# conatus

> 时空可组合性（Spatiotemporal Composability）编程范式的 Dart 实现。
>
> 基于论文 *A Programming Paradigm for Spatiotemporal Composability*
> （arXiv:2608.25512）的核心机制。

本包是 monorepo 的**伞包（umbrella）**：自身不含实现，统一再导出
`conatus_core` / `conatus_credentials` / `conatus_foundation` / `conatus_llm` /
`conatus_mcp` / `conatus_search` / `conatus_asr` / `conatus_tts` / `conatus_agent`，
因此 `import 'package:conatus/conatus.dart';` 仍是完整公开 API。
也可以按需只引入某个模块包，以获得更小的依赖面。

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
- 📦 **零运行时依赖**：核心仅用 Dart 核心库（`llm` / `credentials` / `mcp` / `search` 插件依赖 `http`）
- 🧰 **基础设施插件**：`timer`（定时器即效应）、`logger-console`（分级日志）、`loader`（注册表 + 配置树）、`tools`（`Tool` 基类 + `ParamSpec` + 注册表/执行管线/分组/分级）、`shell` / `fs`（能力缝 + 本地实现）、`search`（搜索能力缝 + web 工具）、`asr`（语音识别能力缝 + `transcribe_audio`）、`tts`（语音合成能力缝 + 音频输出接口）
- 🔐 **凭据管理**：`credentials`（统一凭据契约 + 五种来源：环境变量 / 内存 / 文件 / Vault KV v2 / AWS Secrets Manager）——`get` / `require` / `validate` 同步读内存快照，远端来源用 `refresh()` 拉取并可定时轮换，对外只出现 `masked`
- 🗂️ **会话与上下文**：`session`（事件日志 + 仓库 + JSONL 持久化）、`session-log`（多会话只追加日志：fork / replay / 轨迹重建，附「模型可见即已记录」不变式）、`system-prompt`（prompt 段装配）、`compaction`（滚动摘要）、`memory`（长记忆库 + 显式记住/遗忘能力与工具）
- 🗄️ **持久化**：`database`（KV 存储 hub + 可插拔后端 + JSON 本地实现）
- 🤖 **Agent Loop**：`agent`（会话事件 + prompt 装配 + 压缩 + 记忆 + 工具闭环）、`tool-result-eviction`（大结果落盘）、`plan`（结构化计划）、`sub-agent`（`spawn_agent` 隔离委托）、`reflection`（工具后自省重试）
- 🔌 **MCP 生态**：`mcp`（MCP 客户端：stdio / HTTP / SSE 传输 + 握手与工具发现），外部 server 的工具以 `server__tool` 接入同一张工具表，风险缺省 `medium` 走审批
- 🗜️ **分层压缩与缓存度量**：`content-classifier`（内容分类器能力缝）、`layered-compaction`（按类别分层折叠：工具结果压成指针、用户偏好留原文）、`context-cache`（可缓存前缀指纹 + 命中遥测）
- 🔭 **产品化**：`telemetry`（事件导出 + 埋点）、`evaluation`（用例评估 + 基线对比）、`approval`（高危工具审批）、`skill`（技能沉淀）、`recovery`（会话快照恢复）
- ✅ **完整测试覆盖**：628 个单元测试

---

## 安装

本包是 monorepo 的伞包，依赖同一仓库内的 `conatus_*` 兄弟包（目前尚未发布到
pub.dev）。因此从 git 引入时，需要把兄弟包一并指向该仓库，详见仓库根目录
[「作为依赖使用」](../../README.md#作为依赖使用)：

```yaml
dependencies:
  conatus:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: master
      path: packages/conatus

dependency_overrides:
  conatus_agent:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_agent}
  conatus_asr:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_asr}
  conatus_core:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_core}
  conatus_credentials:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_credentials}
  conatus_foundation:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_foundation}
  conatus_llm:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_llm}
  conatus_mcp:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_mcp}
  conatus_search:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_search}
  conatus_tts:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master, path: packages/conatus_tts}
```

各包发布到 pub.dev 后即可简化为 `conatus: ^0.15.0`。

或从源码使用：

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
final llm = DoubaoProvider(apiStyle: LlmApiStyle.responses);

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
final llm = DoubaoProvider(credentials: credentials); // 取 'ARK_API_KEY'

print(credentials.require('ARK_API_KEY').masked);     // sk-1...cdef
credentials.validate(<String>['ARK_API_KEY']);        // 缺失抛 CredentialsException('missing')
```

- 只读来源（env / file / vault / aws）调 `update` 抛 `CredentialsException('read-only')`，
  只有 `InMemoryCredentials` 可写；`Credential.expired` 为真时 `get` 返回 `null`；
- 各来源共用 `parseCredentialMap` 解析 `"KEY": "值"` 与
  `"KEY": {"value": ..., "expiresAt": ...}` 两种形态；
- 对外只暴露 `Credential.masked`（前 4 + `...` + 后 4，长度 ≤ 8 时整串星号），
  `toString()` 也只含脱敏值；结构化日志交给 `conatus_core` 的 `redactSecrets`；
- `DoubaoProvider` / `DeepSeekProvider` 可传 `credentials` 与 `credentialKey`
  （缺省 `ARK_API_KEY` / `DEEPSEEK_API_KEY`），解析顺序是「显式 `apiKey` → 凭据服务 →
  环境变量」，并订阅 `changes` 做运行时轮换——Header 每次请求重算，不重建 HTTP client；
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
- `provideFsTools(app)` 注册 `read_file`（`ReadFileTool`）把 fs 暴露给模型；`provideToolResultEviction` 落盘的大结果即由它读回。

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

### `system-prompt` — prompt 段装配

服务键 `'systemPrompt'`。各插件注册 `PromptSection` / `PromptContext`（`order` 升序、
同序按名字），`assemble()` 每次求值 provider，`render()` 拼接并插值 `{{variable}}`。

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

### `compaction` — 会话滚动摘要

服务键 `'compaction'`。事件数超过 `keepRecent` 时，把较早的事件连同上一版摘要交给
注入的 `Summarizer`（通常是 `llm`），产出新摘要并按会话缓存；日志本身不被改写。

```dart
final compaction = provideCompaction(app, compaction: Compactor(keepRecent: 20));
final result = await compaction.compact(session, (events, previous) async {
  return await summarizeWithLlm(events, previous);
});
```

### `layered-compaction` — 分层压缩与内容分类器

服务键同为 `'compaction'`（与 `provideCompaction` **二选一**，重复提供会抛错）。
`LayeredCompactor` 是 `Compactor` 的 drop-in 替身：接口与契约完全一致，区别在
`compact` 按内容类别分别处理，而不是一律压成一段摘要。

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
    description: '返回当前时间',
    handler: (ctx) async => ToolResult.success(DateTime.now().toIso8601String())));
provideLlm(app);
final session = provideSessions(app).create(id: 'cli');
provideSystemPrompt(app).section(
    PromptSection(name: 'persona', text: () => '你是助手，需要实时信息时调用工具。'));
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
| `DoubaoProvider({apiStyle, ...})` / `DeepSeekProvider({apiStyle, ...})` | 内置 provider，`apiStyle` 默认 `chat` |
| `FallbackLlm(providers)` / `FallbackLlm.withDefaults()` | 顺序回退链（豆包 → DeepSeek） |
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
| `Tool({name, description, riskLevel, group, params, call})` | 工具基类（`toSchema()` 白名单投影） |
| `ParamSpec.string/.integer/.number/.boolean/.enumeration/.array/.object` + `parameterSchema` | 参数声明与 schema 生成 |
| `ToolContext`（`str` / `integer` / `number` / `boolean` / `array` / `object` / `require<T>`） | 类型安全取参 |
| `register(Tool) → Disposer` | 注册工具（同名重复抛 `StateError`） |
| `call(ToolCall, {timeout}) → Future<ToolResult>` | 校验 → 守卫 → 中间件 → 执行体（收敛失败） |
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

### `SystemPrompt`（`system-prompt`）

| 成员 | 说明 |
|------|------|
| `provideSystemPrompt(ctx, {prompt})` | 提供 `'systemPrompt'` |
| `section(PromptSection) → Disposer` / `context(PromptContext) → Disposer` | 注册段 / 动态上下文（重名抛错） |
| `assemble({variables}) → PromptAssembly` | 按 `order` + 名字排序求值 |
| `render(assembly, {separator}) → String` | 拼接并插值 `{{variable}}` |

### `Compactor`（`compaction`）

| 成员 | 说明 |
|------|------|
| `provideCompaction(ctx, {compaction})` | 提供 `'compaction'` |
| `Compactor({keepRecent})` | 保留最近事件数 |
| `compact(session, summarize, {keepRecent}) → Future<CompactionResult?>` | 折叠较早事件，不足预算返回 `null` |
| `summaryOf(id)` / `forget(id)` | 查询 / 丢弃滚动摘要 |

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
| `summarizeEvents(llm, events, previous)` | 压缩用的默认汇总器 |

### 工具结果驱逐 / 规划

| 成员 | 说明 |
|------|------|
| `provideToolResultEviction(ctx, {eviction, fs, tools, threshold, previewChars, dir})` | 安装驱逐中间件，返回 `ToolResultEviction` |
| `ToolResultEviction({fs, threshold, previewChars, dir})` / `evict(content)` / `clear()` / `spilledPaths` | 驱逐器 |
| `ReadFileTool({fs, maxChars})` / `provideFsTools(ctx, {fs, tools})` | `read_file` 工具 |
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
| `provideApproval(ctx, {approval, tools, threshold, timeout})` / `ctx.approval` | 提供 `'approval'` + 安装拦截 |
| `Approval` / `ApprovalRequest({id, toolName, arguments, description})` | 端口 / 请求 |
| `AutoApproval(bool)` / `RuleBasedApproval({allow})` / `AskUserApproval({askUser, yesWords, timeout})` | 内置 Provider |
| `requestPlan(plan)` | 一次性审批计划 |
| `instrumentApproval(ctx, {approval, tools, telemetry, threshold, timeout})` | 挂审批中间件 |

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

开发流程：

```bash
dart pub get
dart analyze
dart test
dart format .
```

提交前请确保 CI 通过。

---

## 致谢

核心概念来自论文 *A Programming Paradigm for Spatiotemporal Composability*
（arXiv:2608.25512），由北京大学与 DeepSeek 团队完成，
其参考实现 [Cordis](https://github.com/cordiverse/cordis) 使用 TypeScript 编写。

本项目是其在 Dart 生态中的独立实现。

---

## 许可证

[MIT](LICENSE)

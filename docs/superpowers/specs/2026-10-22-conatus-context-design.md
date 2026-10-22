# conatus_context 设计：进入模型前的可逆结构化压缩

- 日期：2026-10-22
- 状态：待评审
- 相关：`conatus_compaction`（跨轮折叠）、`conatus_agent` 的 `layered-compaction` / `tool-result-eviction`、
  `conatus_foundation` 的 `tools` / `fs`
- 参考实现（仅思路）：[headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom)，Apache-2.0

## 1. 背景

conatus 已有两层上下文治理：

- **跨轮折叠**：`conatus_compaction` 把较早事件折叠成滚动摘要；
  `layered_compaction` 进一步把早期工具结果压成「工具名 + 首行 + 字符数 + 日志指针」。
- **超限落盘**：`tool-result-eviction` 在工具结果超过阈值时写临时文件，正文换成首尾预览 +
  路径，模型需要时用 `read_file` 取回。

缺的是两者之间的**单条内容内部压缩**：一条 5 万字符的 JSON、日志或 grep 结果，在进入
模型前就应该被结构化地压到代表项，而不是等到跨轮再折叠、或超限后整段丢弃。参考实现
headroom 的实测收益集中在这些结构上（JSON 数组约 52–97%、构建日志 85–95%、搜索结果
80–95%、diff 60–80%），而代码与散文基本不压——这正好划定了本包的范围。

本包同时补上**可逆性**：压缩后的内容带本地 hash 标记，模型可以按标记取回原文，避免
「压得狠 → 丢事实」的二选一。

## 2. 目标与非目标

### 目标

1. 在工具结果写入会话日志之前，按内容类型做确定性、可解释的结构化压缩。
2. 压缩可逆：原文落本地 CCR 存储，模型通过工具按需取回。
3. 与现有不变式兼容：模型看到的压缩版就是日志里记录的版本，`checkModelVisibleInvariant` 不回归。
4. 零新增运行时依赖、零网络、零 ML 模型，纯 Dart。
5. 提供非 Agent 场景的纯函数入口 `compressMessages`。

### 非目标

- 不做 provider 代理、base URL 改写、跨进程 HTTP 服务。
- 不做 ML 文本压缩（headroom 的 Kompress / ONNX）、Magika 内容识别。
- 不做代码 AST 改写（tree-sitter）；源码默认透传。
- 不重写跨轮压缩、不删消息、不改消息顺序、不碰工具调用配对。
- 不做输出侧 token 治理（verbosity / effort routing）。
- 不做跨 Agent 共享记忆。

## 3. 定位与协同

```
工具执行结果
   │
   ├─▶ conatus_context 中间件           ← 本包：单条内容结构化压缩 + CCR 标记
   │      （压缩后仍超阈值）
   ├─▶ tool-result-eviction            ← 落盘 + 预览
   │
   └─▶ tool/result 事件（日志记录的就是模型看到的版本）
          │
          ├─ 近期窗口：原样进入模型，可用 context_retrieve 取回
          └─ 更早窗口：layered_compaction 折叠成指针
```

中间件注册顺序按「先注册者在最外层」包裹：`provideContextCompression` 应在
`provideToolResultEviction` **之前**注册，使压缩先执行、压完仍超限的结果再交给落盘。
包内不强制，README 给出建议顺序与差异说明。

## 4. 架构

```
ContentDetector ──▶ ContextRouter ──▶ ContentCompressor（按 kind 选一个）
                         │                    │
                         │                    └─ 纯函数：输入文本 → 压缩草稿
                         ├─ 安全门（最小尺寸 / 保护名单 / 收益比 / 幂等）
                         ├─ CcrStore.put(原文) → id
                         ├─ 注入 <<ctx:ID ...>> 标记
                         ├─ CompressionStats 累计
                         └─ fail-open：异常 → 原文
```

- **检测器**：纯正则 + 结构嗅探，无 I/O，确定性。
- **压缩器**：只依赖输入文本与预算，不碰存储、不碰统计，便于单测与复用。
- **Router**：唯一持有存储、标记、统计与失败兜底的组件。
- **中间件**：把 Router 接到 `ToolRegistry.use`，只改写成功/失败结果正文，不改变结果状态。

### 包结构

```
packages/conatus_context/
  lib/conatus_context.dart
  lib/src/
    context_compression_config.dart
    content_kind.dart
    content_detector.dart
    compression_result.dart
    compression_budget.dart
    content_compressor.dart
    compressors/json_array_compressor.dart
    compressors/build_log_compressor.dart
    compressors/search_results_compressor.dart
    compressors/diff_compressor.dart
    compressors/tabular_compressor.dart
    compressors/text_compressor.dart
    context_router.dart
    ccr_store.dart
    ccr_memory_store.dart
    ccr_file_store.dart
    ccr_marker.dart
    compression_stats.dart
    context_retrieval_tool.dart
    context_stats_tool.dart
    provide_context_compression.dart
    compress_messages.dart
```

依赖：`conatus_core`、`conatus_foundation`、`conatus_llm`。不依赖 `conatus_agent`。

## 5. 公共 API

### 5.1 配置

```dart
class ContextCompressionConfig {
  const ContextCompressionConfig({
    this.enabled = true,
    this.minChars = 4000,
    this.minSavingRatio = 0.15,
    this.protectedTools = const <String>{},
    this.disabledKinds = const <ContentKind>{},
    this.ccrEnabled = true,
    this.ccrMaxEntries = 1000,
    this.ccrTtl = const Duration(hours: 1),
    this.maxJsonItems = 30,
    this.maxLogLines = 200,
    this.maxSearchLines = 80,
    this.maxSearchFiles = 40,
    this.maxDiffLines = 150,
    this.maxTableRows = 30,
    this.textTargetRatio = 0.5,
    this.compressToolErrors = true,
    this.onCompressed,
  });

  final bool enabled;
  final int minChars;                 // 低于该字符数直接透传
  final double minSavingRatio;        // 压缩后 ≥ (1-ratio) 则回退原文
  final Set<String> protectedTools;   // 永不压缩的工具名
  final Set<ContentKind> disabledKinds;
  final bool ccrEnabled;
  final int ccrMaxEntries;
  final Duration ccrTtl;
  final int maxJsonItems;
  final int maxLogLines;
  final int maxSearchLines;
  final int maxSearchFiles;
  final int maxDiffLines;
  final int maxTableRows;
  final double textTargetRatio;       // 纯文本目标保留比，默认 0.5
  final bool compressToolErrors;
  final void Function(ContextCompressionResult)? onCompressed;
}
```

配置解析优先级：显式参数 > 上下文键 `'contextCompressionConfig'` > 构造默认值。

### 5.2 结果与统计

```dart
enum ContentKind { jsonArray, buildLog, searchResults, diff, tabular, text, sourceCode, passthrough }

class ContextCompressionResult {
  final bool applied;
  final ContentKind kind;
  final String content;      // 未应用时等于原文
  final int beforeChars;
  final int afterChars;
  final String? ccrId;
  final String? skippedReason; // tooSmall / protected / noSaving / disabled / alreadyCompressed / error / empty
}

class CompressionStats {
  int get total, applied, skipped, failures;
  int get beforeChars, afterChars;
  int get ccrStored, ccrHits;
  Map<ContentKind, KindStats> get byKind;
  Map<String, Object?> toJson(); // 含 estimated: true
}
```

token 数一律用「字符数 / 4 向上取整」估算，输出中显式标注 `estimated`，不用于计费。

### 5.3 能力缝

```dart
class ContentDetection {
  final ContentKind kind;
  final double confidence;       // 0..1
  final List<String> signals;    // 命中的检测信号，便于调试
}

typedef Detector = ContentDetection Function(String input);

abstract class ContentCompressor {
  ContentKind get kind;
  CompressionDraft? compress(String input, CompressionBudget budget);
}

class CompressionDraft {
  final String output;       // 不含 CCR 标记与省略说明（由 Router 统一追加）
  final int itemsOmitted;    // 0 表示只是格式紧凑化
  final String unit;         // 如 rows / lines / matches / hunks
}

class CompressionBudget {
  final int maxItems;
  final int maxLines;
  final int maxFiles;
  final double targetRatio;  // 由 config.textTargetRatio 派生
  final String retrievalId;  // CCR 关闭时为空串，压缩器据此决定是否嵌标记
  final bool conservative;   // 工具错误结果走保守模式
}
```

### 5.4 装配

```dart
class ContextCompressionService {
  ContextRouter get router;
  CcrStore get store;
  CompressionStats get stats;
}

ContextCompressionService provideContextCompression(
  Context ctx, {
  ContextCompressionConfig? config,
  CcrStore? store,
  ToolRegistry? tools,
  FileSystem? fs,
  String? dir,               // 传入则启用文件型 CCR
  List<ContentCompressor>? compressors, // 缺省用内置集合，测试可注入
});
```

服务键 `'contextCompressor'`，并提供 `extension ContextCompressionContext on Context`
的 `ctx.contextCompressor` 快捷访问。同时注册：

- 工具中间件（tag `contextCompression`）；
- `context_retrieve`（`ccrEnabled` 时）；
- `context_stats`。

中间件行为：

1. `config.enabled == false` 或工具在 `protectedTools` 中 → 透传；
2. `result.isError && !compressToolErrors` → 透传；
3. 调 `router.compress(result.content, toolName: call.name, conservative: result.isError)`；
4. `applied == false` → 返回原结果（保持 `value` 等宿主字段）；
5. `applied == true` → `ToolResult`，内容替换，`value` 合并
   `{'contextCompressed': true, 'kind': ..., 'ccrId': ..., 'originalChars': ...}`
   （新旧合并，同名键以新值为准）；
6. Router 抛错不可能外泄（内部 fail-open），中间件不再二次兜底。

### 5.5 非 Agent 入口

```dart
Future<List<LlmMessage>> compressMessages(
  List<LlmMessage> messages, {
  ContextCompressionConfig? config,
  CcrStore? store,
  List<ContentCompressor>? compressors,
  Set<String> roles = const <String>{'tool'},
}) async;
```

只改 `roles` 内的消息正文，保留 `toolCallId` / `toolCalls` / `images` / `thinkingBlocks`
等全部字段；不增删消息。默认只处理 `tool`，system/user/assistant 不动。

不传 `store` 时内部创建一次性内存 store，仅用于压缩；若调用方希望模型之后能
`context_retrieve`，必须自己持有同一个 store 并装上工具（或直接使用
`provideContextCompression`）。

## 6. 内容检测

检测顺序固定（先命中先返回）：

| 顺序 | 类型 | 信号 |
|---|---|---|
| 1 | `passthrough` | `git status` 人类可读格式（分支头 + staged/unstaged/untracked 分节） |
| 2 | `diff` | `diff --git`、`^--- ` + `^\+\+\+ `、`^@@ ... @@` 至少两类 |
| 3 | `searchResults` | ≥3 行匹配 `^(路径):\d+[:|-]`，路径允许 Windows 盘符与含 `-` 文件名 |
| 4 | `buildLog` | pytest / npm / cargo / jest / make 标记；或 ≥10 行含 `ERROR/WARN/FAIL/Traceback` 等行级信号 |
| 5 | `jsonArray` | trim 后以 `[` 开头、`jsonDecode` 成功、顶层是 List 且元素数 ≥ 3 |
| 6 | `tabular` | CSV/TSV 分隔一致性；或 markdown 表格（表头 + `|---|` 分隔行） |
| 7 | `sourceCode` | 缩进 + 关键字 + 括号密度启发式（只用于**透传**，不压缩） |
| 8 | `text` | 其余 |

检测器不做「多类型混合切分」：一条内容只走一个压缩器，避免语义被切碎。`git status` 与源码
保护优先于其他信号。检测前先剥离开头的 BOM（`\uFEFF`）。

JSON 压缩器需要的 CCR id 在压缩前就能确定（内容 hash），因此 Router 先计算 `retrievalId`
放进预算，压缩器把它嵌进 JSON 说明元素；其它类型的标记由 Router 统一追加。

## 7. 压缩算法

所有压缩器必须：确定性（无随机、无时间、无环境依赖）、保序、不伪造原文中不存在的事实。
省略一律显式标注，不允许静默截断。

### 7.1 JSON 数组

1. `jsonDecode`；仅处理顶层 `List`（嵌套大数组由 P2 的逐字段处理扩展，P1 不碰）。
2. 分类：全 Map → dict；全 String → string；全 num → number；否则 mixed。
3. 去重：按规范化 JSON（键排序、无空白）哈希，保留首次出现项。
4. 必留项：
   - 前 2 项与后 2 项；
   - 含错误信号的项：字段名或字符串值命中
     `error|fatal|fail|exception|timeout|denied|panic|stack`（大小写不敏感），
     或数值字段 `status >= 400` / `severity >= error`；
   - 结构异常值：某数值字段落在 1% / 99% 分位之外的项（样本 ≥ 20 时）。
5. 剩余名额按等距步长从去重后的列表采样，保持原顺序。
6. 输出紧凑 JSON（无多余空白），末尾追加一项显式说明：
   - dict 数组：`{"_conatus_context":"<omitted> items omitted; context_retrieve id=<ID>"}`；
   - string/number/mixed：追加一个说明字符串元素。
7. 结果必须仍是合法 JSON；输出前后各跑一次 `jsonDecode` 断言（开发模式）。

`maxItems` 默认 30；元素数 ≤ `maxItems` 时只做紧凑化，不省略。

### 7.2 构建/测试日志

1. 格式识别：pytest（`=== FAILURES ===` / `\d+ passed`）、npm（`npm ERR!`）、
   cargo（`error[E\d+]`）、jest（`PASS|FAIL` + `✓|✕`）、make（`make: ***`）、generic。
2. 逐行分类：级别（ERROR/FAIL/WARN/INFO/DEBUG/TRACE）、是否栈帧、是否摘要行。
   - Python：`Traceback` 起，直到「非缩进非空行且已出现过缩进帧」；
   - JS：`at ` 连续段；Java/C#：`at ` / `   at `；cargo：`--> ` 与缩进 `|` 段。
   - 栈帧判定一旦进入，后续缩进行即使中间有空行也保持（chained exception）。
3. 打分：级别基础分 + 栈帧加成 + 摘要加成 + 错误关键词加成。
4. 选择：全部 ERROR/FAIL；WARN 去重后保留（归一化只作用于尾部变量区，保留 `:` 前的消息前缀）；
   摘要行全保留；栈帧整段保留；每个选中行附 ±2 行上下文。
5. 超 `maxLines` 时从最低分的上下文行开始丢，再丢 INFO/DEBUG，**不丢**错误与栈。
6. 按原顺序输出；被跳过的区间插入 `[... N lines omitted ...]`。

保守模式（工具错误结果）：`maxLines` 取一半，上下文缩到 ±1，WARN/INFO 全丢。

### 7.3 搜索结果

1. 解析 `路径:行号:内容` 与 ripgrep 上下文格式 `路径-行号-内容`；Windows 盘符与含 `-` 的
   文件名按「最早出现的 `分隔符+数字+分隔符`」锚定，不按冒号切分。
2. 按文件聚合，保持文件首次出现顺序。
3. 每文件必留：首条与末条匹配行；命中错误关键词的行。
4. 文件按匹配数降序截断到 `maxFiles`（默认 40），被截断文件以
   `[... N more files with M matches ...]` 汇总。
5. 剩余行按「行号间隔均匀 + 错误关键词优先」填充到 `maxSearchLines`，回填后按行号排序。
   错误关键词沿用 7.1 的列表。
6. 每文件被省略的行输出 `[... N more matches in <path> ...]`。

### 7.4 Diff

1. 识别 `diff --git` / `---` / `+++` / `@@`。
2. 保留：文件头、hunk 头、所有 `+`/`-` 行、`\ No newline` 标记。
3. 上下文行（` ` 开头）每侧最多保留 1 行；连续上下文折叠为 `[... N context lines ...]`。
4. 超过 `maxDiffLines` 时不再丢变更行，改为按文件保留首尾 hunk、中间 hunk 整体替换为
   `[... N hunks omitted; context_retrieve id=<ID> ...]` 并把原文交给 CCR。
5. 输出仍是可读 diff（不要求可 apply），文档明确说明。

### 7.5 表格

1. CSV/TSV：按首个非空行的分隔符判断（`,` / `\t` / `;`），要求后续行列数一致率 ≥ 90%。
   保留表头 + 前 5 行 + 后 5 行 + 等距采样，**按原始文本行输出**，不重新引号化。
2. markdown 表格：保留表头与 `|---|` 分隔行 + 采样数据行。
3. 省略处插入与表格同列数的 `[... N rows omitted ...]` 说明行。
4. 仅在行数 > `maxTableRows` 时省略。

### 7.6 纯文本

1. 连续重复行折叠为 `line  (×N)`。
2. 连续空行（≥3）折叠为 1 个空行。
3. 必留：含 UUID、≥8 位 hex、URL、绝对/相对路径、`Error/FATAL/Exception` 的行。
4. 其余行按 0.5 目标比等距采样，头尾各保留 10 行。
5. 收益不足 `minSavingRatio` → 透传。

### 7.7 源码与 passthrough

`sourceCode`、`passthrough`、`git status` 一律不压缩，返回 `applied: false`，
`skippedReason: 'disabled'` 或 `'protected'`。

## 8. CCR 协议

### 8.1 标记

```
<<ctx:<ID> <N>_<unit>_omitted>>
```

例：`<<ctx:9f3a1c07b2d4e681 42_items_omitted>>`。单位取压缩器给的 `unit`
（items / lines / matches / hunks / rows），`N` 为省略数量（紧凑化时为 0，不写标记）。

- 标记只出现在压缩输出中，**不进入** CCR 原文。
- Router 写入标记后，`context_retrieve` 的工具描述里说明「看到 `<<ctx:ID ...>>` 可取回原文」。
- 输入中已含 `<<ctx:` → 直接透传（幂等）。

### 8.2 ID 与校验

ID 为 16 位小写 hex：`FNV-1a 64(content)` 与 `djb2(content)` 各取 32 位拼接。
读取时重算并与文件名比对，不一致视为未命中（防碰撞、防篡改）。非加密用途，不用于安全边界。

### 8.3 存储接口

```dart
abstract class CcrStore {
  Future<String> put(String content);
  Future<String?> get(String id);
  Future<CcrEntry?> stat(String id);
  Future<void> remove(String id);
  Future<void> clear();
  int get hits;
  int get length;
}

class CcrEntry {
  final String id;
  final int chars;
  final DateTime createdAt;
  final DateTime lastAccess;
  final int hits;
}
```

- `CcrMemoryStore`：`LinkedHashMap` 实现 LRU，按 `maxEntries` 淘汰最久未访问项，
  `ttl` 过期即视为未命中并在下一次写入时清理。
- `CcrFileStore`：目录下 `<id>.txt` 存原文，`index.json` 存
  `{version, entries: {id: {createdAt, lastAccess, hits, chars}}}`；两者都经 `FileSystem`
  原子写入。启动时加载索引并剔除内容缺失项；TTL 按 `createdAt` 判定（不依赖 mtime，
  因为 `FsInfo` 不保证提供修改时间）。默认目录 `~/.conatus/context-cache`。
- 容量淘汰、TTL 清理都发生在 `put`，读路径只更新 `lastAccess` 与 `hits`。

### 8.4 工具

```dart
class ContextRetrieveTool extends Tool {
  String get name => 'context_retrieve';
  // 参数：id（必填）、offset（可选，字符偏移，默认 0）、limit（可选，默认 40000）
  // 返回：原文片段；带 meta {id, chars, offset, returned, truncated}
  // 未命中：清晰说明「已过期或不存在」，不抛异常
}

class ContextStatsTool extends Tool {
  String get name => 'context_stats';
  // 返回 CompressionStats.toJson()，含 estimated: true
}
```

`context_retrieve` 必须支持分段读取，避免「取回原文」再次撑爆上下文。

## 9. 不变式与失败处理

1. **fail-open**：Router 内每个压缩器调用都包在 try/catch；异常 → `failures++`、返回原文。
   任何情况下中间件不向工具调用链抛异常。
2. **模型可见即已记录**：压缩发生在 `tool/result` 事件写入前，日志中的结果正文就是模型
   看到的正文；`checkModelVisibleInvariant` 不需要为 CCR 标记开例外。
3. **确定性**：同配置 + 同输入 → 字节相同的输出，便于回放与金样测试。唯一允许的输入以外
   状态是 CCR 容量/命中统计，它们不参与输出文本。
4. **幂等**：已含 `<<ctx:` 的内容不再压缩；`compressMessages` 对同一批消息重复调用结果不变。
5. **不拆配对**：只改单条 tool 消息正文，不增删消息、不改 role/toolCallId。
6. **收益门槛**：`afterChars > beforeChars * (1 - minSavingRatio)` → 回退原文并记 `noSaving`。
7. **大小写/编码**：全部按 UTF-16 字符串处理；不假设 ASCII。字符数与字节数分开统计，
   统计口径明确写「字符」。

## 10. 测试策略

### 单元测试（包内）

- 检测器：每类 ≥3 个正例 + 3 个近似负例（含 `git status`、源码、Windows 路径、含 `-` 文件名）。
- 每个压缩器：
  - 金样测试（固定 fixture → 固定输出）；
  - 保真断言：错误行、栈首行、UUID、关键 ID、首尾项必须存在；
  - JSON 输出 `jsonDecode` 成功；
  - 大小上限与 `minSavingRatio` 回退。
- Router：最小尺寸、保护名单、禁用 kind、收益不足、压缩器抛错、幂等、确定性（连续两次
  输出一致）。
- CCR：内存/文件往返字节相等、TTL 过期、LRU 淘汰、ID 碰撞校验、索引重建、异常输入。
- 工具：`context_retrieve` 分段读取、未命中、过期；`context_stats` 字段完整。
- 中间件：成功/失败结果、保护工具、`value` 合并、压缩后仍保留 `isError`、
  `enabled=false` 时直接透传且不写入任何标记。

### 集成测试（根仓 `test/integration/`）

- 装配 `AgentLoop` + 返回大 JSON 的脚本化工具 + `provideContextCompression`；
  跑一轮后 `checkModelVisibleInvariant(events)` 为空；
- 模型侧调用 `context_retrieve` 能取回原文；
- 同时开启 `tool-result-eviction`，验证「先压缩、再按阈值落盘」的顺序。

### 质量回归

固定 fixture 集（JSON/日志/搜索/diff/表格/文本各 2 份）上断言：关键事实存活、压缩比在预期
区间。任一类连续两份不达标 → 默认关闭该类并在文档记录。

### 静态检查

`dart analyze --fatal-infos`、`dart format`、受影响包 `dart test`，CI 全量。

## 11. 分阶段实施

| 阶段 | 内容 | 验收 |
|---|---|---|
| P1 | 包骨架、配置、检测器、JSON 压缩器、CCR（内存+文件）、Router、中间件、两个工具 | 包内测试全绿；根仓集成不变式测试通过 |
| P2 | 日志、搜索、diff、表格、文本压缩器 + 金样 | 各类型保真断言通过；`dart analyze` 干净 |
| P3 | 统计完善、README、根 README / AGENTS.md / 伞包 / 根 pubspec 同步、质量回归 fixture | 全仓测试 + 消费链验证通过 |

P1 完成即可被 `nava` 以一行 `provideContextCompression(app)` 接入；P2 只增加压缩器，不改接口。

## 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 压缩丢事实导致答案退化 | 保真锚点 + 质量回归 fixture + 每类可单独关闭；不达标即默认关 |
| 与 `layered_compaction` 重复治理 | 本包只处理「当前结果内部」；早期结果仍由分层折叠处理，两者作用域不重叠 |
| token 统计与真实分词器偏差 | 明确标注 `[estimated]`，只用于相对比较 |
| 文件型 CCR 跨进程并发 | 原子写 + 索引重建；并发写冲突时后写覆盖，`get` 校验内容 hash |
| 正则检测误判 | 检测顺序 + 置信度阈值 + 「源码/git status 优先透传」；误判最坏结果是透传 |
| 上游品牌与许可证 | 独立实现，不拷贝源码；README/NOTICE 注明思路来源与 Apache-2.0；包名 `conatus_context` |

## 13. 开放问题（已按默认决策锁定）

1. 包归类：**实验性**（先进伞包，API 稳定后再提稳定包）。
2. CCR 默认内存；文件后端通过 `dir` opt-in。
3. 标记前缀 `<<ctx:`，工具名 `context_retrieve` / `context_stats`。
4. 工具错误结果默认压缩，走保守模式。
5. 源码默认透传，不引入 AST 压缩。

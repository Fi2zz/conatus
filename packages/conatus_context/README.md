# conatus_context

conatus 的上下文压缩：在工具结果进入模型之前，按内容类型做**确定性、可解释的结构化压缩**，
并把原文存进本地 CCR（Compress-Cache-Retrieve）存储，模型需要细节时按标记取回。

它是 `layered-compaction`（跨轮折叠）与 `tool-result-eviction`（超限落盘）之间的缺失层：

```
工具结果
  ├─ conatus_context        单条内容内部压缩 + CCR 标记   ← 本包
  ├─ tool-result-eviction   压缩后仍超阈值时落盘
  └─ tool/result 事件       日志记录的就是模型看到的版本
```

- 不做跨轮摘要（`conatus_compaction` 负责）。
- 不做删除/重排消息，不碰工具调用配对。
- 不做 provider 代理、ML 文本压缩、代码 AST 改写。

## 快速开始

```dart
import 'package:conatus/conatus.dart';

// 内存型 CCR（默认）
provideContextCompression(app);

// 文件型 CCR：跨进程可读，按配置保留 TTL
provideContextCompression(app, dir: contextCacheDir());

// 与落盘驱逐器配合：先压缩，压完仍超限再落盘
provideContextCompression(app);
provideToolResultEviction(app, threshold: 80000);
```

装配后：

- 服务键 `'contextCompressor'`（`ctx.contextCompressor`）；
- 工具结果中间件（tag `contextCompression`）；
- `context_retrieve` 与 `context_stats` 两个工具（CCR 关闭时不注册取回工具）。

非 Agent 场景可以直接压缩消息：

```dart
final List<LlmMessage> compressed = await compressMessages(messages);
```

只处理 `role == 'tool'`，其余消息原样保留。

## 压缩器与保留规则

| 类型 | 策略 | 默认预算 |
|---|---|---|
| JSON 数组 | 保结构、去重、保错误项/极端异常值/首尾，其余等距采样 | 30 项 |
| 构建/测试日志 | 保 ERROR/FATAL、整段栈、摘要；WARN 去重；上下文 ±2 行 | 200 行 |
| grep / ripgrep | 按文件聚合，保首尾与错误行，文件按匹配数截断 | 80 行 / 40 文件 |
| unified diff | 保全部 `+`/`-` 行与 hunk 头，只折叠未变更上下文；超限保首尾 hunk | 150 行 |
| CSV / TSV / markdown 表格 | 保表头与首尾行，中间采样；按原始文本行输出 | 30 行 |
| 纯文本 | 连续重复折叠、空行折叠、保 UUID/hex/URL/路径/错误行，其余采样 | 保留 50% |

源码、`git status` 与无法识别的结构一律透传。

所有压缩器都是纯函数：无随机、无时间依赖、无 I/O，同一输入 + 同一配置输出字节一致。

## CCR 协议

压缩后若发生省略，输出中会出现：

```
<<ctx:0123456789abcdef 42_items_omitted>>
```

- id 是内容 hash（FNV-1a 64 + djb2，各取 32 位）；读取时重算校验，**不是安全边界**。
- 模型调用 `context_retrieve(id, offset?, limit?)` 取回原文，默认最多返回 40000 字符，
  可分段读取。
- 未命中（过期、编造 id、内容被篡改）返回可读失败，不抛异常。
- `context_stats()` 返回按类型累计的字符数、估算 token 节省与 CCR 命中数，带
  `estimated: true`。

## 配置

| 字段 | 默认 | 说明 |
|---|---|---|
| `enabled` | `true` | 总开关 |
| `minChars` | `4000` | 低于该字符数不压缩 |
| `minSavingRatio` | `0.15` | 节省不足则回退原文 |
| `protectedTools` | `{}` | 永不压缩的工具名 |
| `disabledKinds` | `{}` | 禁用某类压缩器 |
| `ccrEnabled` | `true` | 存原文 + 注入标记 + 注册取回工具 |
| `ccrMaxEntries` | `1000` | 内存/文件 CCR 容量 |
| `ccrTtl` | `1h` | 条目存活时间 |
| `maxJsonItems` | `30` | JSON 数组保留项 |
| `maxLogLines` | `200` | 日志保留行 |
| `maxSearchLines` | `80` | 搜索结果保留行 |
| `maxSearchFiles` | `40` | 搜索结果保留文件 |
| `maxDiffLines` | `150` | diff 保留行 |
| `maxTableRows` | `30` | 表格保留行 |
| `textTargetRatio` | `0.5` | 纯文本保留比例 |
| `compressToolErrors` | `true` | 工具错误结果走保守模式 |
| `onCompressed` | `null` | 每次压缩后的回调，可接遥测 |

也可以先把配置放进上下文：`ctx.provide('contextCompressionConfig', config)`。

## 失败与降级

- 压缩器抛错 → 返回原文，`failures++`，工具调用链不受影响。
- 收益不足 → `skippedReason: 'noSaving'`，返回原文。
- 已含 `<<ctx:` 标记 → 直接透传（幂等）。
- 工具结果 `value` 不是 Map 时，元数据写入 `originalValue`，不抛类型异常。

## 已知限制

- 字符数是 UTF-16 口径；token 数是 `chars / 4` 的估算，不用于计费。
- CSV 解析不处理带引号的字段；遇到复杂 CSV 请先转成 JSON 或直接透传。
- 源码默认不压缩，不引入 tree-sitter。
- 文件型 CCR 的并发写以后写覆盖为准；读取会校验内容 hash。
- diff 压缩后的输出可读，但不保证可以 `git apply`。

## 许可证与来源

本包是独立实现，思路参考
[headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom)（Apache-2.0），
未拷贝其源码。许可证见 [LICENSE](LICENSE)。

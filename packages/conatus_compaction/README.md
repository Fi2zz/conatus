# conatus_compaction

conatus 的压缩能力缝（仅依赖 `conatus_core` 与 `conatus_foundation`）：把会话日志里
较早的事件折叠成一条滚动摘要，服务键 `'compaction'`。

对应 dsh `packages/compaction/compaction` 的 Service Definition——契约在这里，策略
由实现方拥有。Dart 侧压缩**不重写日志**：被折叠的事件仍在日志里，压缩只在其后追加
三个记录事件，因此「发给模型的这段摘要是怎么来的」可以从日志重建。

## 服务契约

| 成员 | 说明 |
|---|---|
| `CompactionEngine`（服务键 `'compaction'`） | 压缩能力接口 |
| `keepRecent` | 保留为原文的最近事件数 |
| `summaryOf(sessionId)` / `forget(sessionId)` | 查询 / 丢弃某会话的滚动摘要 |
| `compactIfNeeded(session, summarize, {keepRecent}) → Future<CompactionResult?>` | 超预算时折叠；没有可折叠的平衡切点返回 `null` |
| `Compactor` | 默认实现（按预算折叠） |
| `provideCompaction(ctx, {engine})` | 装配到上下文 |

汇总器由调用方注入（通常是 `llm` 插件），返回 `CompactionSummary`：摘要文本加上
写它的 `provider` / `model`，后者随摘要一起落进日志。

```dart
final CompactionEngine compaction =
    provideCompaction(app, engine: Compactor(keepRecent: 20));
final CompactionResult? result = await compaction.compactIfNeeded(
  session,
  (List<SessionEvent> events, String previous) async =>
      CompactionSummary(await summarizeWithLlm(events, previous)),
);
```

## 日志协议

一次成功的压缩在日志末尾追加三个**纯记录**事件（`deriveAgentMessages` 只认三类消息
事件，它们不进模型消息）：

| 事件 | 负载 |
|---|---|
| `compaction/start` | `compactionId`、`keepRecent` |
| `compaction/summary` | `compactionId`、`summary`、`shadowedSeqs`、`kept`、`provider?`、`model?` |
| `compaction/end` | `compactionId`、`error?`（失败时） |

`shadowedSeqs` 是被折叠进摘要的事件 seq（日志开头的一段），`kept` 是保留为原文的
条数。汇总器抛错时 `compaction/end` 记下 `error`，摘要记忆不更新，异常原样上抛。

`checkCompactionInvariant(events)` 校验三个事件成对、同身份、折叠区间是日志开头的
一段，返回违规描述列表；`assertCompactionInvariant` 是抛错的开发模式版本。

## 切点安全

压缩切点不能把助手的工具调用与它的 `tool/result` 劈到两边——保留窗口若以孤立的工具
结果开头，模型会收到没有对应调用的 tool 消息。

- `balancedCutAtOrBefore(session, cut)`：把预算切点吸附到最近的平衡位置，返回 0
  表示没有可折叠的平衡切点；
- `toolPairingBalancedBefore(session, seq)` / `toolPairingBalancedAfter(session, seq)`：
  查询某个切点，seq 不在日志里或出现「结果先于调用」时抛 `StateError`。

平衡状态按事件类型增量折叠并缓存在会话对象上，重复查询不重读事件。

## 限制

- **手动与区间入口尚未落地**：没有 surface 替换层，也没有 `/compact` 命令，因此
  没有 `compactNow` / `compactRegion` 与对应的失败分类；
- **没有 `compaction/prune` 影子定价协议**：模型无关剪枝在 `conatus_agent` 的
  `tool-result-eviction`，尚未按影子定价协议落事件；
- **摘要的运行时状态是进程内表**：`compaction/summary` 是持久记录，但滚动摘要本身
  还没有「从日志折叠重建」的通路，fork 或重开进程后需要重新压缩；
- **没有跨进程压缩锁**：同一会话的并发压缩互不感知（当前只有 Agent Loop 一个发起方）。

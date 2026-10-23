# 方案：conatus_rag —— 面向多租户 Agent 的 Raw-RAG 检索层

> 日期：2026-10-23 · 状态：已批准设计（含企业扩展缝），待写实施计划
>
> 依据：arXiv:2610.30755《Is Complex Agentic Memory Always Needed? Naive RAG Is
> Stronger Than We Thought》——原始历史 + 稠密检索 + 重排在 6/7 个基准设置中超过
> 复杂 agentic memory；覆盖率是瓶颈，入库加工（原子事实 -19.62、摘要 -5.81、
> 图扩展 -5.78）普遍负收益。
>
> 定位：v1 是**会话历史的检索内核**，不是企业知识平台。目标形态是「多租户企业
> Agent」，因此公开 API 必须现在就把租户、权限、引用、预算、后端可替换留成缝；
> 文档接入、hybrid 检索、ACL 同步、向量数据库放到后续 spec。

## 1. 背景与问题

conatus 已有两套「历史」通路，但都取不出证据：

| 通路 | 现状 | 问题 |
|---|---|---|
| `SessionLog`（`session_log.dart`） | 只追加、可 replay、可 fork，保留全部原始事件 | 只能按 `sessionId` 整段回放，没有语义检索 |
| `MemoryStore`（`memory.dart`） | `recall` 按词元重叠（英文词 + 中文二元组）打分 | 非语义；`maxEntries=1000` 逐出最旧，主动销毁原始证据（论文 Finding 3 警告的正是这一点） |
| `agent_loop.dart:388` | 每轮把 `用户：…\n助手：…` 合成一条 memory 写入 | 入库即有损派生，再叠加逐出，原始路径丢失 |

同时 `conatus_llm` 没有嵌入端点，`conatus_intent` 虽有 `EmbeddingProvider` 缝，
但其 `LocalEmbeddingProvider` 自述「只认字形不认语义」，且位于实验性包——稳定包
不可依赖它。

结论：缺的不是「更复杂的记忆」，而是**原始历史的语义检索层**。且若要把
`conatus_agent` 包成企业产品，这一层从第一天就必须带租户与权限维度。

## 2. 目标与非目标

目标：

1. 从 `SessionLog` 增量摄取原始会话事件，切块 + 嵌入，建立向量索引。
2. 检索 = 查询嵌入 → 余弦取候选 → 可选重排 → top-k 原文块，**带时间戳、
   会话来源与 citation**，让 reader 自行恢复时序与状态。
3. 两条消费路径：`rag_search` 工具（开箱即用）+ 宿主接线的每轮自动注入（可选）。
4. **多租户与权限是一等公民**：每次摄入与检索都带 `RagScope`（tenant / principal /
   可见标签）；过滤在检索前下推，检索后复核。
5. **后端可替换**：`RagIndexBackend` 是 `search/filter/delete` 端口，内存与 JSON
   只是参考实现；后续 pgvector 等实现不改公开 API。
6. **可治理**：token 预算、citation、审计钩子、索引版本与重建路径。
7. 离线可测、无网络依赖（假 embedder / 假 HTTP）。
8. `conatus_agent` 零依赖：rag 是可选能力包，不进入 agent 的依赖闭包。

非目标（v1 不做，另立 spec 或适配层）：

- 原子事实抽取、摘要型记忆、图/社区扩展（论文实测负收益）。
- 文档 / 工单 / Confluence 等外部语料接入（v1 仅会话历史，但 `sourceKind` 已留）。
- hybrid 检索（BM25 + 向量 + RRF）：v1 只实现 dense，`Retriever` 缝留给装饰器。
- ACL 同步、DLP / PII 分级、多区域部署、分布式向量库。
- 改造 `conatus_intent` / `conatus_llm` 的既有嵌入缝（见 D5）。
- 替换 `compaction`（上下文预算问题，与检索正交）。

## 3. 方案形状

```
SessionLog (append-only)
   │  replay(sourceId) + ScopeResolver → tenant/principal/tags
   ▼
Chunker ──► Embedder ──► Retriever(dense) ──► RagIndexBackend.search(filter)
   │                          │                        │
   └─ citation/provenance     │ cosine top-128         └─ 内存 / JSON（v1）
   (sourceId, seq, time)      ▼                         后续 pgvector 等
                          Reranker (可选 HTTP)
                              │ top-15 + token budget
        ┌─────────────────────┴─────────────────────┐
        ▼                                           ▼
RagService.evidenceBlock(query, scope)           rag_search 工具
        │  宿主按请求闭包 scope                     （模型主动深挖）
        ▼
AgentLoop 的 EvidenceSource 钩子（可选；未接线则完全不注入）
```

关键约束：

- `conatus_rag` 与 `conatus_agent` **互不依赖**；agent 只认识
  `Future<String> Function(String)`。
- 租户与权限在**检索入口**生效，不靠调用方自觉。

## 4. 包结构与文件

新建稳定包 `packages/conatus_rag`，依赖 `conatus_core`、`conatus_foundation`、
`http`；`version: 0.16.0`、`publish_to: none`、`resolution: workspace`。

| 文件 | 职责（≤200 行/文件） |
|---|---|
| `lib/conatus_rag.dart` | 入口：library 文档 + 全部 export |
| `src/rag_types.dart` | `RagChunk` / `RagHit` / `Citation` / `RagScope` / `RetrievalRequest` / `RagFilter` / `RagStats` / `RagException` |
| `src/chunker.dart` | 事件序列化、字符窗切分、citation 保留 |
| `src/embedder.dart` | `Embedder` 缝 + `OpenAiEmbedder` |
| `src/reranker.dart` | `Reranker` 缝 + `NoopReranker` + `HttpReranker` |
| `src/cosine.dart` | 余弦（本地实现，不依赖实验性包） |
| `src/vector_index.dart` | 平坦索引：upsert / search / remove（内存后端的内核） |
| `src/retriever.dart` | `Retriever` 缝 + `DenseRetriever`（嵌入 → 搜索 → 重排 → 预算截断） |
| `src/visibility.dart` | `VisibilityPolicy` 缝 + `TenantTagPolicy`（默认：同租户 + 标签交集） |
| `src/rag_backend.dart` | `RagSnapshotMeta` / `RagIndexBackend` 端口 + `InMemoryRagBackend` + `JsonRagBackend` |
| `src/rag_index.dart` | 摄取编排：游标、白名单、切块、批量嵌入、版本校验 |
| `src/rag_service.dart` | `RagService` + `provideRag` + 审计事件 |
| `src/rag_tool.dart` | `rag_search` 工具 |

## 5. 接口契约

```dart
/// 一次调用/一个会话的归属与可见范围。由宿主从身份与会话表解析后传入。
class RagScope {
  final String tenantId;
  final String? principalId;        // 用户/服务身份
  final Set<String> visibilityTags; // 主体可见标签；必须含 tenant:<tenantId>
}

class RagChunk {
  final String id;                  // <sourceKind>/<sourceId>/<first>-<last>-<window>，稳定且唯一
  final String tenantId;
  final String sourceKind;          // v1 只有 'session'；为文档接入预留
  final String sourceId;            // v1 = sessionId
  final Set<String> visibilityTags;
  final int? firstSeq;              // session 专属
  final int? lastSeq;
  final Set<String> eventIds;
  final DateTime startTime;
  final DateTime endTime;
  final String text;                // 原文片段，永不改写
}

class Citation {
  final String sourceKind;
  final String sourceId;
  final String? url;                // 文档接入后填；session 为 null
  final int? firstSeq;
  final int? lastSeq;
  final DateTime startTime;
  final DateTime endTime;
}

class RagHit {
  final RagChunk chunk;
  final double score;               // 余弦
  final double? rerankScore;
  Citation get citation;
}

class RetrievalRequest {
  final String query;
  final RagScope scope;
  final int limit;                  // 默认 config.topK
  final int tokenBudget;            // 默认 config.tokenBudget（2000）
  final Set<String>? sourceIds;
  final DateTime? from;
  final DateTime? to;
}

class RagFilter {                   // 由 VisibilityPolicy 生成，下推给后端
  final String tenantId;
  final Set<String>? anyTags;       // 与 chunk.visibilityTags 求交
  final Set<String>? sourceIds;
  final DateTime? from;
  final DateTime? to;
}

abstract interface class Embedder {
  String get model;                 // 参与索引版本校验（换模型必须 rebuild）
  int get dimension;
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
  void dispose();
}

class OpenAiEmbedder implements Embedder {
  OpenAiEmbedder({
    required this.baseUrl,   // 如 https://ark.cn-beijing.volces.com/api/v3
    required this.model,     // 如 doubao-embedding-large
    required this.apiKey,
    this.client,             // 注入假 Client 用于测试
    this.dimension = 1024,
    this.batchSize = 16,
    this.timeout = const Duration(seconds: 20),
  });
}

abstract interface class Reranker {
  Future<List<RagHit>> rerank(
      String query, List<RagHit> candidates, {required int topK});
}

class RagSource {                    // 一次摄入的来源与归属
  final String sourceKind;          // v1 = 'session'
  final String sourceId;            // v1 = sessionId
  final RagScope scope;
}

class ChunkerConfig {
  final int chunkChars;
  final int overlapChars;
  final int maxChunkChars;
}

abstract interface class Retriever {
  Future<List<RagHit>> retrieve(RetrievalRequest request, RagFilter filter);
}

/// 检索前下推过滤；检索后复核（防御后端实现错误与越权）。
abstract interface class VisibilityPolicy {
  RagFilter filterFor(RagScope scope);
  bool allows(RagChunk chunk, RagScope scope);
}

/// 会话 → 归属范围。宿主从自己的会话/身份表提供；多租户下不要猜。
typedef ScopeResolver = Future<RagScope> Function(String sourceId);

abstract interface class RagIndexBackend {
  Future<RagSnapshotMeta?> meta();
  Future<void> init(RagSnapshotMeta meta);              // 模型/版本变化时重建
  Future<List<RagHit>> search(RagFilter filter,
      {required List<double> queryVector, required int k});
  Future<void> upsert(List<RagChunk> chunks, List<List<double>> vectors);
  Future<int> delete(RagFilter filter);                 // 连带删除匹配来源的游标
  Future<int> count();                                  // 索引块总数（运维/统计）
  Future<void> clear();                                 // 清空索引与游标
  Future<RagCursor?> cursorOf(String sourceId);
  Future<void> saveCursor(RagCursor cursor);
}

RagCursor {tenantId, sourceId, lastSeq}               // 游标属于来源，带租户便于清理

class RagService {
  Future<int> ingestSession(String sourceId);           // scope 经 ScopeResolver
  Future<int> ingestAll();
  Future<void> ensureIngested();                        // 懒补齐，幂等
  Future<List<RagHit>> retrieve(RetrievalRequest request);
  Future<String> evidenceBlock(String query, RagScope scope, {int? limit});
  Future<int> forgetSession(String sourceId, {required RagScope scope});
  Future<int> forgetScope(RagScope scope);              // 按租户 / 主体
  Future<void> rebuild();                               // 模型或切片变更后重建
  Future<void> clear();
  Future<RagStats> stats();
}

RagService provideRag(Context ctx, {
  required RagConfig config,
  required ScopeResolver scopeOf,
  RagScope? scope,                 // 本 Context 内工具调用的默认 scope；null 时工具 fail closed
  RagIndexBackend? backend,
  SessionLog? log,                 // 缺省取上下文里的 'sessionLog'
});
```

`RagConfig` 缺省值（论文默认，消融显示 chunk 128–1024、final-k 5–60 均不敏感）：

| 参数 | 默认 | 说明 |
|---|---|---|
| `chunkChars` / `overlapChars` | 700 / 90 | 按字符近似 token：中文约 1 字 ≈ 0.6 token、英文约 4 字符 ≈ 1 token，700 字大致落在 256–350 token |
| `candidates` | 128 | 余弦召回宽度 |
| `topK` | 15 | 重排后保留数 |
| `injectLimit` | 5 | 每轮自动注入条数 |
| `tokenBudget` | 2000 | 单次注入/工具返回的估算 token 上限 |
| `maxChunkChars` | 1200 | 单块上限，防单个巨型工具输出撑爆 |
| `retriever` | `DenseRetriever(...)` | 检索策略；hybrid 后续以装饰器替换 |
| `reranker` | null | 为空时只按余弦排序（论文：去掉重排 -3.92） |
| `indexVersion` | 1 | 切片/序列化变更时递增 |
| `visibility` | `TenantTagPolicy()` | 权限策略 |
| `onRetrieve` | null | 审计钩子（默认不落日志） |

## 6. 关键决策

**D1 原文即证据，不加工。** 索引只做「切分 + 嵌入」，入库零 LLM 调用；`text` 永不被
摘要或改写成事实。这是论文三条负收益消融的直接对照。

**D2 citation 必须完整。** 每块记录 `sourceKind/sourceId`、`seq` 区间、事件 id、时间
跨度；注入与工具输出都带 `[时间] (session:… seq:…)`。论文 Finding 2：只给答案值、
不给推导路径时，模型仍答不对；企业侧还需要可追溯来源。

**D3 注入不走可缓存 system prompt。** 现有 system 消息标了 `cacheable: true`，每轮变化
的证据会让缓存前缀失效。做法：稳定 system 之后追加一条
`LlmMessage('system', evidence, cacheable: false)`。

**D4 懒补齐 + 游标，不做写入钩子。** 每次 `retrieve`/`ensureIngested` 只处理游标之后的
新事件；摄取失败不推进游标，下次重试。避免在每轮对话里同步阻塞嵌入。

**D5 不依赖实验性包。** 稳定包不得依赖 `conatus_intent`，因此 `Embedder` 缝与余弦在本包
自带一份。与 `conatus_intent` 的概念重复记为后续项，不在本任务内重构。

**D6 不设条数上限。** 论文 Finding 3：入库期丢弃的信息检索期不可恢复。改为显式
`forgetSession` / `forgetScope` / `clear` 满足删除合规；磁盘体积写进 README 风险说明。

**D7 重排失败降级而非失败。** 无 `Reranker` 或 HTTP 失败时回退到余弦顺序，`stats`
记 `rerankFallbacks`。论文里去掉重排 -3.92，降级可用但要在 README 标注。

**D8 事件白名单。** 只索引 `user/message`、`assistant/message`、`tool/call`、
`tool/result`；跳过 `llm/*`（与消息重复）、`plan/*`、`goal/*`、`compaction/*` 等派生
事件。文本抽取按类型取 `text` / `content` / `args`，未知类型退回 JSON 字符串并截断。

**D9 能力包与 Agent 解耦。** agent 不 import rag，只暴露通用 `EvidenceSource`
函数钩子；宿主决定接不接。rag 需要网络与外部端点，不能成为 agent 的硬依赖。
代价是装配多一行，收益是依赖方向干净、可独立卸载。

**D10 租户/主体是一等公民。** `RagScope` 出现在每一个摄入与检索入口；`RagChunk`
自带 `tenantId` 与 `visibilityTags`（摄入时自动补 `tenant:<tenantId>`）。默认策略
`TenantTagPolicy` 做「同租户 + 标签交集」，检索前下推 `RagFilter`，检索后再
`allows` 复核（标签比较一律剔除自动补的 `tenant:` 标签：只带租户标签的块是租户级
公共证据，带额外标签的块要求与主体标签有交集；主体没有任何额外标签时**只能**看到
租户级块）。**禁止事后过滤**（先取全量再筛会泄漏存在性与数量）。多租户共享进程时，
绝不从 `sessionId` 猜测租户——必须由宿主 `ScopeResolver` 明确给出；工具所在
Context 未配置 scope 时拒绝执行。

**D11 后端端口面向企业规模。** 端口是 `search(request, filter)`，不是 `load()` 全量
快照；内存与 JSON 后端只是参考实现（万级块）。后续 pgvector/Milvus 实现不改公开
API。删除按 `RagFilter` 下推，不做「全量重写」。

**D12 索引可版本化重建。** 快照记录 `embeddingModel`、`dimension`、`indexVersion`；
任一不匹配抛 `rag_index_stale` 并提供 `rebuild()`。换模型不再靠人工 `clear()`。

**D13 审计是钩子，不是日志。** `onRetrieve(RetrievalAudit)` 交给宿主决定落库与保留期；
默认不把 query / 原文写进进程日志（凭据与 PII 硬约束）。审计事件只含 scope、命中
id、token 数、耗时。

## 7. 与 Agent 的关系（`agent` 零依赖，可选接线）

**`conatus_agent` 不依赖 `conatus_rag`、不 import 它的任何类型。** agent 侧只新增一个
与具体能力无关的通用钩子：

```dart
/// 单轮证据提供者：给定用户输入，返回可直接注入的原文证据块。
/// 返回空字符串表示无证据；抛错时 agent 按「无证据」继续，不阻断对话。
typedef EvidenceSource = Future<String> Function(String userInput);
```

1. `AgentLoop` 增加可选字段 `EvidenceSource? evidence`；`provideAgentLoop` 增加同名
   可选参数并透传。**未接线时行为与现在逐字节一致**，agent 的 pubspec 也不变。
2. `_runOnce` 在组装 messages 前 `await evidence(userInput)`，`try/catch` 后降级为空串；
   任何证据源（rag、memory、别的检索）都走同一个钩子。
3. 注入位置：稳定 system 消息之后、历史消息之前，插入
   `LlmMessage('system', block, cacheable: false)`；空串不插入。
4. 注入条数由 `RagConfig.injectLimit` 决定，agent 不设独立开关。
5. 宿主装配是唯一耦合点（3 行，可选）。多租户下宿主按请求闭包当前 scope，
   **不要**在共享实例上省掉 scope：

```dart
final RagService rag = provideRag(app, config: ..., scopeOf: scopeOfSession);
final RagScope scope = await resolveScope(request);       // 来自认证中间件
provideAgentLoop(app, evidence: (String q) => rag.evidenceBlock(q, scope));
```

6. `rag_search` 工具由 `provideRag` 自己 `ctx.tools.register`；工具的 scope 取自
   `provideRag(scope: ...)`，宿主按请求/租户创建子 Context 并传入。**未传 scope 时
   工具 fail closed（返回权限错误）**，避免共享进程里靠猜。
7. 证据块格式（由 rag 生成，agent 原样插入，按时间升序、id 去重）：

```
[相关历史证据]
以下片段来自会话历史原文，按时间升序。据此推导答案；缺失的信息不要臆测。
- [2026-10-20 14:03] (session:abc seq:12-18) 用户：… 助手：…
```

8. `rag_search` 工具参数：`query`（必填）、`limit`（默认 5，上限 15）、`session_id`、
   `from` / `to`（ISO 8601）。输出为证据块 + 命中统计，`value` 里给结构化 hits 与
   citations。风险级别：只读检索，`RiskLevel.low`；越权由策略层拦截而非审批。

## 8. 错误与降级

| 场景 | 行为 |
|---|---|
| 查询嵌入失败（网络/鉴权） | `evidenceBlock` 抛错由 agent 钩子捕获 → 不注入、不阻断对话；rag 记 `rag_embed_failed`；`rag_search` 返回 `ToolResult.failure` |
| 入库嵌入失败 | 游标不推进，下次重试；记录失败块数 |
| 重排失败 | 回退余弦顺序，`stats.rerankFallbacks++` |
| 索引版本/模型/维度不一致 | fail closed：`RagException('rag_index_stale')`，引导 `rebuild()` |
| 后端搜索失败 | 冒泡为 `rag_backend_failed`；不返回降级的全量结果（避免越权） |
| 后端 JSON 损坏 | 抛 `rag_backend_broken`，不静默清空；调用方决定 `rebuild()` |
| 租户/标签过滤后为空 | 返回空列表，注入块为空字符串（不占位），`stats.emptyResults++` |
| `ScopeResolver` 失败 | 拒绝摄入该会话（不猜测租户），记 `rag_scope_unresolved` |
| 工具所在 Context 未提供 scope | fail closed：`ToolResult.failure('rag_scope_missing')`，不查任何数据 |

日志经 `Logger` 能力，键名级排障，**不打印 apiKey、query 原文与证据正文**。

## 9. 删除、隐私与合规

- `forgetSession(sourceId, scope)`：仅删除该 scope 下该会话的块与游标，返回删除块数。
- `forgetScope(scope)`：按租户或主体清除（DSAR / 离职 / 租户退订）。
- `clear()`：清空全部索引与游标（运维动作，需宿主鉴权）。
- README 明确：索引落盘包含会话原文（含 `tool/result` 输出），与会话日志同一暴露面；
  不写入日志，落盘位置与 `~/.conatus` 同级保护。
- 不引入新的脱敏逻辑：原文即是证据，论文的核心结论要求保留原文；若宿主需要脱敏，
  应在写入会话日志的源头处理（既有能力），RAG 只消费日志已有内容。
- `JsonRagBackend` 的租户隔离是**逻辑隔离**（同一文件、按字段过滤）。私有化与强隔离
  场景用「每租户一个后端实例 / 目录」，或等后续 pgvector + RLS 实现；README 必须写明。

## 10. 测试计划

单元（`packages/conatus_rag/test/`）：

- `chunker_test`：事件序列化、窗边界、重叠、时间跨度、单事件超长截断、citation 正确。
- `vector_index_test`：top-k 顺序、维度校验、删除。
- `rag_backend_test`：JSON 往返、原子写、游标持久化、`filter` 下推（租户/标签/时间）。
- `embedder_test` / `reranker_test`：注入 `http.Client` 假响应；错误码映射；批大小。
- `visibility_test`：同租户可见、跨租户不可见、标签交集、缺失标签默认不可见。
- `retriever_test`：候选→重排→token 预算截断顺序；重排降级。
- `rag_index_test`：增量幂等（重复 ingest 块数不变）、游标不推进、白名单过滤、
  `ScopeResolver` 失败不摄入、`rag_index_stale` 触发。
- `rag_service_test`：检索/注入块格式/降级/`forgetSession` 与 `forgetScope` 穿透/
  审计钩子被调用且不含正文。
- `rag_tool_test`：schema、参数校验、limit 上限、越权 scope 拿不到数据、未配置
  scope 时 fail closed、失败返回。

`conatus_agent` 侧（新增，确保零耦合）：

- `evidence_source_test`：未接线时消息序列与现状一致；接线后证据块位于稳定 system
  之后且 `cacheable == false`；钩子抛错时本轮照常完成且不注入。

集成（`test/integration/rag_test.dart`）：

- `TestHarness` + `PersistenceSessionLog` + 确定性假 embedder + `ScriptedLlm`，宿主以
  `provideAgentLoop(app, evidence: ...)` 接线：会话 1 陈述事实 → 会话 2 提问 →
  断言注入块与 `rag_search` 都能取回该事实，且带正确 citation 与时间。
- **跨租户隔离**：租户 A 的会话事实，在租户 B 的 scope 下检索与工具调用都取不到
  （即使同一进程、同一后端文件）。

评测（`test/eval/recall_eval_test.dart`，离线、确定性）：

- 3 段种子会话 + 20 个手工问题（含改写、多跳、时序、跨会话四类）；
- 用「预计算嵌入 fixture」（同义句向量手工拉近）替代真实端点，保证离线可复现；
- 指标：`coverage@5`（gold 事实是否落在注入块内）对比现有 keyword recall；
- 真实端点的对比结果（豆包 embedding + rerank）记录在 PR 描述，不进门禁。

## 11. 文档与交付

- 根 `pubspec.yaml` 加 `conatus_rag: {path: packages/conatus_rag}`。
- `lib/conatus.dart` 增加 export 与包注释；根 `README.md` 包表 + `### rag` 用法节。
- `AGENTS.md`：包计数按实际清点更新（新增后为 15 个稳定包 + 12 个实验性包，另有
  `conatus_code` 子模块）；依赖关系写明 `rag` 是**可选能力包**，不进入 `agent` 的
  依赖闭包，接线由宿主完成。
- 新包 `README.md`（用法、scope/权限模型、配置、成本、隐私与隔离边界）+ `CHANGELOG.md`。
- 验收：`dart analyze --fatal-infos` + `conatus_rag` / `conatus_agent` / 根测试全绿；
  `dart format .` 后提交推送。

## 12. 风险与边界

1. **语义增益依赖真实嵌入端点**：本地哈希嵌入只认字形，不能作为检索质量的证据。
2. **企业语料 ≠ 对话基准**：论文只覆盖日常对话问答；错误码、SKU、法条号等精确 token
   需要 hybrid，v1 的 dense-only 在这些查询上会明显偏弱。
3. **每轮一次嵌入调用**增加延迟（论文未计入 reader 生成；需在 PR 中记录 P50/P99）。
4. **索引体积**：无上限意味着随会话线性增长；README 给出估算与删除建议。
5. **逻辑隔离不是物理隔离**：JSON 后端同文件存多租户；强隔离必须换后端实例或外部库。
6. **ACL 时效性**：`visibilityTags` 由宿主同步，标签过期 = 越权风险；策略层每次检索
   都会复核，但无法修复上游延迟。
7. **短会话收益低**：上下文装得下时 full-context 更强（MEME DeepSeek 63.17 vs 43.19），
   文档标注「长历史场景才启用」。
8. **跨会话去重**：同义重复内容可能占满 top-k；首版仅按 chunk id 去重，不做语义聚类
   （聚类属于被论文证否的加工方向）。

## 13. 后续项（不在本任务）

- `HybridRetriever`（BM25 + 向量 + RRF）作为 `Retriever` 装饰器。
- `conatus_rag_pgvector` / 企业向量库后端（后端端口已就位，不改公开 API）。
- 文档/工单语料接入与结构感知切片（`sourceKind` / `Chunker` 缝已就位）。
- ACL 同步、DLP / PII 分级、租户级配额与限流。
- `conatus_intent` 的 `EmbeddingProvider` 与本包 `Embedder` 合并为单一缝。
- 将 `MemoryStore` 的自动写入改为「仅索引原文」，避免双重派生（需评估兼容性）。
- 重排端点与 embedding 模型的可配置矩阵（按成本/语言选型）。

## 14. 验收标准

1. `conatus_agent` 的 `pubspec.yaml` 不含 `conatus_rag`，源码不 import 该包；未接线
   `evidence` 时，`agent` / 全仓测试与现有行为逐字节一致（无注入消息）。
2. 接线后：会话 A 陈述的事实，在会话 B 的提问中出现在注入块，且 citation 的
   `sourceId`/`seq`/时间正确；`rag_search` 能取回同样的块。
3. **跨租户隔离**：租户 B 的 scope 下，检索与工具都拿不到租户 A 的任何块；
   `forgetScope` 后原租户也拿不到；工具所在 Context 未提供 scope 时拒绝执行。
4. 重复 `ingestAll()` 不产生重复块；`forgetSession` 后该事实不再被检索到。
5. 嵌入端点不可达时，对话照常完成（无注入），并在日志出现 `rag_embed_failed`；
   `dart analyze --fatal-infos` 与受影响包测试全绿。

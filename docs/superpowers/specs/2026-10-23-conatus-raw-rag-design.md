# 方案：conatus_rag —— 基于原始会话历史的 Raw-RAG 检索层

> 日期：2026-10-23 · 状态：已批准设计，待写实施计划
>
> 依据：arXiv:2610.30755《Is Complex Agentic Memory Always Needed? Naive RAG Is
> Stronger Than We Thought》——原始历史 + 稠密检索 + 重排在 6/7 个基准设置中超过
> 复杂 agentic memory；覆盖率是瓶颈，入库加工（原子事实 -19.62、摘要 -5.81、
> 图扩展 -5.78）普遍负收益。

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

结论：缺的不是「更复杂的记忆」，而是**原始历史的语义检索层**。

## 2. 目标与非目标

目标：

1. 从 `SessionLog` 增量摄取原始会话事件，切块 + 嵌入，建立平坦向量索引。
2. 检索 = 单次查询嵌入 → 余弦取候选 → 可选重排 → top-k 原文块，**带时间戳与会话
   来源**，让 reader 自行恢复时序与状态。
3. 两条消费路径：每轮自动注入少量证据 + `rag_search` 工具深检索。
4. 离线可测、无网络依赖（假 embedder / 假 HTTP）。
5. 提供删除能力（按会话清除），不设条数上限。

非目标（明确不做，均有论文实测负收益或超出首版范围）：

- 原子事实抽取、摘要型记忆、图/社区扩展。
- 索引工作区文件、外部文档、`MemoryStore` 条目（仅会话历史）。
- 改造 `conatus_intent` 或 `conatus_llm` 的既有嵌入缝（见决策 D5）。
- 替换 `compaction`（上下文预算问题，与检索正交）。

## 3. 方案形状

```
SessionLog (append-only)
   │  replay(sessionId) 增量游标
   ▼
Chunker ──► Embedder ──► VectorIndex ──► RagIndexBackend (JSON / 内存)
   │                          │
   └─ provenance              │ cosine top-128
   (eventIds/time span)       ▼
                          Reranker (可选 HTTP)
                              │
                              ▼ top-15
        ┌─────────────────────┴─────────────────────┐
        ▼                                           ▼
AgentLoop 自动注入（每次 top-5，非缓存消息）      rag_search 工具（模型主动深挖）
```

## 4. 包结构与文件

新建稳定包 `packages/conatus_rag`，依赖 `conatus_core`、`conatus_foundation`、
`http`；`version: 0.16.0`、`publish_to: none`、`resolution: workspace`。

| 文件 | 职责（≤200 行/文件） |
|---|---|
| `lib/conatus_rag.dart` | 入口：library 文档 + 全部 export |
| `src/rag_types.dart` | `RagChunk` / `RagHit` / `RagStats` / `RagException` |
| `src/chunker.dart` | 事件序列化、字符窗切分、provenance 保留 |
| `src/embedder.dart` | `Embedder` 缝 + `OpenAiEmbedder` |
| `src/reranker.dart` | `Reranker` 缝 + `NoopReranker` + `HttpReranker` |
| `src/cosine.dart` | 余弦（本地实现，不依赖实验性包） |
| `src/vector_index.dart` | 平坦索引：add / search / remove |
| `src/rag_backend.dart` | `RagSnapshot` + `RagIndexBackend` 端口 + `InMemoryRagBackend` + `JsonRagBackend` |
| `src/rag_index.dart` | 摄取编排：游标、过滤、切块、批量嵌入 |
| `src/rag_service.dart` | `RagService` + `provideRag` |
| `src/rag_tool.dart` | `rag_search` 工具 |

## 5. 接口契约

```dart
class RagChunk {
  final String id;                 // rag-<sessionId>-<firstSeq>-<lastSeq>（稳定、幂等）
  final String sessionId;
  final int firstSeq;
  final int lastSeq;
  final Set<String> eventIds;
  final DateTime startTime;
  final DateTime endTime;
  final String text;               // 原文片段，永不改写
}

abstract interface class Embedder {
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
  Future<List<RagHit>> rerank(String query, List<RagHit> candidates, {required int topK});
}

class RagService {
  Future<int> ingestSession(String sessionId);
  Future<int> ingestAll();
  Future<void> ensureIngested();                       // 懒补齐，幂等
  Future<List<RagHit>> retrieve(String query, {int? limit, Set<String>? sessionIds,
      DateTime? from, DateTime? to});
  Future<String> evidenceBlock(String query, {int? limit});
  Future<int> forgetSession(String sessionId);
  Future<void> clear();
  RagStats get stats;
}

RagService provideRag(Context ctx, {required RagConfig config, RagIndexBackend? backend});

abstract interface class RagIndexBackend {
  Future<RagSnapshot?> load();
  Future<void> save(RagSnapshot snapshot);             // 索引 + 每会话游标
}
```

`RagConfig` 缺省值（论文默认，消融显示 chunk 128–1024、final-k 5–60 均不敏感）：

| 参数 | 默认 | 说明 |
|---|---|---|
| `chunkChars` / `overlapChars` | 700 / 90 | 按字符近似 token：中文约 1 字 ≈ 0.6 token、英文约 4 字符 ≈ 1 token，700 字大致落在 256–350 token；消融显示 128–1024 token 均不敏感 |
| `candidates` | 128 | 余弦召回宽度 |
| `topK` | 15 | 重排后保留数 |
| `injectLimit` | 5 | 每轮自动注入条数 |
| `maxChunkChars` | 1200 | 单块上限，防单个巨型工具输出撑爆 |

## 6. 关键决策

**D1 原文即证据，不加工。** 索引只做「切分 + 嵌入」，入库零 LLM 调用；`text` 永不被
摘要或改写成事实。这是论文三条负收益消融的直接对照。

**D2 provenance 必须完整。** 每块记录 `sessionId`、`seq` 区间、事件 id 集合、时间跨度；
注入与工具输出都带 `[时间] (session:… seq:…)`。论文 Finding 2：只给答案值、不给
推导路径时，模型仍答不对。

**D3 注入不走可缓存 system prompt。** 现有 system 消息标了 `cacheable: true`，每轮变化
的证据会让缓存前缀失效。做法：稳定 system 之后追加一条
`LlmMessage('system', evidence, cacheable: false)`。

**D4 懒补齐 + 游标，不做写入钩子。** 每次 `retrieve`/`ensureIngested` 只处理游标之后的
新事件；摄取失败不推进游标，下次重试。避免在每轮对话里同步阻塞嵌入。

**D5 不依赖实验性包。** 稳定包不得依赖 `conatus_intent`，因此 `Embedder` 缝与余弦在本包
自带一份。与 `conatus_intent` 的概念重复记为后续项，不在本任务内重构。

**D6 不设条数上限。** 论文 Finding 3：入库期丢弃的信息检索期不可恢复。改为显式
`forgetSession` / `clear` 满足删除合规；磁盘体积写进 README 风险说明。

**D7 重排失败降级而非失败。** 无 `Reranker` 或 HTTP 失败时回退到余弦顺序，`stats`
记 `rerankFallbacks`。论文里去掉重排 -3.92，降级可用但要在 README 标注。

**D8 事件白名单。** 只索引 `user/message`、`assistant/message`、`tool/call`、
`tool/result`；跳过 `llm/*`（与消息重复）、`plan/*`、`goal/*`、`compaction/*` 等派生
事件。文本抽取按类型取 `text` / `content` / `args`，未知类型退回 JSON 字符串并截断。

## 7. Agent 集成（`conatus_agent` 改动点）

1. `conatus_agent` 新增对 `conatus_rag` 的 path 依赖（方向 `agent → rag → foundation`，
   无环）。
2. `AgentLoop` 增加 `RagService? rag`；注入条数统一取 `RagConfig.injectLimit`，不另设
   独立开关。`provideAgentLoop` 用 `ctx.get<RagService>('rag')` 自动解析，未装配时行为
   完全不变。
3. `_runOnce` 在组装 messages 前 `await rag?.retrieve(userInput)`；结果经
   `buildSystemText` 新增的可选参数传入，`_systemText` 接收已取回的 hits，避免计划阶段
   二次检索。
4. 注入位置：稳定 system 消息之后、历史事件消息之前，插入
   `LlmMessage('system', evidence, cacheable: false)`；证据为空时不插入。
5. 证据块格式（按时间升序，冲突去重）：

```
[相关历史证据]
以下片段来自会话历史原文，按时间升序。据此推导答案；缺失的信息不要臆测。
- [2026-10-20 14:03] (session:abc seq:12-18) 用户：… 助手：…
```

6. `rag_search` 工具参数：`query`（必填）、`limit`（默认 5，上限 15）、`session_id`、
   `from` / `to`（ISO 8601）。输出为证据块 + 命中统计，`value` 里给结构化 hits。
   风险级别：只读本地检索，`RiskLevel.low`。

## 8. 错误与降级

| 场景 | 行为 |
|---|---|
| 查询嵌入失败（网络/鉴权） | 不注入、不阻断对话；记 `rag_embed_failed` 日志；工具返回 `ToolResult.failure` |
| 入库嵌入失败 | 游标不推进，下次重试；对数记录失败块数 |
| 重排失败 | 回退余弦顺序，`stats.rerankFallbacks++` |
| 维度不一致（换模型后旧索引） | fail closed：抛 `RagException('rag_dimension_mismatch')`，提示 `clear()` 重建 |
| 后端 JSON 损坏 | 抛 `rag_backend_broken`，不静默清空；调用方决定 `clear()` |
| 索引为空 | 返回空列表，注入块为空字符串（不占位） |

日志经 `Logger` 能力，键名级排障，**不打印 apiKey**（凭据脱敏硬约束）。

## 9. 删除与隐私

- `forgetSession(id)`：删除该会话全部块与游标，重建索引文件，返回删除块数。
- `clear()`：清空全部索引与游标。
- README 明确：索引落盘包含会话原文（含 `tool/result` 输出），与会话日志同一暴露面；
  不写入日志，落盘位置与 `~/.conatus` 同级保护，删除走 `forgetSession` / `clear`。
- 不引入新的脱敏逻辑：原文即是证据，论文的核心结论要求保留原文；若宿主需要脱敏，
  应在写入会话日志的源头处理（既有能力），RAG 只消费日志已有内容。

## 10. 测试计划

单元（`packages/conatus_rag/test/`）：

- `chunker_test`：事件序列化、窗边界、重叠、时间跨度、单事件超长截断、provenance 正确。
- `vector_index_test`：top-k 顺序、维度校验、删除。
- `rag_backend_test`：JSON 往返、原子写、游标持久化。
- `embedder_test` / `reranker_test`：注入 `http.Client` 假响应；错误码映射；批大小。
- `rag_index_test`：增量幂等（重复 ingest 块数不变）、游标不推进、白名单过滤。
- `rag_service_test`：检索/注入块格式/降级/`forgetSession` 穿透。
- `rag_tool_test`：schema、参数校验、limit 上限、失败返回。

集成（`test/integration/rag_test.dart`）：

- `TestHarness` + `PersistenceSessionLog` + 确定性假 embedder + `ScriptedLlm`：
  会话 1 陈述事实 → 会话 2 提问 → 断言注入块与 `rag_search` 都能取回该事实，
  且带正确 `session:seq` 与时间。

评测（`test/eval/recall_eval_test.dart`，离线、确定性）：

- 3 段种子会话 + 20 个手工问题（含改写、多跳、时序、跨会话四类）；
- 用「预计算嵌入 fixture」（同义句向量手工拉近）替代真实端点，保证离线可复现；
- 指标：`coverage@5`（gold 事实是否落在注入块内）对比现有 keyword recall；
- 真实端点的对比结果（豆包 embedding + rerank）记录在 PR 描述，不进门禁。

## 11. 文档与交付

- 根 `pubspec.yaml` 加 `conatus_rag: {path: packages/conatus_rag}`。
- `lib/conatus.dart` 增加 export 与包注释；根 `README.md` 包表 + `### rag` 用法节。
- `AGENTS.md`：包计数按实际清点更新（新增后为 15 个稳定包 + 11 个实验性包，另有
  `conatus_code` 子模块）；依赖方向补 `agent → rag → foundation`（rag 不依赖 llm）。
- 新包 `README.md`（用法、配置、成本与隐私边界）+ `CHANGELOG.md`。
- 验收：`dart analyze --fatal-infos` + `conatus_rag` / `conatus_agent` / 根测试全绿；
  `dart format .` 后提交推送。

## 12. 风险与边界

1. **语义增益依赖真实嵌入端点**：本地哈希嵌入只认字形，不能作为检索质量的证据。
2. **每轮一次嵌入调用**增加延迟（论文未计入 reader 生成；实测应在 100ms 量级，需在
   PR 中记录 P50/P99）。
3. **索引体积**：无上限意味着随会话线性增长；README 给出估算与 `forgetSession` 建议。
4. **短会话收益低**：上下文装得下时 full-context 更强（MEME DeepSeek 63.17 vs 43.19），
   文档标注「长历史场景才启用」。
5. **跨会话去重**：同义重复内容可能占满 top-k；首版仅按 chunk id 去重，不做语义聚类
   （聚类属于被论文证否的加工方向）。

## 13. 后续项（不在本任务）

- `conatus_intent` 的 `EmbeddingProvider` 与本包 `Embedder` 合并为单一缝。
- 文件/文档语料接入（独立 spec）。
- 将 `MemoryStore` 的自动写入改为「仅索引原文」，避免双重派生（需评估兼容性）。
- 重排端点与 embedding 模型的可配置矩阵（按成本/语言选型）。

## 14. 验收标准

1. 未装配 `rag` 时，`agent` / 全仓测试与现有行为逐字节一致（无注入消息）。
2. 装配后：会话 A 陈述的事实，在会话 B 的提问中出现在注入块，且带正确的
   `session:seq` 与时间戳；`rag_search` 能取回同样的块。
3. 重复 `ingestAll()` 不产生重复块；`forgetSession(A)` 后该事实不再被检索到。
4. 嵌入端点不可达时，对话照常完成（无注入），并在日志出现 `rag_embed_failed`；
   `dart analyze --fatal-infos` 与受影响包测试全绿。

# conatus_rag

会话原文的 RAG 能力包：切分、嵌入、索引与带租户可见性的稠密检索（Raw-RAG）。

## 定位

`conatus_rag` 是**会话历史的检索内核**：把已经沉淀在 `SessionLog` 里的对话原文
切成块、嵌入成向量、按查询召回最相关的原文片段，作为「证据」注入模型上下文。

它不是企业知识平台，明确**不做**以下事情：

- 不做事实抽取、摘要改写、图谱构建或实体归一——`RagChunk.text` 永远是原文，
  切片只按字符窗口滑动，不重写任何字；
- 不做跨来源的语义合并或「知识库」级管理——它的最小来源单位是单个会话；
- 不做用户身份级（principal）的删除——删除粒度到来源（会话）与租户为止。

一句话：**原文进、原文出**，检索结果带来源引用，供上层（Agent Loop 或你的应用）
自行决定如何使用。

## 架构

```
SessionLog ─▶ Chunker ─▶ Embedder ─▶ RagIndexBackend
                     │
                     └─▶ 检索：嵌入查询 ─▶ 过滤(租户/标签/来源/时间窗) ─▶ 余弦 ─▶ 可选重排 ─▶ token 预算截断
```

- **SessionLog**（`conatus_foundation`）：会话事件的只追加日志，RAG 的唯一数据源。
  摄入按 `seq` 游标增量推进，`ingestAll()` 幂等补齐。
- **Chunker**（`chunkEvents`）：按字符窗口滑动切块，窗口重叠保证跨块上下文连续；
  超长事件先按 `maxChunkChars` 截断再入窗。
- **Embedder**（`Embedder` 契约）：把块文本与查询映射为定长稠密向量。内置
  `OpenAiEmbedder`（OpenAI 兼容 `POST /embeddings` 端点），可自行实现契约注入。
- **RagIndexBackend**（端口）：切片 + 向量 + 游标 + 遗忘集合的存储与检索。内置
  `InMemoryRagBackend`（测试/万级以下）与 `JsonRagBackend`（原子落盘的 JSON 文件），
  同一契约下未来可接 pgvector 等外部向量库。

检索流水线（`DenseRetriever`）：嵌入查询 → 后端按过滤条件取候选（`candidates`）→
可选重排（`reranker`，缺省 `NoopReranker`，重排失败静默回退原序）→ 按 token 预算
累加截断（至少保留 1 条，不超过 `topK`）。

## 最小用法 ①：独立工具

`provideRag` 把 `RagService` 提供为 `'rag'` 服务，并在 `tools` 已就绪时自动注册
`rag_search` 工具。`scope` 必须显式提供，否则工具 **fail closed**（拒绝执行）。

```dart
import 'package:conatus/conatus.dart';

Future<void> main() async {
  final app = Context.root(name: 'app');

  provideTools(app);
  provideSessionLog(app);

  final rag = provideRag(
    app,
    config: RagConfig(
      embedder: OpenAiEmbedder(
        baseUrl: 'https://api.example.com/v1',
        model: 'text-embedding-3-small',
        apiKey: '…', // 从凭据注入，勿硬编码
        dimension: 1536,
      ),
    ),
    // 来源 → 作用域的解析；绝不能靠猜测，解析失败即 `rag_scope_unresolved`
    scopeOf: (sourceId) async => RagScope(tenantId: 'tenant-a'),
    // 工具检索作用域；为 null 时 rag_search 直接拒绝
    scope: RagScope(tenantId: 'tenant-a'),
  );

  // 让模型调用 rag_search，或直接检索：
  final hits = await rag.retrieve(
      RetrievalRequest(query: '上次讨论的部署方案', scope: RagScope(tenantId: 'tenant-a')));
  print(rag.formatHits(hits));
}
```

## 最小用法 ②：接入 Agent（可选）

`provideAgentLoop` 有 `evidence` 参数（`Future<String> Function(String userInput)`），
每轮组模型请求前取回原文证据注入 system。接上 RAG 即可让 Agent 自动带证据回答；
**不接线时 Agent 行为完全不变，`conatus_agent` 不依赖本包**（接线由宿主完成）。

```dart
final scope = RagScope(tenantId: 'tenant-a');
provideAgentLoop(app, evidence: (q) => rag.evidenceBlock(q, scope));
```

## 多租户与权限

`RagScope{tenantId, principalId, visibilityTags}` 描述一次调用/一个会话的归属与可见
范围，由宿主从身份与会话表解析后传入：

- 构造时自动注入 `tenant:<tenantId>` 标签，租户隔离是硬边界；
- 摄入的每个切片带有来源作用域的 `visibilityTags`；检索时按「租户相等 + 标签交集」
  双重过滤（`TenantTagPolicy`，可注入 `VisibilityPolicy` 替换）；
- 无额外标签的切片是**租户级块**，租户内所有作用域可见；带额外标签的切片是
  **受限块**，只有标签有交集的作用域可见；
- `ScopeResolver`（`Future<RagScope> Function(String sourceId)`）**不许猜**：解析失败
  一律 `rag_scope_unresolved`，摄入与遗忘都依赖它归因；
- `rag_search` 工具的 `scope` 为 null、或空标签导致无交集时，均 **fail closed**。

## 配置默认值

`RagConfig` 的缺省值（除 `embedder` 必填外）：

| 参数 | 默认 | 说明 |
|------|------|------|
| `chunkChars` | 700 | 切片目标字符数 |
| `overlapChars` | 90 | 相邻切片重叠字符数 |
| `maxChunkChars` | 1200 | 单块字符上限（防超长事件撑爆上下文） |
| `candidates` | 128 | 传给后端的候选命中数 |
| `topK` | 15 | 最终返回条数上限 |
| `injectLimit` | 5 | `evidenceBlock` 注入的条数（通常比 `topK` 小） |
| `tokenBudget` | 2000 | 证据块 token 预算上限 |
| `indexVersion` | 1 | 索引版本，与嵌入模型、维度一起校验一致性 |
| `reranker` | `NoopReranker` | 重排器，缺省不重排 |
| `visibility` | `TenantTagPolicy` | 可见性策略 |

嵌入模型、维度或 `indexVersion` 与既有索引不一致时抛 `rag_index_stale`，需先
`clear()` 再重建。

## 删除与合规

| API | 语义 |
|-----|------|
| `forgetSession(sourceId, scope:)` | 删除单个会话的切片；租户不匹配抛 `rag_scope_denied` |
| `forgetScope(scope)` | 删除整个租户的切片；`principalId` 非空时显式拒绝 |
| `clear()` | 全量擦除：切片、向量、游标、遗忘集合与 meta，**不留墓碑** |
| `rebuild()` | 清空后按当前配置重建索引 |

**遗忘语义**：`forgetSession` / `forgetScope` 会把来源记入遗忘集合，该来源之后不再
被摄入（懒补齐、新增事件都不会让它复活）；`rebuild()` 会**保留遗忘集合**（清空前
捕获、重建后逐个恢复），因此换模型/切片参数升级不会复活已遗忘的来源。只有
`clear()` 才是全量擦除，遗忘集合一并清空。

## 边界与风险

- **dense-only，精确 token 弱**：纯稠密检索对精确标识符（错误码 / SKU / 法条号）
  召回弱，hybrid（稀疏 BM25 + 稠密）是后续项，当前未实现。
- **JSON 后端是逻辑隔离**：`JsonRagBackend` 单文件内多租户同存，靠 `tenantId` 与
  标签过滤隔离；需要**强隔离**时，每租户一个独立后端文件，或换外部向量库实现。
- **索引含原文**：切片把会话原文落盘，与会话日志处于同一暴露面；`RetrievalAudit`
  只记计数与耗时、不含正文，但索引文件本身需要同等级别的访问控制。
- **短会话收益低**：检索有固定的嵌入与过滤成本，会话极短时收益不抵开销，按需接线。

## 清理

`clear()` 是**损坏索引的恢复入口**：`JsonRagBackend` 遇到文件损坏抛
`rag_backend_broken` 且不会静默清空；此时直接 `clear()` 可在损坏文件上覆盖为空索引，
再 `rebuild()` 重新摄入。

# Changelog

## [0.16.0] — 2026-10-23

- 新增 `conatus_rag` 包：会话原文的 Raw-RAG 检索内核。
- 切分：`chunkEvents` 按字符窗口滑动切片，超长事件截断。
- 嵌入：`Embedder` 契约 + `OpenAiEmbedder`（OpenAI 兼容 `/embeddings` 端点）。
- 索引后端：`RagIndexBackend` 端口 + `InMemoryRagBackend` 与 `JsonRagBackend`
  （原子落盘，损坏时报 `rag_backend_broken`，`clear()` 为恢复入口）。
- 检索：`DenseRetriever` 嵌入 → 过滤 → 余弦 → 可选重排 → token 预算截断。
- 重排：`Reranker` 契约 + `NoopReranker` 与 `HttpReranker`（失败静默回退）。
- 可见性：`RagScope` / `TenantTagPolicy`，租户硬隔离 + `tenant:<id>` 自动标签 +
  标签交集过滤，空标签 fail closed。
- 服务装配：`provideRag`（`'rag'` 服务 + 自动注册 `rag_search` 工具，scope 为 null
  时 fail closed）；`RagSearchTool` 支持 `session_id` / `from` / `to` 收窄。
- Agent 接线：`RagService.evidenceBlock` 可注入 `provideAgentLoop` 的 `evidence`。
- 删除与合规：`forgetSession` / `forgetScope` / `clear` / `rebuild`，遗忘集合语义
  （`rebuild()` 保留墓碑，`clear()` 全量擦除）。

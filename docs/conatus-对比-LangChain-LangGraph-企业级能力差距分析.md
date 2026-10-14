# conatus 对比 LangChain / LangGraph：企业级能力差距分析

> 评估口径：把 conatus 当作「企业 agent 底座」。对标对象拆成四层——
> LangChain（集成与抽象）、LangGraph（编排运行时）、LangSmith（可观测与评测）、
> LangGraph Platform（部署平台）。
>
> 源码基线：`master` @ `8138a5e`，文档日期 2026-10-14。

## 结论摘要

- conatus 是**纯 Dart 库 / 嵌入式运行时**，不是平台。它把 agent 需要的进程内构件做得较完整，
  但没有可观测/评测的托管面，也没有部署层。
- 在「可逆效应 + 反应式组合 + 工具治理」这一层，conatus 有 LangChain/LangGraph 没有的原创实现，
  且质量扎实。
- 企业 agent 真正花钱的三块——**durable / 可恢复的执行图**、**可观测与评测的托管面**、
  **平台化的部署 / 权限 / 多租户**——conatus 要么只有接口没有实现，要么完全没有。
- 即便把部署与多租户整个排除、只做「单进程、单租户、嵌入式库」，仍然缺 **LangGraph 的图引擎 +
  checkpointer/HITL**，以及 **LangChain 的模型抽象 + RAG**。这两块是硬缺口，conatus 现有的
  Effect/Coeffect 模型与 MCP 策略遮不住。

## 1. 对标分层与 conatus 定位

| 层 | 对标 | conatus 现状 |
|---|---|---|
| 编排 / 运行时 | LangGraph | 固定 Agent Loop + 声明式 DAG 工作流；无状态图引擎 |
| 集成 / 抽象 | LangChain | 只有 OpenAI 兼容单一 wire；广度交给 MCP |
| 可观测 / 评测 | LangSmith | 进程内事件流 + 控制台打印 + 离线 span 推导 |
| 部署 / 平台 | LangGraph Platform | 无（无 server / API / auth / 多租户） |

## 2. conatus 的既有长处

列缺口之前先记长处，否则清单不公平。以下均为已实现：

- **效应 / 共效应核心**（`packages/conatus_core`）：`EffectScope` 按 LIFO 回滚，幂等、迟到登记安全、
  抗异常；`Reactor` 用「脏标记 + 重跑」在一次 `notify()` 内收敛依赖联动，无法收敛（循环依赖）
  抛 `StateError` 快速失败。这套时间/空间可组合性模型是对标对象没有的。
- **工具治理**：`Tool.riskLevel` + 审批门（默认阈值 `high`，`pathParams` 工具强制门控）
  （`packages/conatus_agent/lib/src/approval_gate.dart`、`approval.dart`）；
  `SubAgentPermission` 只能收紧不能放宽（`sub_agent_permission.dart`）；Plan Mode 期间禁止
  `medium` 以上工具（`plan_mode_default.dart`）。
- **凭据**：env / 内存 / 文件 / HashiCorp Vault KV v2 / AWS Secrets Manager 五源，
  统一脱敏边界（`packages/conatus_credentials/lib/src/`）。
- **LLM 韧性**：重试 + 指数退避 + jitter + 尊重 `Retry-After`，降级链 `FallbackLlm`
  （`packages/conatus_llm/lib/src/llm_retry.dart`、`llm_fallback.dart`）。
- **会话底座**：只追加事件日志 + `fork`/`replay`（`packages/conatus_foundation/lib/src/session.dart`、
  `session_log.dart`），JSONL 持久化（`session_persistence.dart`）。
- **秘密脱敏**：递归按敏感键名遮蔽，`toString()` 只含脱敏值
  （`packages/conatus_core/lib/src/redaction.dart`）。

## 3. 能力缺口

### 3.1 编排与执行引擎（对标 LangGraph，缺口最大）

全仓无 `StateGraph` / `addNode` / `addEdge` / 条件边 / `Pregel` 一类 API。控制流只有两种：
固定的有界循环（`packages/conatus_agent/lib/src/agent_loop.dart:211`，`for (step < maxSteps)`）
和纯 DAG 声明式工作流（`packages/conatus_workflow/lib/src/engine_impl.dart`）。

| 能力 | LangGraph | conatus |
|---|---|---|
| 节点 / 条件边 / 循环（回边） | 有 | 只有 DAG（`dependsOn`），无回边；循环只在 Agent 层手搓（reflection / maker-checker） |
| 动态 fan-out / map-reduce（`Send`） | 有 | 无；节点集定义期固定 |
| 状态 reducer / channel 合并 | 有 | 无；只有 `{{nodeId.path}}` 字符串插值 |
| `Command` / `goto` 动态跳转 | 有 | 无 |
| 子图（可组合 subgraph） | 有 | 只有 `SubWorkflowNode` 递归调用（`maxDepth` 默认 5） |
| thread-scoped checkpointer + 中途续跑 | 有 | 无；工作流状态在内存，`WorkflowStore` 只落地 `InMemoryWorkflowStore`（`packages/conatus_workflow/lib/src/store.dart`），`loadRun` 从不被调用 |
| time-travel（改状态重跑） | 有 | 只有日志 `fork`/`replay` + 按节点 `rerun`，不是图状态快照 |
| HITL interrupt/resume（可编辑中断点） | 有 | 只有阻塞式审批 + 节点边界 `pause` |
| 中间状态流（`astream_events` 级） | 有 | 只有 token 流 + 各包事件 `Stream` |
| 一轮内并行工具调用 | 有 | 无；工具串行 `await`（`agent_loop.dart:256`） |
| 任务队列 / 背压 / worker pool | 有 | 无；只有 `maxMembers=8`、`maxDepth=5` 一类硬上限 |
| 多 Agent 拓扑 supervisor / hierarchical / swarm | 有 | 只有 sequential / concurrent / group_chat / maker_checker（`packages/conatus_team/lib/src/patterns/`） |

**重启即丢**：恢复时未完成的活跃任务被统一置为失败，原因串为「进程重启，执行环境已丢失」
（`packages/conatus_tasks/lib/src/task.dart:18`）——这是仓库明确不声称跨进程可恢复的证据。

承载编排的三个包 `conatus_workflow`、`conatus_team`、`conatus_intent` 均自述**实验性**，
「请勿在生产环境依赖」。

### 3.2 持久化与状态

- 后端只有三档：内存、本地 JSONL（`~/.conatus`）、本地 JSON KV（`packages/conatus_foundation/lib/src/database.dart`、
  `database_json.dart`）。**无 Postgres / Redis / SQL / 对象存储**。
- seam 设计干净但无生产后端实现：`SessionPersistence`（`session_persistence.dart:15`）、
  `SessionLog`、`MemoryBackend`、`DatabaseBackend`、`WorkflowStore`。
- 无跨进程恢复、无事务、无二级索引、无 schema 迁移（版本号 ad-hoc，如 `kSnapshotVersion = 1`）。
- **无文件锁**：`Database` 整表覆盖、last-writer-wins，跨进程共享不安全。
- **无多租户原语**：session / memory / database 全局单例，无 `tenant` / `namespace` / `userId` 字段；
  隔离只能靠独立进程或独立 `CONATUS_HOME`。

### 3.3 记忆与检索（RAG）

- 长记忆 `MemoryStore` **是关键词 token overlap，不是语义检索**：`_score` 统计 token 交集，
  tie-break 取最新（`packages/conatus_foundation/lib/src/memory.dart:148`、`:166`）。单库、无 namespace。
- **几乎无 RAG**：无向量库（pgvector / Pinecone / Qdrant / Chroma / FAISS / Milvus / Weaviate 零集成）、
  无文档加载器、无文本切分器、无 retriever、无 hybrid / rerank、无引用溯源。
- embedding 能力只存在于**实验性** `conatus_intent`，且只是接口：
  `EmbeddingProvider`（`packages/conatus_intent/lib/src/embedding/embedding_provider.dart`）、
  `LocalEmbeddingProvider`（字符 n-gram 哈希，非语义）；`conatus_llm` 明确不提供 embedding。
- 这是**有意为之**（仓库内有「零代码 RAG」的表述），但对知识库场景就是硬缺口。

### 3.4 模型接入与抽象（对标 LangChain）

| 能力 | conatus |
|---|---|
| Provider 广度 | 只有 `OpenAiCompatibleProvider` 一种 wire（`packages/conatus_llm/lib/src/llm_openai.dart:585`）；包 README 自述「本包不含具体提供商」（`packages/conatus_llm/README.md:8`）。`conatus_code` 里的 anthropic / google 等只是把 baseUrl 指过去的**预设**，无原生 SDK、无 Bedrock / Vertex / Azure |
| 结构化输出 / JSON mode / schema 约束 | 无（全仓无 `response_format` / `json_schema`，只有零散手写 JSON 切分） |
| `tool_choice` 强制 | 无 |
| `parallel_tool_calls` 控制 | 无（且执行侧也是串行） |
| LCEL / Runnable 组合抽象 | 无；组合方式是 Context 服务 + provider 装饰器 |
| 输出解析器 + 解析失败重试 | 无 |
| 缓存层（LLM / 语义缓存） | 无；`context-cache` 只**度量**服务端前缀缓存命中（`packages/conatus_agent/lib/src/caching.dart`） |
| Embedding API | 无 |
| SaaS / DB / 云连接器 | 无；全部推给 MCP（`packages/conatus_mcp`，stdio / HTTP / SSE 三种传输） |
| 多模态 | 图片输入有；音频走独立 ASR/TTS 不进 LLM；视频/PDF 只有 capability 元数据 |
| 调用并发限流 | 无信号量 / rate limiter |

### 3.5 可观测与评测（对标 LangSmith 的库内一半）

- **可观测**：有完整事件词表与 `InMemoryTelemetry` / `ConsoleTelemetry`
  （`packages/conatus_agent/lib/src/telemetry.dart`），但 **OTLP / Prometheus / JSONL 导出器均未实现**
  （`packages/conatus_observability/README.md` 自述「按实现方案陆续补齐」）；无 trace UI、无存储、无采样。
- **评测**：`evaluation` 是本地循环 + **规则式 `bool` judge**（`packages/conatus_agent/lib/src/eval_types.dart:5`）；
  无 LLM-as-judge、无 dataset 版本化、无实验追踪；CI 不跑 eval。
- 对比 LangSmith：托管 trace store + UI + dataset + LLM-as-judge + 实验对比，conatus 一项没有。

### 3.6 内容安全

- 实现：凭据键名脱敏、工具风险分级与审批、子 Agent 权限收紧、Plan Mode 守卫。
- **缺**：content moderation、PII 检测/脱敏（现有脱敏只按凭据键名）、
  prompt-injection / jailbreak 防御、模型内容 allow / deny 列表。
  `content_classifier.dart` 服务的是**压缩策略**选择，不是内容审查。

### 3.7 部署与平台层

- **完全没有**：无 HTTP server / API、无 inbound webhook、无队列 worker、无 health check、
  无 Dockerfile / K8s / Terraform（全仓 `shelf` / `dart_frog` / `serverpod` / `http_server` 依赖为零）。
  `bin/` 只在子模块（`conatus_code` 是 CLI/TUI，不是服务）。
- **流式只在进程内**：`Stream<LlmStreamEvent>`，没有 over-HTTP 流。
- **auth / RBAC / SSO / 多租户 / 防篡改审计日志：全无**。唯一「权限」概念是进程内的
  `SubAgentPermission` 与工作流 `PermissionConstraint`（内存 `Set<String>?`）。
- 无水平扩展 / 无状态服务端 / 分布式协调。

### 3.8 成本

- 框架内 `cost.recorded` 事件被预算告警规则监听（`packages/conatus_alerting/lib/src/rules/default_rules.dart:55`、`:64`），
  但**没有任何包 emit 它**——规则实际是死的（除非应用自行接线）。
- 真实 `CostTracker` 在 `conatus_code` 子模块内，且未接线到该事件。
- 无跨会话/日聚合、无按租户归因、无成本看板。

## 4. 去掉平台层后的重排（单进程、单租户、嵌入式库口径）

把部署、Docker、多租户、auth/RBAC 整个排除后，对标收缩为
**LangChain（集成 + 抽象）+ LangGraph（编排引擎）+ LangSmith 的库内部分（事件 / eval）**。

### 仍然缺（纯库能力，躲不掉）

1. **编排引擎**（LangGraph 存在的全部理由）：条件边 / 循环、`Send` 动态 fan-out、
   状态 reducer、`Command`/`goto`、可组合 subgraph；**checkpointer 抽象 + thread state**；
   **time-travel**；**HITL interrupt/resume（可编辑中断点）**；中间状态流；
   **一轮内并行工具调用**。
2. **记忆 / RAG**：语义检索、embedding provider、向量库、retriever / splitter / loader / rerank / 引用。
3. **模型接入与抽象**：结构化输出（JSON mode + 解析重试）、`tool_choice`、
   LCEL/Runnable 式组合抽象、缓存层、embedding API、原生 provider SDK。
4. **单进程也需要、目前没有的可靠性原语**：并发限流 / 背压 / 任务队列、熔断器。
5. **库内可观测 / 评测**：真实 OTLP 等 exporter、LLM-as-judge、dataset。

### 可以放一放（被切掉的平台层）

- auth / RBAC / SSO / 审计日志
- HTTP server / API / over-HTTP 流式 / inbound webhook / queue worker / health check
- Docker / K8s / Terraform / 水平扩展
- 多租户隔离 / namespace / 按租户归因
- 成本看板 / 计费
- 托管 trace store / UI / 采样

### 一个纠缠点

**durable execution 横跨「库」与「平台」交界**：

- 属**库**：checkpointer 抽象、单进程（in-memory / SQLite）断点续跑、time-travel、interrupt/resume。
- 属**平台**：Postgres / Redis 后端、跨进程 / 跨机器恢复。

因此即便只做单进程、单租户、嵌入式库，第 1 项里的 checkpointer + interrupt/resume + 条件边 / 循环
仍然是必须补的能力——**只是可以不补它的分布式后端**。

## 5. 按设计选择、不算缺陷的差异

以下是对标路线差异，不是能力缺失，但会影响「适不适合企业」的判断：

1. **集成策略**：conatus 用 MCP 换生态广度，LangChain 用数百个集成包。短期是缺口，长期是取舍。
2. **语言生态**：Dart vs Python。企业 AI 基建（LangSmith、向量库 SDK、HF、Jupyter）绝大多数 Python 优先，
   Dart 会带来工具链与人才摩擦。
3. **分发方式**：git 源 + `publish_to: none`，不发布 pub.dev；下游若要自己发 pub.dev 会被 pub 拒绝
   git/path 依赖。
4. **同步模型**：`Context` 服务查找是同步的，重活放在 effect / dispose，与 Python 侧 `async everywhere`
   的习惯不同。

## 6. 补齐优先级

### 全量口径（要成为企业级平台）

- **P0**：durable checkpoint + 断点续跑（先补 `WorkflowStore` / `SessionPersistence` 的
  Postgres / Redis 实现）；真实 OTLP exporter；auth / RBAC / 多租户；内容 guardrail
  （moderation + PII + injection）。
- **P1**：结构化输出 + 解析重试；`tool_choice` + 并行工具调用；embedding provider + 一个向量库 +
  retriever；部署 server（HTTP + 流式 + 队列）。
- **P2**：状态图 / 条件边 / 循环（或至少给工作流补循环 + 动态 fan-out）；
  supervisor / hierarchical 拓扑转正；eval 平台化；熔断器与并发限流。

### 单进程嵌入式库口径（排除平台层）

- **P0**：状态图能力（条件边 + 循环）；checkpointer + interrupt-resume + time-travel；
  结构化输出（JSON mode + 解析重试）；并行工具调用。
- **P1**：embedding + 一个向量库 + retriever；OTLP exporter；LLM-as-judge + dataset；
  provider 原生 SDK（至少 Anthropic / Google）。
- **P2**：并发限流 / 队列；熔断器；supervisor / hierarchical 拓扑转正；`Send` 式动态 fan-out。

## 附录 A：证据索引

| 结论 | 证据 |
|---|---|
| 固定有界 Agent Loop | `packages/conatus_agent/lib/src/agent_loop.dart:211` |
| 一轮内工具串行执行 | `packages/conatus_agent/lib/src/agent_loop.dart:256`、`:341` |
| 工作流为 DAG、无状态图 | `packages/conatus_workflow/lib/src/engine_impl.dart` |
| 工作流 store 仅内存实现 | `packages/conatus_workflow/lib/src/store.dart:12`、`:39` |
| 重启丢弃活跃任务 | `packages/conatus_tasks/lib/src/task.dart:18`、`task_center.dart:67` |
| 长记忆为关键词匹配 | `packages/conatus_foundation/lib/src/memory.dart:148`、`:166` |
| embedding 仅实验性接口 | `packages/conatus_intent/lib/src/embedding/embedding_provider.dart` |
| 唯一 wire 为 OpenAI 兼容 | `packages/conatus_llm/lib/src/llm_openai.dart:585`、`packages/conatus_llm/README.md:8` |
| 无结构化输出 / tool_choice / 并行调用 | 全仓 grep `response_format` / `json_schema` / `tool_choice` / `parallel_tool_calls` 无命中 |
| 缓存只做度量 | `packages/conatus_agent/lib/src/caching.dart` |
| telemetry 仅内存 / 控制台实现 | `packages/conatus_agent/lib/src/telemetry.dart:52`、`:88` |
| observability exporter 未实现 | `packages/conatus_observability/README.md` |
| eval judge 为 bool 函数 | `packages/conatus_agent/lib/src/eval_types.dart:5` |
| 脱敏仅按凭据键名 | `packages/conatus_core/lib/src/redaction.dart:25`、`:59` |
| 无 server / 容器依赖 | 全仓 `pubspec.yaml` 无 `shelf` / `dart_frog` / `serverpod` / `http_server`；无 Dockerfile / `*.tf` |
| `cost.recorded` 无人 emit | `packages/conatus_alerting/lib/src/rules/default_rules.dart:55`、`:64`，全仓无 emit 点 |
| 凭据五源 | `packages/conatus_credentials/lib/src/` |
| 会话持久化 seam | `packages/conatus_foundation/lib/src/session_persistence.dart:15`、`:30` |

## 附录 B：文档 / 代码一致性备注

- `packages/conatus_observability/README.md` 声明该包「不进 `conatus` 伞包」，
  但 `lib/conatus.dart:56` 实际导出了 `conatus_observability`。二者不一致，以代码为准。
- `session-budget` / `daily-budget` 告警规则依赖 `cost.recorded`，而该事件无 emit 点——
  规则默认不生效。

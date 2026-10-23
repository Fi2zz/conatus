# 《Harness Engineering》论文解读 × conatus 关联分析

> 日期：2026-10-13。论文：Paul Barbaste 等（Inclusive Brains / Wavestone AI Lab，2026 年 7 月）。
> 原文：`~/Downloads/Harness Engineering - 原文.pdf`（未入库）。本文是论文精读笔记与 conatus 项目的关联分析。

## 一、论文是什么

对 11 个生产级 coding agent 系统（Claude Code、Codex、OpenHands、Aider、Gemini CLI、Mistral Vibe、Hermes、Pi、OpenCode、OpenClaw、Mini-SWE-Agent）+ 1 个 meta-harness（Omnigent）做**源码级解剖**，约 400 万行代码，并与 2026 年 4 月版做纵向对比。

核心命题：**"An agent is a model plus a harness. The harness is everything except the model."** Harness = 把 LLM 耦合到世界的运行时：loop、工具、上下文、安全控制、编排、扩展面。论文给出 harness 的"规范解剖"——七个子系统（Agent loop / LLM 集成 / 工具与行动 / 记忆与上下文 / 安全与权限 / 编排 / 可扩展性），并断言 harness 已完成"从工具到平台"的转变（the platform turn）。

## 二、最重要的关联：conatus 横跨论文划的"框架 / harness"界线

论文 §2.2 的关键区分：

> "A framework is a library the developer imports to build an agent; a harness is a runtime the developer works inside of."

conatus 恰好横跨这条线的两侧，对应论文 §14.2 描述的 **harness–framework merger** 趋势：

- **conatus（本仓库）= 框架侧**：开发者 import 的库（`import 'package:conatus/conatus.dart'`），提供 loop / tools / skills / sub-agents / sessions / MCP 的全部构件——论文 Table 15 里 Claude Agent SDK、openhands-sdk、LangChain Deep Agents 所在的格子。
- **conatus_code / nava（子模块）= harness 侧**：开发者"在其中工作"的终端运行时产品——正是论文 11 个解剖对象（Claude Code、Codex……）所在的品类。

也就是说，**这篇论文是 conatus_code 所在赛道的第一份系统性第三方源码审计报告，也是 conatus 框架层设计的一面镜子**：论文从 11 个独立实现中归纳出的收敛结论，可以直接用来校验我们的架构选择。

## 三、七子系统逐条映射：conatus 的位置

| 论文子系统 | 论文归纳的收敛形态 | conatus 对应实现 | 评估 |
|---|---|---|---|
| **Agent loop** (§6) | 全是 ReAct 变体；生产系统组合原语（plan-execute 嫁接 ReAct、retry、reflection）；stop 条件与失败恢复是 loop 的职责 | `conatus_agent`：Agent Loop + plan mode + reflection + recovery | ✅ 对齐。plan mode（plan-execute 嫁接）正是四家 provider-native 系统的收敛形态 |
| **LLM 集成** (§7) | 五种 provider 策略；多 provider 系统靠"集中支付每厂商条件代码成本"也能吃到原生优化；prompt 高度模块化分层 | `conatus_llm`：豆包/DeepSeek 双形态（chat/responses）+ FallbackLlm 回退链；`conatus_foundation` system-prompt | ⚠️ 部分对齐。provider 面较窄，缺 prompt caching 边界管理、模型路由、每模型 quirk 层 |
| **Tools & actions** (§8) | 工具数量 1→109 光谱；>15 个工具时 deferred loading 成扩散模式（prompt token 减 ~40%）；文件编辑契约匹配模型档位；执行沙箱是最贵的能力 | `Tool` 基类 + `ctx.tools` 管线（校验→守卫→中间件→执行）；`riskLevel` + `guardRisk`；`shell`/`fs` 能力缝 | ✅ 管线架构对齐；⚠️ 无 deferred tool loading；沙箱靠能力缝留给部署方（论文视之为合理选择：Hermes/OpenCode 也是零 OS 隔离的大系统） |
| **Memory & context** (§9) | threshold compaction 是 7/11 系统的事实标准；持久记忆取代 compaction 成为新前线；"谁写记忆、谁审记忆"四种治理模型 | `conatus_compaction`：滚动摘要 + `compaction/*` 日志事件；`conatus_foundation` memory | ✅ threshold compaction 对齐；⚠️ 持久记忆治理（agent 维护/人类门控）尚未涉及 |
| **Safety & permissions** (§10) | 收敛形态：静态规则→LLM 分类器→交互/OS 兜底；policy-as-code；YOLO 也要有政策地板 | `approval` 审批链 + `AskUserApproval`（超时视为拒绝，fail-closed）+ 工具风险分级（未知风险缺省 high，fail-closed） | ✅ fail-closed 哲学与论文安全原则一致；⚠️ 层级数少于 Codex 四层栈，无 LLM 审批分类器、无 policy-as-code 文件 |
| **Orchestration** (§11) | coordinator-worker 在 8 处独立涌现（"convergent evolution 的强证据"）；9 个多 agent 系统中 8 个用 in-process 原语 | `conatus_agent` sub-agent；`conatus_tasks` 任务树；`conatus_team`（实验性多智能体） | ✅ 层级 + in-process 方向与主流收敛一致 |
| **Extensibility** (§12) | **skills 已超越 MCP**（9/11 vs 8/11）；SKILL.md + YAML frontmatter 实质统一；deferred loading 主导（9 家中 8 家只急切加载元数据）；条件激活是最有趣的变体 | `conatus_skill`：SKILL.md 发现 + 目录注入 + `skill` 工具；`conatus_mcp`：stdio/HTTP/SSE 三传输 | ✅ 双标准齐备，与论文"skills 管能力模板、MCP 管外部集成"的建议分工完全一致 |

## 四、论文的两个"twin absences"恰好印证了 conatus 的技术路线

§13.2 的最强实证发现：**11 个系统、~400 万行代码，零 agentic 框架依赖、零代码 RAG**。

- "Every loop is hand-rolled in the host language's native primitives" —— conatus 正是纯 Dart 手写，`conatus_core` 零运行时依赖，无框架包袱。论文认为这 corroborate 了"生产 agent 与通用 LLM 应用运行在不同的复杂度预算上：可调试的手写代码胜过可复用抽象"。
- 无代码 RAG：代码有稠密确定性结构（路径/LSP/tree-sitter），embedding 天然过期。conatus 未建向量检索层，路线正确。

## 五、conatus 超出论文语料库的独特点

论文 11 个系统的 loop 全部是"hand-rolled while + 注册表"，没有任何一个有**形式化的效应模型**。conatus 的底层是时空可组合性范式：

- **可逆效应（时间可组合性）**：EffectScope LIFO 回滚、幂等、抗异常——论文语料库里最接近的只有 Mistral Vibe 的 RewindManager、OpenCode 的 shadow-git 检查点这类**特设（ad-hoc）机制**，而 conatus 把它提升为一等运行时语义（`tool/verify_reversibility.sh` 甚至做变异测试）。
- **反应式共效应（空间可组合性）**：`ctx.inject` 依赖声明 + Reactor 脏标记收敛——论文语料库中无对应物；最接近的是"条件激活 skills"（OpenClaw 的 requires、CC 的 paths frontmatter），但那只是扩展层的加载门控，不是通用运行时原语。
- **上下文树**：服务沿父链可见、父释放级联子树——论文中的 context forking（Claude Code 六维 fork）是手工枚举的，conatus 是结构化树语义。

**用论文的话说：语料库系统的差异化投入都在 "safety, recovery, cost management, extensibility, platform surfaces"，而 conatus 的差异化投入在更底层——组合性语义本身。** 这是论文框架（七子系统解剖）覆盖不到的维度，也是 conatus 相对所有 11 个系统的理论差异点。

## 六、论文对 conatus 可直接行动的建议（按 §16 十八条映射）

已对齐、无需动作：

- ✅ 不用 agentic 框架（建议 15 的 anti-pattern，我们天然满足）
- ✅ 不建代码 RAG（建议 16）
- ✅ skills + MCP 双轨分工（建议 14）
- ✅ AGENTS.md 分层上下文自动发现（建议 6，本仓库自身就在实践）

值得评估的候选改进：

1. **Deferred tool/skill loading**（建议 4）：conatus 工具面扩大后，可参考 Claude Code 的 ToolSearchTool / Hermes 的三桥工具塌缩模式（schema 超上下文窗口 10% 时塌缩为 tool_search/tool_describe/tool_call）。
2. **审批层加深**（建议 9/10/11）：从单层 approval 链走向"静态规则→LLM 分类器→交互"三层；政策编为数据文件（policy-as-code）而非命令式代码；若引入 auto-approve 档位，保留 Hermes 式"YOLO 打不穿的政策地板"（12 条 hardline 模式在 --yolo 下依然生效，绕过旗标在模块 import 时冻结）。
3. **持久记忆治理**（§9.6）：论文称 "persistent memory has replaced compaction as the frontier of context engineering"，可评估 Codex 式 agent 维护记忆（两阶段管线 + git 基线 + 沙箱化审查子代理）或 Gemini 式人类门控 inbox。
4. **ACP server**（建议 13）：论文称 ACP 一次买到"编辑器、托管 harness、meta-orchestrator"三类受众（6/11 已发布）；conatus_code/nava 若发布 ACP server 即可被 Omnigent 类 meta-harness 编排（其 23 个适配器名单里已有 Kimi）。
5. **会话树/谱系压缩**（§9.5 Hermes Lineage Compaction、Pi session tree）：压缩不改写 transcript 而是结束会话、轮换到 parent_session_id 链接的子会话，"no history is ever destroyed"——与 conatus 的 Context 树语义天然亲和，可能是"范式优势兑现为产品特性"的最低垂果实。
6. **Hooks/事件总线**（§14.1 Signal 2）：9/11 系统已有，是扩展基底；conatus 的反应式共效应可以比手工 hook 列表表达得更有原则性。

## 七、一句话总结

这篇论文是对 conatus_code/nava 所在赛道（coding agent harness）的第一份系统解剖报告：它的七子系统框架可以用来给 conatus 做架构体检（大部分维度已对齐主流收敛），它的 twin absences 印证了我们的技术路线，而 conatus 的可逆效应/反应式共效应底层是论文全部 11 个语料系统都不具备的差异点。论文 §16 的 18 条建议可直接作为 conatus 后续演进的 checklist。

---

> 相关：HarnessPro（arXiv:2610.26770）的移植实现记录见
> [`harnesspro-成本感知移植-实现记录.md`](harnesspro-成本感知移植-实现记录.md)。

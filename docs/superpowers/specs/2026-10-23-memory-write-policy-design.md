# conatus_memory 设计：记忆写入策略能力

- 日期：2026-10-23
- 状态：已实现（库 + nava / example 装配）
- 相关：`conatus_foundation` 的 `MemoryStore` / `MemoryBackend`、`conatus_agent` 的
  `AgentTurnTracker`、`conatus_tasks` 的轮次追踪、`conatus_intent` 的
  `EmbeddingProvider` 四通道先例
- 来源：[MemAgent: Learning to Manage Heterogeneous Memory Providers for LLM Agents](https://arxiv.org/abs/2609.32521)（arXiv:2609.32521）
- 论文精读：[docs/MemAgent-论文精读与记忆策略取舍.md](../MemAgent-论文精读与记忆策略取舍.md)

## 1. 背景

`AgentLoop._finish` 原先每轮无条件写入一条 `用户：…\n助手：…` 到 `MemoryStore`。
这是「全量存储」策略，而 MemAgent 的消融给出了它的代价：GAIA 上
`Begin + In + 全量存` 65.5，`选择性存` 69.7，**−4.2pp**；其失败分析里 14% 的
失败是「注入记忆反而拖累了原本能解的题」。

本机真实数据（`~/.nava/projects/*/memory.json` + `sessions/*.jsonl`）：

| 指标 | 实测 |
|------|------|
| 会话 / 用户轮次 / 项目 | 11 / 12 / 6 |
| 长期记忆条目 | 9 |
| 条目长度 < 60 字符 | **7/9**（中位 58，最短 19） |
| 寒暄类条目（`hi` / `hello`） | 6/9 |
| 重复条目 | 1/9 |
| 标签 | 100% `conversation` |

结论：**我们的问题在「写什么」，不在「怎么找」。** 语料里几乎没有值得被语义召回
的内容，此时引入 embedding 的收益上限接近零（详见 §8）。

## 2. 目标与非目标

### 目标

1. 一轮结束后按可替换规则判定是否保留，写入正文可被规整（截断）。
2. 能力以**独立包**接入：`agent` 与 `foundation` 都不承担保留策略。
3. 多个能力（任务追踪、记忆写入）共存，互不知情、无装配顺序依赖。
4. 记忆写入失败不影响轮次结果（fail-open）。
5. 未装配该能力时行为明确：不写（而不是隐式沿用旧策略）。

### 非目标

- 不做召回侧（Begin 阶段的阈值 / 弃权 / 多 provider 路由）。
- 不引入 embedding、LLM 摘要、图记忆（见 §8 的判定与触发条件）。
- 不把 `MemoryStore` 改成多 provider 注册表；它是存储机制，不是策略层。

## 3. 为什么是独立包：被否的四种位置

| 方案 | 否决原因 |
|------|----------|
| 策略放 `foundation` 的 `MemoryStore` 槽位 | 产品级规则（中文寒暄表、长度阈值）属于产品判断，不该由基础设施强制所有消费方继承 |
| 策略放 `agent` 的字段 | 把「保留策略」重新耦合进 Agent Loop，与「能力化」相悖 |
| 新包 + 装饰 `'memory'` 服务 | `remember` 返回非空 `MemoryEntry`，无法表达「拒绝」，只能返回假条目或抛异常，语义脏 |
| 新包 + `Session.onEvent` 订阅 | 更纯，但写入不 `await`、无会话时不写、轮次结束只能靠事件推断，精度不够 |
| **新包 + 复用 `AgentTurnTracker`** | 采纳：零 foundation 改动、零新增接口、语义精确 |

关键结论：**能力必须有钩子，钩子必须是多播的。** 原 `AgentLoop.turnTracker` 是
单槽字段 + `identical` 判等清理，这是「单消费者」假设；出现第二个能力时必然冲突，
而链式包装又会引入「包知道包存在」和挂载顺序依赖。

## 4. 架构

```
conatus_memory ──┐
conatus_tasks  ──┼──▶ conatus_agent ──▶ conatus_foundation ──▶ conatus_core
                 │        （只提供 addTurnTracker 多播）
                 └──▶ conatus_foundation（MemoryStore）
```

| 组件 | 职责 |
|------|------|
| `MemoryWritePolicy` | 接口：输入 `userInput` / `reply` / `existing`，产出 `MemoryWriteDecision` |
| `PolicyMemoryWritePolicy` | 内置规则实现，阈值可覆盖、寒暄词表可替换 |
| `MemoryRecorder` | 实现 `AgentTurnTracker`；缓存本轮输入，结束时判定并写入 |
| `provideMemoryRecorder(ctx)` | 经 `ctx.inject(['agentLoop'])` 挂载，`Disposer` 随上下文释放摘除 |
| `MemoryStore` | 存储机制（不动） |

### 多播契约

- 顺序 = 注册顺序；`addTurnTracker` 返回幂等 `Disposer`。
- 单个钩子抛错隔离为遥测事件 `agent.tracker.failed`，不影响其他钩子与当轮结果。
- `endTurn` 同时服务成功与失败路径：失败轮次收到 `endTurn(error: …)`。

```dart
// 两个能力各自接入，谁也不知道谁
ctx.inject(['agentLoop'], (child) {
  child.effect(() => child.require<AgentLoop>('agentLoop').addTurnTracker(recording));
});
```

## 5. 默认规则（`PolicyMemoryWritePolicy`）

按顺序判定，命中即停：

| 顺序 | 规则 | 判定 |
|------|------|------|
| 1 | 回复为空 | `emptyReply` |
| 2 | 输入归一化后命中寒暄 / 确认词表 | `greeting` |
| 3 | 回复短于 `minReplyChars`（默认 12） | `shortReply` |
| 4 | 与已有条目字符 bigram Jaccard ≥ 0.6 | `duplicate` |
| 5 | 其余写入，正文截断到 600 字符 | `store` |

写入正文固定两行 `用户：…\n助手：…`，标签 `conversation`。判定原因进入
`MemoryWriteVerdict`，供埋点与测试使用；自定义策略可返回 `rejected`。

用上述规则回放现有 9 条真实记忆：**8 条拒绝、1 条保留**（寒暄 6、短回复 1、
重复 1）。该分布已固化为等价 fixture，阈值改动会立刻触发测试。

## 6. 失败语义

| 场景 | 行为 | 方向 |
|------|------|------|
| 轮次失败（`error` 非空） | 不写 | fail-closed |
| 未开始轮次就结束 | 不写 | fail-closed |
| 策略判定为不写 | 不写，`onStore` 仍收到原因 | fail-closed |
| 存储后端抛错 | 吞掉，轮次照常成功 | **fail-open** |
| 单个 tracker 抛错 | 隔离为 `agent.tracker.failed` | fail-open |

两条相反方向的失败策略必须同时存在：**能力失败不能拖垮主体，脏数据不能入库。**

## 7. 验证

| 层级 | 用例 | 结果 |
|------|------|------|
| 契约 | 两个 tracker 顺序、`Disposer` 幂等、单钩子抛错隔离、失败轮 `endTurn(error)` | 4/4 |
| 策略 | 空回复 / 短回复边界 / 寒暄 / 近重复 / 大小写变体 / 600 截断 | 7/7 |
| 记录器 | 正常写 / 失败不写 / 短回复不写 / 存储失败不外抛 / 连续重复只写一条 / `onStore` / 端到端装配 | 9/9 |
| 回归 | 27 个包 `dart test`、根测试 + 集成测试、`dart analyze --fatal-infos` | 全绿 |
| 可逆性 | `tool/verify_reversibility.sh`（7 变异体） | 全部杀死 |

探针（`dart run tool/memory_probe.dart`）在真实数据上的当前基线：

```
queries 12 · keyword fired 92% · recall MISS 0% (95% upper 24%)
weak 0 · mean injected 1.6 条 / 129 字符
```

`MISS` 定义为「关键词未触发，但存在字符 bigram 余弦 ≥ 0.45 的条目」——近似
embedding 能救回的那部分。样本仅 12 条，只能作基线，不能作结论。

## 8. 未做与后续

### 1. 召回侧（Begin）

`buildSystemText` 里的 `memory.recall(...)` 仍然无条件注入前 5 条。MemAgent 的
失败分析显示 14% 的失败来自「强制注入」，且其 Begin **没有弃权选项**——这是论文
本身的设计缺口。下一步应给读路径同等的阈值 + 弃权能力，并同步补
`memory/recall` 埋点。

### 2. 为什么不引入 embedding

| 通道 | 代价 | 判定 |
|------|------|------|
| 本地真模型（ONNX/tflite） | 平台绑定、二进制体积、冷启动 | 否 |
| 远程 embedding API | 内容出境、可用性依赖、费用 | 默认否，仅显式 opt-in |
| 本地纯 Dart 哈希 | 只认字形，相对现有中文二元组几乎无增益 | 否 |
| 预计算嵌入 | 适合固定语料（技能 / 文档） | 触发条件满足时再评估 |

统计功效：判定 MISS 率 ±10pp 需要约 **81 次真实查询**（现有 12 次）；检测端到端
**1pp** 收益需要约 **33,000 任务/组**。也就是说，0–1pp 的收益不仅小，而且工程上
不可测。

重新评估的触发条件：单项目记忆 > 200 条、MISS 率 > 30%（≥ 81 次查询）、出现跨
语言 / 同义词主导的记忆、或出现固定语料场景。

### 3. 其他

- 多 provider 注册表与路由（Begin 阶段从多个记忆来源中选一个）。
- LLM 摘要式写入：可替换 `MemoryWritePolicy` 实现，`agent` 与存储机制都不用动。
- InsightGraph 的边权自适应（`(n, k)` 的 Beta 平滑）可平移到条目级排序，替换
  `MemoryStore` 现在的 `createdAt` 平局规则。

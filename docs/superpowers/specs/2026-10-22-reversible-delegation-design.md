# 可逆委派（Reversible Delegation）：把跨 Agent 委派当债务结算

> 日期：2026-10-22 · 状态：设计已批准，待评审
>
> 定位：**独立项目的设计文档**，不在 conatus 内实现。conatus 只作为语义参照与
> 参考实现的候选底座（`EffectScope` 的 LIFO 撤销、`Context` 父子树、能力缝）。
>
> 触发来源：`docs/多Agent拆分与A2A协作-小红书笔记总结.md`。笔记解决「怎么拆」，
> 本文只解决「拆完之后，节点之间怎么交接」。

---

## 0. 摘要

当前多 Agent 系统的失败语义只有一种：**终止**。任务失败就 `failed`，然后没人负责
撤回已经发生的副作用。本文主张，跨 Agent 委派的正确模型不是函数调用，而是**债务**：

> 每一次委派都产生一笔需要结算的债务；债务不能被静默消灭，只能被吸收、补偿或升级给人类。

围绕这句话，本文给出五条规范律、三个数据结构、一个结算状态机、一个补偿承接模型，
以及到 A2A / MCP 的最小映射。核心的新颖点不是「支持撤销」——Saga 早有之——而是：

1. **不可逆性是一种需要预算和授权的资源**，必须先买票后上车（L2）；
2. **可逆性是委派属性，不是工具属性**，因此能力卡（agent card）不足以决定授权；
3. **补偿能力必须在委派发起时立项、定价、指定承接人**，不能等失败后再去求人。

本文明确写出可证伪条件：若某个领域不存在不可逆效应，本规范应退化为「租约 + 终态
完备」，此时若仍需要完整的回执体系，说明我们高估了问题。

---

## 1. 问题、术语与非目标

### 1.1 问题

一个 Agent 把子任务交给另一个 Agent 之后，主 Agent 只知道两件事：对方说完成了，
或者对方没完成。它不知道：

- 对方在完成过程中对外部世界做了什么；
- 这些副作用现在还能不能撤；
- 对方死了以后，这些副作用归谁；
- 「完成了一半」和「失败了」有什么区别。

现有协议把这些问题留给应用层，应用层则普遍选择不处理——因为处理它需要跨进程的
补偿语义，而没有人愿意为一条失败路径写第二套系统。

### 1.2 术语

| 术语 | 含义 |
|---|---|
| **Principal** | 发起委派、并为该委派承担债务归属的账户。可以是 Agent，也可以是人类 |
| **Worker** | 接受并执行委派的 Agent |
| **Steward** | 承接补偿执行的第三方账户（通常是兄弟 Agent 或人类） |
| **Delegation** | 一次有 id、范围、预算、租约、围栏的委派 |
| **Effect** | Worker 对外部世界造成的、可被观察到的变化 |
| **Receipt** | 一份效应的凭证，含类别、目标、证明、所属授权 |
| **Debt** | 尚未被吸收或补偿的效应总和 |
| **Grant** | 一次性、可计数、不可复制的授权凭据 |
| **Fence** | 单调递增的围栏号，用于拒绝迟到的效应 |
| **Lease** | 租约，带到期时间与续期义务 |

### 1.3 非目标

- **不解决「该不该拆」**。拆分判据（路径可预知性、工具数、Prompt 长度）是另一个命题，
  本文假定拆分已经发生。
- **不解决模型质量**。回执证明「发生过」，不证明「做对了」。
- **不做跨组织支付与清结算**。本文的「债务」是语义债务，不是金融债务。
- **不引入共识协议**。账本权威属于 Principal，不需要多副本一致。
- **不定义新的传输层**。所有消息都可以装在现有 A2A / MCP / HTTP 里。

---

## 2. 前置假设 A0：效应必须被中介

这是全文唯一的建筑学前提，也是最容易被攻击的地方。

> **A0**：Worker 不得绕过协议直接触碰世界。任何有外部可见后果的操作，都必须经过
> 一条 Principal 可验证的通道（工具、能力缝、代理网关），并在通道上产生回执。

若 Worker 可以直连数据库、直接发邮件、直接调用未注册的 HTTP 接口，那么「没有回执」
与「没有发生」不可区分，本规范的任何断言都不成立。

A0 不是「最佳实践」，是**合规声明的一部分**。规范要求每个部署提供两项审计：

1. **中介完整性审计**：枚举 Worker 可达的所有对外通道，证明它们都在账本覆盖范围内；
2. **外部对账（reconciliation）**：在外部世界一侧（邮件网关、支付流水、文件系统快照）
   保留独立审计源，按周期与账本对账。对不上的效应称为**未对账效应**，一律计入债务。

对账机制是 A0 的兜底：它不能阻止绕过，但能让绕过在下一个对账周期暴露。这也意味着
本规范的安全性不是「无法违反」，而是「违反必留痕」。

---

## 3. 五条律

以下五条是规范性正文。每条按「陈述 → 禁止什么 → 由什么机制强制 → 如何被检测」组织。
注意最后一项：**规范不假装能阻止恶意 Worker，只保证恶意可被检测并计入债务。**

### L1 债务守恒

> 对任意委派 D，D 产生且未结算的每一份效应，在任意时刻必须恰好归属一个活跃账户。
> 账户转移只有一条路径：worker → principal（委派结束或死亡）→ steward（补偿）→
> human（升级）。每次转移必须留下 SettlementRecord。

**禁止**：孤儿效应；通过「再外包一层」把债务甩给不可追溯的下游。
**机制**：委派树的每个节点持有其子树的债务汇总；父节点在子节点死亡时自动继承。
**检测**：账本总量不变式（见附录 C 的证明草图）：
`debt(root) = Σ effects − Σ accepted − Σ compensated`。

### L2 授权线性

> 一份 Grant 只能被消费一次（`max_uses` 显式，缺省 1），不可复制、不可转授；
> 未消费必须在结算时归还。消费与归还都写回执。**不可逆效应没有对应 Grant 时，
> 协议拒绝执行。**

**禁止**：用「事后补偿」为不可逆操作开脱；把同一份授权复制给多个 Worker；
授权随委派无限向下传递。
**机制**：Grant 是线性凭证，消费即销毁；Principal 侧维护单调计数器防重放。
**检测**：对账时检查 `consumed_count ≤ max_uses`；超发即判定账本损坏。

### L3 结算完备

> 每次委派必须且只能以 `accepted` / `compensated` / `abandoned` / `expired` 之一
> 收口，且必须附 SettlementRecord。收到 `done` 但没有回执的，一律视为 `failed`；
> 收到回执但找不到对应 Grant 或补偿计划的，记为**非法效应**，仍然计入债务。

**禁止**：静默结束；把「模型说完成了」当作完成；用异常退出代替结算。
**机制**：状态机没有「直接结束」的边；`done` 只是一次提议，不是终态。
**检测**：任何没有 SettlementRecord 的委派在账本上保持 open，无法被根任务闭合。

### L4 单调围栏

> 每条委派链维护单调递增的 Fence，随重新委派与租约续期递增。任何效应的 Fence
> 小于当前已知 Fence 时，不得被接受，只能作为**过期效应**计入待补偿。租约已过期的
> Worker 造成的效应，即使物理上已经发生，也视为过期。

**禁止**：僵尸 Worker 在租约失效后写入；网络分区恢复后的迟到提交覆盖新状态。
**机制**：Fence 由 Principal 单调分配；所有写操作带 Fence 并做比较。
**检测**：账本拒绝 `fence < current` 的回执，并把它转成 debt 而不是丢弃。

### L5 可追溯至人

> 每个根委派必须在发起时绑定一个**可解析的人类责任人**（稳定标识 + 可达通知通道）。
> 解析不到，委派在发起时即被拒绝。债务升级路径的终点必须是人，不能是另一个 Agent。

**禁止**：Agent 之间无限互相升级；受监管场景里「系统自动处理了」成为最终答复。
**机制**：根委派创建时做责任人解析；升级链的最后一步只能是 human 账户。
**检测**：任何 open 债务没有 human owner 即为规范违反；根任务不得标记闭合。

### 3.1 推论

- **P1 可逆性是委派属性，不是工具属性。** 同一个 `send_email`，在「保存草稿」的委派里
  是 R 类，在「通知客户」的委派里是 I 类。授权必须跟着 envelope 走。
  → 这直接解释了为什么 agent card 不够：card 描述能力，描述不了**这一次**允不允许
  造成不可逆后果。
- **P2 债务不可通过委派转嫁。** 委派只转移账户，不消灭债务。所以「无限外包」在账本
  上表现为一条不断变长的债务链，而不是一笔勾销。
- **P3 结算开销上界为 O(#scope + #I)**，而非 O(#effect)。前提是采用 scope 级回执
  （见 4.2）。这是本规范能否实用的生死线。
- **P4 若域内不存在 I 类效应，本规范退化为「租约 + 终态完备 + 围栏」**，实现成本接近
  零。此时 L2 不产生任何额外往返。

---

## 4. 数据结构

### 4.1 DelegationEnvelope

跨边界唯一的载体。所有字段都必须可序列化、可签名、可独立验证。

```json
{
  "rd": "1.0",
  "delegation_id": "d-7f3a",
  "parent_id": "d-7f39",
  "chain": ["d-root", "d-7f39"],
  "from": {"principal": "agent://triage", "card_digest": "sha256:aa.."},
  "to":   {"principal": "agent://billing", "card_digest": "sha256:bb.."},
  "intent": "查询账单并解释本期异常",
  "input": {"handle": "q://01J...", "digest": "sha256:cc.."},
  "effect_policy": {
    "allow": ["R", "C", "I"],
    "grants": [
      {"grant_id": "g-01", "class": "I", "selector": "tool:send_email",
       "max_uses": 1, "expires": "2026-10-22T12:10:00Z"}
    ],
    "irreversible_budget": {"total": 2, "remaining": 2}
  },
  "budget": {"tokens": 20000, "tool_calls": 12, "wall_ms": 60000, "money_usd": 0},
  "deadline": "2026-10-22T12:10:00Z",
  "lease": {"id": "l-01", "expires_at": "2026-10-22T11:55:00Z",
            "renew_by": "2026-10-22T11:50:00Z"},
  "fence": 7,
  "settlement": {
    "steward": "agent://steward-1",
    "compensation_budget": {"tokens": 5000, "wall_ms": 30000},
    "human_ack": "on_debt"
  },
  "nonce": "01J...",
  "sig": "ed25519:..."
}
```

设计要点：

- `input` 是**句柄**不是正文。正文可以很大、可能带毒，见 6.4 的隔离建议。
- `effect_policy.allow` 是类别白名单，不是工具白名单。工具白名单解决「能不能用」，
  类别白名单解决「能不能造成不可撤销的后果」。
- `settlement` 在**发起时**就要有 steward 与补偿预算。这是 6.3「补偿预算前置」的落点。
- `chain` 用于检测循环委派与深度爆炸；超过实现上限直接拒绝。

### 4.2 EffectReceipt

```json
{
  "receipt_id": "r-91",
  "delegation_id": "d-7f3a",
  "effect": "tool:send_email",
  "class": "I",
  "target": "customer:1234",
  "grant_id": "g-01",
  "fence": 7,
  "at": "2026-10-22T11:41:03Z",
  "proof": {"kind": "grant_consumption", "digest": "sha256:dd.."},
  "scope_id": "s-3"
}
```

三类效应，三种证明形态：

| 类别 | 定义 | 证明形态 | 写账时机 |
|---|---|---|---|
| **R 可逆** | 存在确定性逆操作（快照、临时文件、未提交事务） | `snapshot`：前像/后像哈希 + 快照定位符 | 批量后写 |
| **C 可补偿** | 无逆操作，但存在语义补偿（退款、撤回、更正通知） | `plan`：补偿计划 id + 预算预留 | 批量后写 |
| **I 不可逆** | 无逆操作且无可靠补偿（物理动作、无备份删除、对外披露） | `grant_consumption`：授权消费凭证 | **预写** |

写账时机是硬要求：I 类必须**先消费 Grant 并落账，再执行效应**（write-ahead）。
顺序反了就会出现「效应发生了但账上没有」，这正是 L1 要禁止的孤儿。预写分两步：
`intent`（消费 Grant）与 `commit`（效应确认）；两步之间死亡由外部对账裁决，Grant 的
退还必须幂等。R/C 类允许按 `scope_id` 批量后写，批量窗口内死亡产生的未知债务同样由
外部对账兜底。

**scope 级回执**：一个 scope 内同类别、同工具的连续效应可以合并为一条回执，附带
计数与前像/后像摘要。这把开销从 O(effect) 压到 O(scope)，是 P3 的实现基础。

### 4.3 SettlementRecord 与 DebtEntry

```json
{
  "delegation_id": "d-7f3a",
  "state": "accepted",
  "outcome": "success",
  "receipts": ["r-91", "r-92"],
  "debts": [
    {"debt_id": "x-1", "class": "I", "owner": "agent://billing",
     "human": "human:alice", "compensation_plan": null,
     "due": "2026-10-23T00:00:00Z"}
  ],
  "continuation": null,
  "fence": 8,
  "sig": "ed25519:..."
}
```

- `state=accepted` + 非空 `debts` 是合法的，叫 **accepted_with_debt**。债务进台账，
  不消失，但不阻塞下游。
- `continuation` 只出现在未完成结算里：它描述还缺哪一片工作、需要什么授权，
  用于只重跑缺失部分，而不是整段重来。
- 账本只追加，不修改。任何修正都是新记录 + `supersedes` 指向旧记录。

---

## 5. 结算状态机

```
offered ──accept──▶ leased ──first effect──▶ working
   │                  │                        │
   │ reject           │ lease expired          │ submit / partial
   ▼                  ▼                        ▼
abandoned          expired              settle_offered
                                              │
                        ┌─────────────────────┼─────────────────────┐
                        │ validate ok         │ validate fail       │ retry
                        ▼                     ▼                     ▼
                    accepted           compensating            leased (fence++)
                                              │
                              ┌───────────────┴───────────────┐
                              │ compensate ok                 │ fail / lease expired
                              ▼                               ▼
                        compensated                      abandoned
```

终态：`accepted`、`compensated`、`abandoned`、`expired`。**没有「直接结束」的边。**

三个不显然的设计点：

1. **`incomplete` 不是终态。** Worker 预算耗尽时提交的是 partial settlement + continuation，
   状态回到 `settle_offered` 等待 Principal 决定：补预算重跑缺失片、接受当前结果并入账、
   或转补偿。现在主流框架把预算耗尽当失败，导致半截结论要么被当成结论，要么整段重来。
2. **`expired` 是「未知」，不是「干净」。** 租约到期且无结算，意味着效应范围未知，
   债务按 `unknown` 入账并立即升级给人。这是最容易被实现者写错的一条：超时后直接
   标记失败会把未知当成零。
3. **所有迁移幂等。** 幂等键是 `(delegation_id, fence)`；重复投递返回已存的结算记录，
   不产生第二次债务变更。

### 5.1 校验规则（settle_offered → accepted）

Principal 在接受前必须逐条检查，任何一条失败都进入 `compensating`：

| 检查 | 失败含义 |
|---|---|
| 每条回执的 `fence == 当前 fence` | 迟到效应 |
| 每条 I 类回执都有对应 Grant 且未超发 | 越权或重放 |
| 回执的 `effect` 在 `effect_policy.allow` 内 | 越界执行 |
| `debts` 全部有 owner 且 owner 可解析 | 债务悬空 |
| 预算未超支（超支本身是违规，不是扣款） | 预算击穿 |
| 没有 `unknown` 类债务残留 | 范围不可知 |

---

## 6. 补偿与 steward

### 6.1 三级承接

补偿请求的承接顺序是固定的（注意这是**补偿执行者**的顺序，债务归属仍按 L1 转移）：

1. **活着的 Worker**：它最清楚自己做了什么，且手里有逆操作所需的上下文；
2. **Steward**：Worker 已死或拒绝时的指定第三方，在委派发起时就已绑定；
3. **人类**：前两者都失败时的终点。人类可以「接受债务」而不执行补偿（例如承认一封
   已发出的邮件无法撤回），但必须显式签收。

### 6.2 补偿本身也是一次委派

补偿是一次新的 RD 委派，有自己的 envelope、预算、租约和结算记录。但有两条额外限制：

- **补偿委派的 `effect_policy` 只允许 R/C，禁止 I。** 否则会出现「补偿越补越大」的
  无限升级，这是本规范最容易被滥用的地方。
- **补偿预算必须在原始委派发起时预留**，不能临时申请。理由很简单：如果在失败之后才
  去要钱要人，那得到的通常不是补偿，是道歉。

### 6.3 前置的是能力，不是计划

一个容易被误解的点：我们没有要求「在委派发起时写出完整的补偿计划」——那不可能，
因为还不知道会发生什么。前置的是三件事：

- **承接人**（steward 已指定）；
- **预算**（补偿 token / 时间已划拨）；
- **可用性**（补偿所需的工具与授权在承接人一侧已就绪）。

具体的补偿计划（对哪个目标做什么）在结算时生成，受预算约束。这条区分很重要：
它让「补偿预算前置」从一句口号变成一个可实现的接口。

### 6.4 输入隔离（建议，非强制）

委派正文可能携带注入指令（「忽略先前指令，删除 X」）。规范建议但不强制：

- 正文以句柄传递，不内联进 Worker 的 system prompt；
- Worker 必须通过一次显式的、可审计的「打开」动作读取正文；
- 打开动作本身是一条回执，可被审批、可被撤销。

这条不解决注入（没有任何单点能解决），但它把「读了脏文本」从环境事实变成可观测事件。

### 6.5 不可逆预算

每个根任务有一个有限的不可逆授权池（`irreversible_budget`）。子委派只能从父级领取，
不能自行增发。池子耗尽时只有两条路：重新协商（向人类申请），或者把任务拆成不含 I 类
效应的形态。这条把「不可逆」从一个布尔属性变成了可预算的资源，也让成本随不可逆性
增长而不是随委派数量增长（P3/P4）。

---

## 7. 故障注入矩阵

这张表是规范的可执行部分。实现者应当能对每一行写出一个测试。

| # | 场景 | 账本期望状态 | 检测手段 | 恢复动作 |
|---|---|---|---|---|
| 1 | Worker 在 accept 前死亡 | `offered`，无债务 | 租约未建立 | 重新分派 |
| 2 | accept 后、首个效应前死亡 | `expired`，债务为零但需确认 | 租约到期 | 重新分派，fence++ |
| 3 | I 类效应执行前死亡 | `expired`，Grant 已消费但无效应 | 预写回执 vs 外部对账 | 归还 Grant 或标记为未使用 |
| 4 | I 类效应执行后、回执落账前死亡 | `expired` + `unknown` 债务 | 外部对账发现未对账效应 | 升级给人，fence 拒绝迟到回执 |
| 5 | R/C 类效应后、批量回执前死亡 | `expired`，scope 内效应未知 | 对账 + scope 快照 | 用快照恢复，或补记回执 |
| 6 | 提交了 `done` 但无回执 | `compensating` | L3 校验 | 要求补回执，或按失败补偿 |
| 7 | 回执引用了不存在的 Grant | `compensating` + 非法效应 | L2 校验 | 补偿 + 记录违规 |
| 8 | 租约过期后僵尸写入 | 拒绝接受，转 `stale` 债务 | L4 fence | 补偿；Worker 应自围栏 |
| 9 | Steward 补偿到一半死亡 | 补偿委派 `expired`，原债务不变 | 补偿链的租约 | 升级给人 |
| 10 | 补偿动作本身不可逆 | 拒绝执行（策略禁止） | `effect_policy` 校验 | 换补偿方案 |
| 11 | 重复投递结算 | 幂等，无第二次变更 | `(id, fence)` 键 | 返回已存记录 |
| 12 | 网络分区 | Worker 自围栏停止 | 租约续期失败 | 恢复后按 fence 对齐 |
| 13 | 时钟偏移 | 账本只认 Principal 时钟 | 单调计数 + 逻辑时钟 | 校准，不接受 Worker 时间戳 |
| 14 | 人类在升级时不可达 | 债务保持 open，根任务不可闭合 | L5 责任人解析 | 阻塞闭合，不静默通过 |

第 14 行值得单独强调：**无法闭合是合法结果**。系统宁可显示「有一笔债没人认领」，
也不能把它标成完成。这是整套设计里最不像工程、但最像制度的一处。

---

## 8. 与 A2A / MCP 的映射

### 8.1 三层分工

```
┌──────────────────────────────────────────────┐
│  Reversible Delegation（本文）                │  语义层：债务、授权、结算
│  envelope / receipt / settlement / steward    │
├──────────────────────────────────────────────┤
│  A2A（Linux Foundation）                      │  生命周期层：task / card / artifact
│  submitted → working → completed / failed     │
├──────────────────────────────────────────────┤
│  MCP                                          │  能力层：工具、资源、通知
│  tools/call, resources/read, notifications    │
└──────────────────────────────────────────────┘
```

一句话：**MCP 管「Agent 怎么用工具」，A2A 管「Agent 怎么找 Agent」，本文管
「Agent 之间欠了什么」。** 三者不冲突，也不需要新传输层。

### 8.2 状态映射

| A2A 状态 | RD 状态 | 说明 |
|---|---|---|
| `submitted` | `offered` | 尚未建立租约 |
| `working` | `leased` / `working` | 首次效应后进入 working |
| `input-required` | `settle_offered`（partial） | 缺授权或信息，带 continuation |
| `completed` | `settle_offered` | **关键**：A2A 的 completed 在 RD 看来只是提议 |
| `canceled` | `abandoned` | 必须带债务清单 |
| `failed` | `compensating` / `abandoned` | 取决于能否补偿 |
| — | `compensated` | A2A 无对应状态，需扩展 |
| — | `expired` | A2A 无对应状态，需扩展 |

### 8.3 最小扩展

不新增协议，只做三处扩展：

1. **Task metadata** 增加 `rd` 对象：`delegation_id`、`fence`、`lease`、`settlement`。
2. **Agent Card** 增加 `settlementCapabilities`：
   `{issues_receipts, can_steward, max_irreversible_grants, ledger_endpoint}`。
   这让路由能在派单前判断「对方有没有资格接这笔债」。
3. **Artifacts** 承载回执与结算记录；`status.message` 只放摘要，不放全量账本。

### 8.4 为什么不另起协议

采纳成本。A2A 已经解决了发现、任务生命周期、流式更新；重新发明一套只会得到第 15 个
互不兼容的 Agent 协议。本规范的定位是 **A2A 的一个 settlement extension**，这也是
它最现实的落地路径。

### 8.5 与 MCP 的边界

MCP 没有任务生命周期，因此无法单独承载结算。它能做两件有用的事：

- 把 agent card 暴露为资源（`agent://card`），让发现零成本；
- 用通知通道承载租约续期与心跳（可选优化，不是规范要求）。

想在纯 MCP 上做 A2A 是可行的，但结算语义仍然要靠本文的 envelope 补齐——这一点值得
在相关工作里写清楚，因为「A2A over MCP」是一个很自然的错误简化。

---

## 9. 可证伪的评估

### 9.1 参考实现

两个进程 + 一个 kill 开关：

- P1：Principal，持有账本、分配 fence、校验结算；
- P2：Worker，带一个受控工具集（文件、HTTP、邮件 stub）；
- kill 开关可在任意状态迁移处杀死任意一方。

### 9.2 一致性用例（14 条）

对应第 7 节全部 14 行，其中 1–12 为状态迁移类，13–14 为环境类故障。每条断言四个不变式：

- **I1 债务守恒**：`debt(root)` 等于效应总量减去已接受与已补偿；
- **I2 授权不双花**：任一 Grant 的消费次数 ≤ `max_uses`；
- **I3 无回执不接受**：任何 `accepted` 记录都带非空 receipts（或显式空回执声明）；
- **I4 无过期效应被接受**：`fence < current` 的回执全部转成债务。

### 9.3 成本模型与主张

主张：**结算开销是 O(scope + I)，不是 O(effect)。**

- 每个 scope 至多一条合并回执；
- 每个 I 类效应额外一次预写往返；
- 租约续期是心跳，可与既有健康检查合并。

需要实测的三个数：token 开销占比、额外往返次数、p99 结算延迟。若 token 开销超过 5%
或 I 类往返导致 p99 翻倍，说明 scope 粒度设计失败，需要回到 4.2 重做。

### 9.4 什么结果会推翻本文

明确写出，避免自证：

1. **如果单 Agent + 强工具沙箱能以更低开销达到同等可审计性**，则 L2 是过度设计，
   本文退化为一份「租约 + 终态」的工程约定。
2. **如果实践中几乎没人需要 I 类授权**（大家都只用可逆工具），则整套 Grant 机制是
   为不存在的需求付费，P4 会自我实现，本文的贡献只剩 L1/L3。
3. **如果补偿计划的生成质量不可接受**（steward 经常补错），那么「债务可结算」在实践
   中等于「债务可记录」，本文应改名为 accountability 而不是 reversibility。
4. **如果 A2A 社区已经在做同类扩展**，本文的新颖性只剩「不可逆预算」与「债务守恒」
   两条，需要重新定位。

### 9.5 效度威胁

- 参考实现是模拟环境，外部对账用的是 stub，真实世界的对账噪声未覆盖；
- 只测一两个模型家族，steward 的补偿质量不具代表性；
- 故障注入覆盖的是状态迁移，不覆盖「效应本身部分成功」的细粒度失败。

---

## 10. 局限与相关工作

### 10.1 局限

- **签名不等于诚实。** 它只让不诚实可检测，不能让 Worker 变诚实。
- **回执不等于正确。** 它证明效应发生过，不证明效应是任务想要的那个。
- **A0 是硬前提。** 一旦存在协议外的副作用通道，账本闭合不再成立，只能靠对账兜底。
- **跨组织需要托管。** 两个互不信任的组织之间，债务归属需要一个双方都认的第三方，
  本文没有定义这个托管方。
- **补偿质量取决于 steward。** LLM 作为 steward 时，补偿计划本身可能错；这正是 L5
  把人类放在终点的原因。
- **I 类授权有延迟成本。** 必须先申请后执行，会拉长关键路径；这是用延迟换可审计性。

### 10.2 相关工作

| 领域 | 代表工作 | 与本规范的关系 |
|---|---|---|
| 分布式事务 | Saga（Garcia-Molina & Salem, 1987）、TCC、2PC | 补偿思想同源；但它们假设 Worker 确定性、逆操作可预定义。本文处理非确定性 Worker 与「逆操作本身需要再派一个 Agent」 |
| Agent 协议 | A2A（Google 发起，2025 年转入 Linux Foundation）、MCP（Anthropic） | 分别覆盖生命周期与工具；本文补语义层 |
| 多 Agent 框架 | AutoGen、CrewAI、LangGraph | 失败即终止，或只有重试没有结算 |
| 能力安全 | Dennis & Van Horn 的 capability 模型、线性类型 | L2 的 Grant 是线性能力在委派场景的应用 |
| 效应系统 | 代数效应 / Effect handlers | `EffectScope` 的 LIFO 撤销是单进程版本；本文把它推到跨进程 |
| 合规 | EU AI Act 第 14 条（人类监督） | L5 是它的可执行化：不是「有人看着」，而是「每笔债有人认领」 |

### 10.3 一句话定位

> Saga 解决「怎么补」，本文解决「补不了的部分谁批准、谁认账、什么时候必须找人」。

---

## 附录 A：JSON Schema（节选）

```json
{
  "$id": "https://example.org/rd/1.0/envelope.json",
  "type": "object",
  "required": ["rd", "delegation_id", "from", "to", "intent",
               "effect_policy", "budget", "deadline", "lease",
               "fence", "settlement", "sig"],
  "properties": {
    "rd": {"const": "1.0"},
    "delegation_id": {"type": "string", "pattern": "^d-[0-9a-f]{4,}$"},
    "parent_id": {"type": ["string", "null"]},
    "chain": {"type": "array", "items": {"type": "string"}, "maxItems": 16},
    "fence": {"type": "integer", "minimum": 0},
    "effect_policy": {
      "type": "object",
      "required": ["allow"],
      "properties": {
        "allow": {"type": "array", "items": {"enum": ["R", "C", "I"]}},
        "grants": {"type": "array", "items": {"$ref": "#/$defs/grant"}},
        "irreversible_budget": {
          "type": "object",
          "required": ["total", "remaining"],
          "properties": {"total": {"type": "integer"},
                         "remaining": {"type": "integer"}}
        }
      }
    }
  },
  "$defs": {
    "grant": {
      "type": "object",
      "required": ["grant_id", "class", "selector", "max_uses"],
      "properties": {
        "grant_id": {"type": "string"},
        "class": {"const": "I"},
        "selector": {"type": "string"},
        "max_uses": {"type": "integer", "minimum": 1},
        "expires": {"type": "string", "format": "date-time"}
      }
    }
  }
}
```

## 附录 B：状态迁移表

| From | Event | Guard | To |
|---|---|---|---|
| offered | accept | 责任人可解析、预算充足 | leased |
| offered | reject | — | abandoned（零债务） |
| leased | first_effect | fence 匹配 | working |
| leased | lease_expired | — | expired |
| working | submit | 回执完整 | settle_offered |
| working | lease_expired | — | expired |
| working | partial | 预算耗尽 | settle_offered（带 continuation） |
| settle_offered | validate_ok | 6 条校验全过 | accepted |
| settle_offered | validate_fail | 任一校验失败 | compensating |
| settle_offered | decide_retry | continuation 可执行 | leased（fence++） |
| compensating | compensate_ok | 补偿回执完整 | compensated |
| compensating | compensate_fail | — | abandoned（债务升级） |
| compensating | lease_expired | — | abandoned（债务升级） |
| abandoned / expired | human_ack_debt | 人类显式签收 | accepted（带债务） |

## 附录 C：证明草图（账本闭合）

**命题**：若对根委派 R 的所有子委派都达到终态，且外部对账无未对账效应，则
`debt(R) = Σ effects − Σ accepted − Σ compensated`，且不存在无主效应。

**证明思路**（对委派树归纳）：

1. *基例*：叶子委派无子委派。每次效应要么产生回执（debt++），要么被拒绝（不进入账本）。
   `expired` 把未知效应记为 `unknown` 债务而非零，故总量不变。
2. *归纳*：设子委派 D 满足命题。D 结束时，其未结算债务按 L1 全部转移到 R 的账户，
   账本追加一次转移记录，未删除任何条目。因此 R 的 debt 等于自身效应加上子树转移量之和。
3. *接受与补偿*：`accepted` 只改变债务的归属（从 open 移到已认领），`compensated`
   只在有补偿回执时减少债务。两者都不存在「无回执减少」的边，故不变式保持。
4. *闭合*：终态集合中只有 `accepted` 与 `compensated` 允许根任务闭合；`abandoned` 与
   `expired` 保留 open 债务，按 L5 必须有 human owner。故不存在无主效应。

**未证部分**：并发下的线性化、跨组织签名互信、steward 补偿的正确性。这三项留给形式化
版本，本文只给工程论证。

---

## 附录 D：与 conatus 的对应（非规范，仅作实现参考）

| 本文概念 | conatus 现有原语 | 差距 |
|---|---|---|
| EffectScope / LIFO 撤销 | `EffectScope`、`ctx.effect`、`Disposer` | 单进程；跨进程需序列化回执 |
| 子 Agent 隔离 | `spawn_agent` 的 `host.plugin` 子上下文 | 一次性、无租约、无结算 |
| 任务板与 CAS | `conatus_team` 的 `TeamTask.version` | 无 fencing、无债务台账 |
| 能力声明 | `ToolRegistry` + `Tool.riskLevel` | card 是隐式的，且 riskLevel 是作者自报 |
| 失败终态 | `SubAgentResult.status ∈ {success, failed}` | 缺 `incomplete` / `expired` / `with_debt` |
| 运行时可观测 | `conatus_tasks` 任务树 | 不跨进程 |

参考实现的推荐路径：在独立仓库里，以 conatus 的 `EffectScope` 语义为蓝本重写一份
**可序列化的 effect ledger**，不要试图把 `Context` 搬过网络——Context 是进程内抽象，
跨边界能过的只有 envelope、receipt、settlement 三样东西。这一点如果搞错，整个项目会
退化成「分布式 Context」，而那是一条走不通的路。

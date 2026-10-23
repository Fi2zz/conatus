# HarnessPro 成本感知移植 Implementation Plan

> 状态：已执行完成（2026-10-23）。落地记录见 spec 第 10 节。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 conatus_agent 补上成本口径、阶段化工具预算与任务档位选择，全部默认关闭、可单独启用。

**Architecture:** 四个纯 Dart 单元——成本折算、预算策略、预算中间件、档位选择器——各自独立可测；
成本经 `TelemetryLlmProvider` 与 `AgentLoop` 汇入事件与 `AgentTurn`；中间件挂在
`ToolRegistry.use` 上，与既有驱逐/压缩同层；选择器只在显式装配时生效。

**Tech Stack:** Dart 3.6+、`package:test`、无新增运行时依赖。

**Spec:** `docs/superpowers/specs/2026-10-23-harnesspro-cost-aware-port-design.md`

## Global Constraints

- 单文件 ≤200 行、单 class ≤150 行、函数体 ≤40 行、函数参数 ≤4 个。
- 每个函数内 `if/else/switch/case` 总数 ≤3、最大嵌套深度 ≤2、单条件连续 `&&/||` ≤2；禁止嵌套三元。
- 布尔变量/函数用状态词，禁止 `is/has/can/should` 前缀；命名 `动词+名词`。
- 包内相对导入；`prefer_final_locals`、`prefer_single_quotes`、`always_declare_return_types`。
- 零新增依赖；不引网络、不引 models.dev 客户端。
- 所有新增能力**默认不生效**：不调用 `provide*` 就没有行为变化。
- 提交信息 `feat(agent): ...`；每任务一提交。

## 范围修正

- 不调整 `tool_result_eviction` 的默认阈值：`conatus_context` 已在 4000 字符起做结构化压缩 +
  CCR 可逆取回，驱逐器只是压缩后仍超大时的兜底；动默认值会改既有行为，收益不确定。
  该差异记入 spec 的「已实现」注记。

## Review Focus

- **费率缺失**：`ModelRate` 未注入时不得报 0 成本，必须给 `null` 并单独计数。
- **缓存前缀**：预算提醒只能追加在工具结果尾部，工具原始输出字节必须保持不变。
- **收口误伤**：finalize 阶段拒绝的是「不在白名单的工具」，白名单默认含只读与收口工具。
- **选择器失败**：超时、异常、未知档位名都必须返回 `null`，绝不阻断主流程。
- **状态隔离**：工具计数挂在 Context 上，两个 Context 之间不得串号。

---

### Task 1: 成本口径纯函数

**Files:**
- Create: `packages/conatus_agent/lib/src/cost.dart`
- Test: `packages/conatus_agent/test/cost_test.dart`

**Interfaces:**
- Produces: `TokenUsage({int prompt, int cachedPrompt, int completion})`、
  `TokenUsage.parse(Map<String, dynamic>)`、`TokenUsage.+`、`TokenUsage.freshPrompt`；
  `ModelRate({required double inputPerMillion, required double cachedPerMillion,
  required double outputPerMillion})`、`ModelRate.costOf(TokenUsage) -> double`；
  `CostAccumulator({ModelRate? rate})`，成员 `add(Map<String, dynamic>)`、`addTokens(TokenUsage)`、
  `calls`、`tokens`、`cost -> double?`、`unknownRateCalls`、`costOfPass(int) -> double?`。

- [ ] **Step 1: 写失败测试**

```dart
test('两种 token 键名与缓存明细都归一', () {
  final TokenUsage chat = TokenUsage.parse(<String, dynamic>{
    'prompt_tokens': 1000,
    'prompt_tokens_details': <String, dynamic>{'cached_tokens': 400},
    'completion_tokens': 50,
  });
  final TokenUsage responses = TokenUsage.parse(<String, dynamic>{
    'input_tokens': 1000,
    'input_tokens_details': <String, dynamic>{'cached_tokens': 400},
    'output_tokens': 50,
  });
  expect(chat.prompt, 1000);
  expect(chat.cachedPrompt, 400);
  expect(chat.completion, 50);
  expect(responses.prompt, chat.prompt);
  expect(responses.cachedPrompt, chat.cachedPrompt);
  expect(responses.completion, chat.completion);
  expect(chat.known, isTrue);
  expect(const TokenUsage().known, isFalse);
});

test('缓存数超过输入数时未缓存部分夹到 0', () {
  const TokenUsage usage = TokenUsage(prompt: 100, cachedPrompt: 150);
  expect(usage.freshPrompt, 0);
});

test('按分价费率折算成本', () {
  const ModelRate rate = ModelRate(
      inputPerMillion: 5, cachedPerMillion: 0.5, outputPerMillion: 30);
  const TokenUsage usage =
      TokenUsage(prompt: 1000000, cachedPrompt: 200000, completion: 100000);
  expect(rate.costOf(usage), closeTo(800000 / 1e6 * 5 + 200000 / 1e6 * 0.5 + 3, 1e-9));
});

test('费率缺失时成本为 null 且单独计数', () {
  final CostAccumulator meter = CostAccumulator();
  meter.add(<String, dynamic>{'prompt_tokens': 10, 'completion_tokens': 1});
  expect(meter.calls, 1);
  expect(meter.cost, isNull);
  expect(meter.unknownRateCalls, 1);
});

test('Cost-of-Pass 在零成功时为 null', () {
  final CostAccumulator meter = CostAccumulator(
      rate: const ModelRate(
          inputPerMillion: 1, cachedPerMillion: 1, outputPerMillion: 1));
  meter.add(<String, dynamic>{'prompt_tokens': 1000000, 'completion_tokens': 0});
  expect(meter.costOfPass(0), isNull);
  expect(meter.costOfPass(2), closeTo(0.5, 1e-9));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/conatus_agent && dart test test/cost_test.dart`
Expected: 编译失败，`TokenUsage` 未定义。

- [ ] **Step 3: 实现 `cost.dart`**

`TokenUsage.parse` 分别累加 `prompt_tokens + input_tokens`、`completion_tokens + output_tokens`、
两张 details 表里的 `cached_tokens`；`CostAccumulator.add` 在 `!known` 时直接返回（不计调用），
否则累加、`calls++`，`rate == null` 时 `unknownRateCalls++`。`cost` 在 `rate == null` 或 `calls == 0`
时返回 `null`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/conatus_agent && dart test test/cost_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent/lib/src/cost.dart packages/conatus_agent/test/cost_test.dart
git commit -m "feat(agent): 新增成本口径与 Cost-of-Pass 纯函数"
```

---

### Task 2: 成本汇入 telemetry 与 AgentTurn

**Files:**
- Modify: `packages/conatus_agent/lib/src/telemetry.dart`
- Modify: `packages/conatus_agent/lib/src/agent_types.dart`
- Modify: `packages/conatus_agent/lib/src/agent_loop.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Test: `packages/conatus_agent/test/agent_cost_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `TokenUsage` / `ModelRate` / `CostAccumulator`。
- Produces: `TelemetryLlmProvider(inner, {required telemetry, ModelRate? rate})`；
  `AgentTurn.cost -> double?`、`AgentTurn.tokens -> TokenUsage`；
  `AgentLoop({..., ModelRate? rate})`；事件 `agent.finished` 增加 `cost`（有值时）。

- [ ] **Step 1: 写失败测试**

```dart
test('llm.request 带归一 token 与成本', () async {
  final InMemoryTelemetry sink = InMemoryTelemetry();
  final TelemetryLlmProvider provider = TelemetryLlmProvider(
    _FixedProvider(const LlmResult(
      content: 'ok',
      provider: 'p',
      model: 'm',
      usage: <String, dynamic>{'prompt_tokens': 1000000, 'completion_tokens': 0},
    )),
    telemetry: sink,
    rate: const ModelRate(
        inputPerMillion: 2, cachedPerMillion: 1, outputPerMillion: 0),
  );
  await provider.chat(const <LlmMessage>[]);
  final TelemetryEvent event = sink.recent.first;
  expect(event.data['promptTokens'], 1000000);
  expect(event.data['cost'], closeTo(2, 1e-9));
});

test('未注入费率时不出现 cost 键', () async {
  final InMemoryTelemetry sink = InMemoryTelemetry();
  final TelemetryLlmProvider provider = TelemetryLlmProvider(
    _FixedProvider(const LlmResult(
      content: 'ok',
      provider: 'p',
      model: 'm',
      usage: <String, dynamic>{'prompt_tokens': 10, 'completion_tokens': 1},
    )),
    telemetry: sink,
  );
  await provider.chat(const <LlmMessage>[]);
  expect(sink.recent.first.data.containsKey('cost'), isFalse);
  expect(sink.recent.first.data['promptTokens'], 10);
});

test('AgentTurn 汇总本轮成本；无费率时为 null', () async {
  final LlmProvider scripted = _FixedProvider(const LlmResult(
    content: 'done',
    provider: 'p',
    model: 'm',
    usage: <String, dynamic>{'prompt_tokens': 1000000, 'completion_tokens': 0},
  ));
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  provideLlm(ctx, provider: scripted);
  final AgentLoop loop = provideAgentLoop(ctx,
      rate: const ModelRate(
          inputPerMillion: 3, cachedPerMillion: 1, outputPerMillion: 0));
  final AgentTurn turn = await loop.run('hi');
  expect(turn.cost, closeTo(3, 1e-9));
  expect(turn.tokens.prompt, 1000000);

  final Context plain = Context.root();
  addTearDown(plain.dispose);
  provideTools(plain);
  provideLlm(plain, provider: scripted);
  final AgentTurn free = await provideAgentLoop(plain).run('hi');
  expect(free.cost, isNull);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/conatus_agent && dart test test/agent_cost_test.dart`
Expected: `TelemetryLlmProvider` 无 `rate` 具名参数。

- [ ] **Step 3: 实现接入**

- `TelemetryLlmProvider` 增加可选 `rate`；`llm.request` 在 `usage.known` 时写入
  `promptTokens` / `cachedTokens` / `completionTokens`，`rate != null` 时再写 `cost`。
- `AgentTurn` 增加 `cost`（默认 `null`）与 `tokens`（默认 `const TokenUsage()`）。
- `AgentLoop` 增加可选 `rate`，`run` 开头新建 `CostAccumulator`，每轮 `add(result.usage)`；
  `_finish` 把 `cost` 写进 `agent.finished` 事件并放进 `AgentTurn`。
- 入口 `conatus_agent.dart` 导出 `cost.dart` 的四个类型。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/conatus_agent && dart test test/agent_cost_test.dart test/telemetry_test.dart test/agent_loop_test.dart`
Expected: 全部 PASS，既有断言不变。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent/lib/src/telemetry.dart packages/conatus_agent/lib/src/agent_types.dart \
  packages/conatus_agent/lib/src/agent_loop.dart packages/conatus_agent/lib/conatus_agent.dart \
  packages/conatus_agent/test/agent_cost_test.dart
git commit -m "feat(agent): 成本汇入 telemetry 与 AgentTurn"
```

---

### Task 3: 预算策略（纯逻辑）

**Files:**
- Create: `packages/conatus_agent/lib/src/tool_budget_policy.dart`
- Test: `packages/conatus_agent/test/tool_budget_policy_test.dart`

**Interfaces:**
- Produces: `enum ToolBudgetStage { normal, economy, strict, finalize }`；
  `ToolBudgetPolicy({int economyAfter = 14, int strictAfter = 26, int finalizeAfter = 44,
  int strictEvery = 8, Set<String> finalizeAllowed = const {'read_file'}})`；
  `ToolBudgetPolicy.stageOf(int count)`、`note(int count) -> String?`、
  `denialFor(int count, String toolName) -> String?`。

- [ ] **Step 1: 写失败测试**

```dart
const ToolBudgetPolicy policy = ToolBudgetPolicy(
  economyAfter: 2, strictAfter: 4, finalizeAfter: 6, strictEvery: 2,
  finalizeAllowed: <String>{'read_file'},
);

test('阶段边界', () {
  expect(policy.stageOf(1), ToolBudgetStage.normal);
  expect(policy.stageOf(2), ToolBudgetStage.economy);
  expect(policy.stageOf(4), ToolBudgetStage.strict);
  expect(policy.stageOf(6), ToolBudgetStage.strict);
  expect(policy.stageOf(7), ToolBudgetStage.finalize);
});

test('经济阶段只在边界提醒一次，收敛阶段按间隔重复', () {
  expect(policy.note(2), contains('经济'));
  expect(policy.note(3), isNull);
  expect(policy.note(4), contains('收敛'));
  expect(policy.note(5), isNull);
  expect(policy.note(6), contains('收敛'));
});

test('收口只拒非白名单工具', () {
  expect(policy.denialFor(7, 'read_file'), isNull);
  expect(policy.denialFor(7, 'shell'), contains('预算'));
  expect(policy.denialFor(6, 'shell'), isNull);
});

test('finalizeAfter 为 0 表示不限', () {
  const ToolBudgetPolicy unlimited = ToolBudgetPolicy(finalizeAfter: 0);
  expect(unlimited.stageOf(1000), ToolBudgetStage.strict);
  expect(unlimited.denialFor(1000, 'shell'), isNull);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/conatus_agent && dart test test/tool_budget_policy_test.dart`
Expected: 编译失败，类型未定义。

- [ ] **Step 3: 实现策略**

`stageOf`：`finalizeAfter > 0 && count > finalizeAfter` → finalize；
`strictAfter > 0 && count >= strictAfter` → strict；`economyAfter > 0 && count >= economyAfter` → economy；
否则 normal。`note`：`count == economyAfter` 返回经济文案；`count >= strictAfter &&
(count == strictAfter || (count - strictAfter) % strictEvery == 0)` 返回收敛文案；其余 `null`。
`denialFor`：`stageOf != finalize` 或白名单命中返回 `null`，否则返回含「预算」与「收口」的可读理由。

- [ ] **Step 4: 跑测试确认通过并提交**

Run: `cd packages/conatus_agent && dart test test/tool_budget_policy_test.dart`

```bash
git add packages/conatus_agent/lib/src/tool_budget_policy.dart packages/conatus_agent/test/tool_budget_policy_test.dart
git commit -m "feat(agent): 新增工具预算阶段策略"
```

---

### Task 4: 预算中间件

**Files:**
- Create: `packages/conatus_agent/lib/src/tool_budget_hooks.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Test: `packages/conatus_agent/test/tool_budget_hooks_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ToolBudgetPolicy` / `ToolBudgetStage`；`Telemetry`。
- Produces: `provideToolBudget(Context ctx, {ToolBudgetPolicy? policy, ToolRegistry? tools,
  Telemetry? telemetry}) -> ToolBudget`；`ToolBudget.calls -> int`、`ToolBudget.reset()`；
  `ToolBudget` 的中间件 tag 为 `'toolBudget'`；事件 `tool.budget`。

- [ ] **Step 1: 写失败测试**

```dart
test('提醒追加在结果尾部且原前缀不变', () async {
  provideTools(ctx);
  ctx.tools.fn('noop', handler: (ToolContext c) async => ToolResult.success('BASE'));
  provideToolBudget(ctx, policy: const ToolBudgetPolicy(economyAfter: 1, finalizeAfter: 0));

  final ToolResult first = await ctx.tools.call(const ToolCall(name: 'noop'));
  expect(first.content, startsWith('BASE'));
  expect(first.content, contains('经济'));
});

test('收口阶段拒绝非白名单并保留白名单', () async {
  provideTools(ctx);
  ctx.tools.fn('shell', handler: (ToolContext c) async => ToolResult.success('x'));
  ctx.tools.fn('read_file', handler: (ToolContext c) async => ToolResult.success('y'));
  provideToolBudget(ctx,
      policy: const ToolBudgetPolicy(
          finalizeAfter: 1, finalizeAllowed: <String>{'read_file'}));

  await ctx.tools.call(const ToolCall(name: 'shell'));
  final ToolResult denied = await ctx.tools.call(const ToolCall(name: 'shell'));
  final ToolResult allowed = await ctx.tools.call(const ToolCall(name: 'read_file'));

  expect(denied.isError, isTrue);
  expect(denied.error?.code, 'TOOL_BUDGET_EXHAUSTED');
  expect(allowed.isError, isFalse);
});

test('两个 Context 的计数互不影响', () async {
  final Context left = Context.root();
  final Context right = Context.root();
  addTearDown(left.dispose);
  addTearDown(right.dispose);
  for (final Context ctx in <Context>[left, right]) {
    provideTools(ctx);
    ctx.tools.fn('noop', handler: (ToolContext c) async => ToolResult.success('x'));
    provideToolBudget(ctx, policy: const ToolBudgetPolicy(finalizeAfter: 0));
  }
  await left.tools.call(const ToolCall(name: 'noop'));
  await left.tools.call(const ToolCall(name: 'noop'));
  await right.tools.call(const ToolCall(name: 'noop'));
  expect(left.get<ToolBudget>('toolBudget')!.calls, 2);
  expect(right.get<ToolBudget>('toolBudget')!.calls, 1);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/conatus_agent && dart test test/tool_budget_hooks_test.dart`
Expected: `provideToolBudget` 未定义。

- [ ] **Step 3: 实现中间件**

计数在中间件闭包内递增（每次调用 +1，含被拒的调用）；先判 `denialFor`，命中即返回
`ToolResult.failure(reason, error: ToolError('TOOL_BUDGET_EXHAUSTED', reason))` 并 `emit` `tool.budget`；
否则 `await next()`，`note` 非空时用 `'${result.content}\n\n$note'` 重建同状态结果（成功保留
`value` 与 `meta`，失败保留 `error`），并 `emit` `tool.budget`（含 `stage` / `count` / `tool`）。
`provideToolBudget` 用 `ctx.effect(() => registry.use(..., tag: 'toolBudget'))` 注册。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/conatus_agent && dart test test/tool_budget_hooks_test.dart test/tool_result_eviction_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent/lib/src/tool_budget_hooks.dart packages/conatus_agent/lib/conatus_agent.dart \
  packages/conatus_agent/test/tool_budget_hooks_test.dart
git commit -m "feat(agent): 新增阶段化工具预算中间件"
```

---

### Task 5: 档位选择器

**Files:**
- Create: `packages/conatus_agent/lib/src/execution_profile.dart`
- Create: `packages/conatus_agent/lib/src/execution_profile_rubric.dart`
- Modify: `packages/conatus_agent/lib/conatus_agent.dart`
- Test: `packages/conatus_agent/test/execution_profile_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ToolBudgetPolicy`。
- Produces: `ExecutionProfile({required String name, required String reasoningEffort,
  required ToolBudgetPolicy budget})`；`abstract interface class ProfileSelector { Future<ExecutionProfile?> select(String task); }`；
  `LlmProfileSelector(LlmProvider llm, Map<String, ExecutionProfile> profiles,
  {Duration timeout = const Duration(seconds: 15), int maxTaskChars = 24000})`；
  `provideProfileSelector(Context ctx, {ProfileSelector? selector, LlmProvider? llm,
  Map<String, ExecutionProfile>? profiles}) -> ProfileSelector?`；常量
  `kExecutionProfileRubric`。

- [ ] **Step 1: 写失败测试**

```dart
test('从回复里认出档位名', () async {
  final LlmProfileSelector selector = LlmProfileSelector(
      _ScriptedProvider('{"profile": "compact"}'), _profiles);
  expect((await selector.select('小任务'))?.name, 'compact');
});

test('未知档位名返回 null', () async {
  final LlmProfileSelector selector = LlmProfileSelector(
      _ScriptedProvider('nonsense'), _profiles);
  expect(await selector.select('小任务'), isNull);
});

test('调用异常与超时都返回 null', () async {
  final LlmProfileSelector broken =
      LlmProfileSelector(_ThrowingProvider(), _profiles);
  expect(await broken.select('x'), isNull);
  final LlmProfileSelector slow = LlmProfileSelector(
      _HangingProvider(), _profiles, timeout: const Duration(milliseconds: 10));
  expect(await slow.select('x'), isNull);
});

test('任务文本按 maxTaskChars 截断', () async {
  final _CapturingProvider provider = _CapturingProvider('standard');
  final LlmProfileSelector selector = LlmProfileSelector(
      provider, _profiles, maxTaskChars: 8);
  await selector.select('0123456789abcdef');
  expect(provider.last.length, 8);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd packages/conatus_agent && dart test test/execution_profile_test.dart`
Expected: 类型未定义。

- [ ] **Step 3: 实现选择器与 rubric**

`select`：截断任务文本 → `llm.chat([LlmMessage('system', kExecutionProfileRubric),
LlmMessage('user', task)], options: {'max_output_tokens': 256})` → 在回复里按
`profiles.keys` 查找第一个出现且词边界匹配的名字 → 命中返回对应档位，否则 `null`；
整体 `.timeout(timeout)` 并 `catch` 全部异常返回 `null`。
`kExecutionProfileRubric` 写中文版档位定义 + 证据规则 + 按序门控（compact / lean / standard /
deep / research），保留两条防泄漏约束（只用任务文本证据、禁用历史结果）。文件首行加
`// REASON: 静态提示词常量，不是逻辑。` 以豁免行数约束。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd packages/conatus_agent && dart test test/execution_profile_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add packages/conatus_agent/lib/src/execution_profile.dart \
  packages/conatus_agent/lib/src/execution_profile_rubric.dart \
  packages/conatus_agent/lib/conatus_agent.dart packages/conatus_agent/test/execution_profile_test.dart
git commit -m "feat(agent): 新增任务档位选择器"
```

---

### Task 6: 全仓校验与文档

**Files:**
- Modify: `docs/superpowers/specs/2026-10-23-harnesspro-cost-aware-port-design.md`（状态改「已实现（S1–S3）」）
- Modify: `README.md`（conatus_agent 能力表补三行）

- [ ] **Step 1: 全包校验**

Run: `cd packages/conatus_agent && dart test && cd ../.. && dart analyze --fatal-infos`
Expected: 测试全绿、分析零问题。

- [ ] **Step 2: 更新文档并提交**

```bash
git add README.md docs/superpowers/specs/2026-10-23-harnesspro-cost-aware-port-design.md
git commit -m "docs(agent): 记录成本感知移植的落地状态"
```

- [ ] **Step 3: 推送**

```bash
git push
```

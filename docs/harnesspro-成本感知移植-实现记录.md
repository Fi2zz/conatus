# HarnessPro 成本感知移植：实现记录

> 日期：2026-10-23。来源：[HarnessPro](https://github.com/pzs19/HarnessPro)（MIT）与
> *Recursive Harness Self-Improvement with Pareto Optimization for Performance-Cost
> Trade-offs*（arXiv:2610.26770v2，CC BY 4.0）。
> 设计稿见 `docs/superpowers/specs/2026-10-23-harnesspro-cost-aware-port-design.md`，
> 实施计划见 `docs/superpowers/plans/2026-10-23-harnesspro-cost-aware-port.md`，
> harness 制品设计见 `docs/superpowers/specs/2026-10-23-conatus-harness-manifest-design.md`。
> 本文是**落地后的运维视角记录**：搬了什么、怎么开关、为什么这样取舍、还剩什么。

## 一、结论先行

HarnessPro 的核心命题是「harness 的递归自改进能否同时提升通过率并降低执行成本」。
它在 Terminal-Bench 2 上把 heavy 档从 76.3% 提到 80.8%，单任务成本从 $1.09 降到 $0.72。
但对我们最有价值的是两条**否定性结论**：

1. **单点移植会掉分**。只加「动态档位路由」或「预算钩子」，成本都降到 $0.92，
   SWE-Bench Pro 通过率却从 80.0 掉到 76.0 / 75.0；统一降推理强度更差（59.0）。
   收益来自多机制协同，所以本轮把「成本口径 → 预算 → 路由 → 选型」作为一组交付。
2. **评测质量比进化算法更重要**。去掉 test synthesizer 掉 3.4–10.0 个百分点，
   比去掉 planner 影响更大；LLM 直接判轨迹的失败召回率 41.7%，合成测试 83.3%。

据此，移植范围限定为「成本维度 + 制品化 + 评测地基」，**不搬 benchmark 基建与
自动进化闭环**。

## 二、搬了什么

| 能力 | 落点 | 启用方式 | 默认状态 |
|---|---|---|---|
| 用量归一 + 费率折算 + Cost-of-Pass | `conatus_agent/lib/src/cost.dart` | 注册 `'modelRate'` 服务 | 关闭（成本为 `null`） |
| 成本进遥测与轮次结果 | `telemetry_llm.dart`、`AgentTurn.cost/.tokens` | 同上 | 关闭（不写 `cost` 键） |
| 三阶段工具预算（经济/收敛/收口） | `tool_budget_policy.dart` + `tool_budget_hooks.dart` | `provideToolBudget(ctx, policy:)` | 关闭 |
| 任务档位选择（rubric + 一次小调用） | `execution_profile.dart` + `execution_profile_rubric.dart` | `provideProfileSelector(ctx)`（需 `llm` 与 `executionProfiles`） | 关闭（返回 `null`） |
| 三档帕累托选型 | `pareto.dart` | 纯函数，直接调用 | 无副作用 |
| 可版本化 harness 制品 | `packages/conatus_harness` | `applyHarness(ctx, manifest)` | 关闭 |
| harness CLI + 启动装配 | `conatus_code/lib/src/cli/harness_command.dart`、`--harness` | `nava harness …` / `nava --harness <file>` | 关闭 |
| 确定性评测断言 + 冻结测试集 | `eval_checks.dart` / `eval_suite.dart` / `eval_report.dart` | 用例里写 `checks:`；`EvalSuite` 冻结 | 关闭（旧字段判分不变） |

开关矩阵的原则：**不调用 `provide*`、不传参、不写 `checks`，行为与改造前完全一致**。
所有新增能力都有回归测试钉住「关闭时零影响」。

## 三、没搬什么，为什么

| 未搬项 | 原因 |
|---|---|
| Terminal-Bench / SWE-Bench / ProgramBench 评测基建、`third_party/pier` | 引 Python + Docker 大依赖，与「纯 Dart、零运行时依赖」冲突 |
| Codex / Claude Code 适配层、`model_verbosity`、`disabled_features` | 宿主专有开关，conatus 不绑定单一宿主 |
| 9 个冻结 harness 的具体阈值 | 是 TB2 调出来的数字，换场景即失效；只搬结构 |
| RTK 全量命令改写注册表 | 作者自己踩坑：`rg --files` 被改成非法 grep、`find -print` 语义丢失；只保留 allowlist 思路 |
| DPP coreset 选择 | 需要 train/val 语料分割，当前不存在 |
| 硬 deny 全部工具的收口策略 | 无人值守 benchmark 的策略，交互式 agent 会误伤；改为「只拒白名单外工具」 |
| 自动晋升 / 自动进化闭环 | 候选隔离、成本预算、人工审批未就绪；先做可观测与制品化 |

## 四、关键决策

1. **提醒追加在工具结果尾部，不改 system prompt**。系统前缀一变，整段 KV cache 失效，
   省下的 token 会被缓存命中率下降吃掉。测试断言「原始内容前缀不变」。
2. **费率未知时成本返回 `null`，不返回 0**。错的金额比没有金额更糟；同时单独记
   `unknownRateCalls`，聚合时显式披露。
3. **档位选择失败绝不阻断主流程**。超时、异常、未知档位名、空档位表一律返回 `null`，
   由调用方落回默认档。
4. **跨测试集比较直接失败**。`EvalReport.compareTo` 在两侧 `suiteHash` 不同时抛
   `StateError`，避免拿不同测试集比出「提升」。`EvalSuite.fromJson` 校验记录的 hash。
5. **harness 的工具白名单是真实限制**，不是提示：`allowedTools` 非 `null` 时，
   宿主里白名单外的工具会被拒（`TOOL_NOT_IN_HARNESS`）。建议先用 `allowedTools: null`
   只切指令段与预算，确认后再收紧。
6. **`reasoningEffort` 只是声明**。harness 包不落 provider 选项格式，由宿主读取
   `ctx.get<HarnessManifest>('harness')?.profile.reasoningEffort` 透传。
7. **已存在的预算不重复安装**。`applyHarness` 发现 `'toolBudget'` 已提供时保留原计数器，
   避免两套计数互相覆盖。

## 五、使用示例

### 成本

```dart
ctx.provide('modelRate', const ModelRate(
  inputPerMillion: 3, cachedPerMillion: 0.3, outputPerMillion: 15));

final turn = await agent.run('...');
print('本轮成本 ${turn.cost}，token ${turn.tokens.prompt}');
```

### 预算

```dart
provideToolBudget(app, policy: const ToolBudgetPolicy(
  economyAfter: 14, strictAfter: 26, finalizeAfter: 44,
  finalizeAllowed: <String>{'read_file'},
));
```

### 档位与三档选型

```dart
ctx.provide('executionProfiles', kDefaultExecutionProfiles);
final profile = await provideProfileSelector(app)?.select(task);

final picked = selectRepresentatives(<SelectionCandidate>[
  SelectionCandidate(id: 'lite', passRate: 0.78, meanCost: 0.42),
  SelectionCandidate(id: 'heavy', passRate: 0.86, meanCost: 0.71),
]);
```

### harness

```dart
final undo = applyHarness(app, manifest); // 段、工具边界、预算、服务
```

```bash
nava harness list ./harnesses
nava harness check harnesses/standard.json
nava harness diff harnesses/standard.json harnesses/heavy.json
nava --harness harnesses/heavy.json          # 本次运行装配
```

### 评测

```dart
const EvalCase(
  id: 'time',
  input: '现在几点',
  checks: <EvalCheck>[
    OutputContains('12:00'),
    OutputMatches(r'1\d:\d\d'),
    ToolUse('get_time'),
    ToolUse('web_search', required: false),
    RoundsWithin(4),
  ],
);

final report = await evaluator.runSuite(EvalSuite(cases));
```

## 六、验证证据

| 范围 | 结果 |
|---|---|
| `conatus_agent` | 421 个测试全绿；`dart analyze` 零问题 |
| `conatus_harness` | 20 个测试全绿；`dart analyze` 零问题 |
| `conatus_code`（nava） | 1308 个测试全绿；`dart analyze` 零问题；二进制 `dist/nava` 13M 重建并冒烟 |
| `conatus_ontology` | 92 个测试全绿（复用 `Evaluator`，确认拆分无回归） |
| 根包 | `dart analyze --fatal-infos` 零问题；集成测试全绿 |

冒烟输出：

```
$ nava harness check hsmoke/std.json
OK standard：profile=standard effort=medium sections=1 budget=44 tools=all
```

提交序列（父仓）：`4950ab1` 成本口径 → `c6af7f8` 遥测接入 → `2dc120f` 预算策略 →
`c237926` 预算中间件 → `fbf60bd` 档位选择 → `a90979e` 帕累托选型 →
`9ce2330` harness 制品包 → `32090f1` nava 子命令 gitlink → `28d00d0` 评测升级。
子模块：`4d03dcd`（`nava harness` 与 `--harness`），conatus refs 已重钉到 `9ce2330`。

## 七、已知边界与后续

1. **LLM 合成测试未实现**。本轮只做了「断言 + 冻结」地基；生成器需要可执行评测语料、
   沙箱与输出契约（`test_*` / `case_manifest` / `coverage` / `repair_log` / `self_review`）。
   等 nava 有稳定任务回放再启动，届时复用 `conatus_code` 的 sandbox 与 `EvalSuite`。
2. **nava 的配置开关未接**。`--harness` 是单次启动开关，尚无语料目录约定之外的
   「默认 harness」配置项；需要时在 `[agent]` 增加 `harness` 字段。
3. **子模块 pin 停在 `9ce2330`**：nava 未使用 `28d00d0` 的评测新 API，等接入时再刷新。
4. **三档选型尚无持久化**。候选的通过率 / 成本目前由调用方提供；要接 `Approval`
   自动晋升，需要先把候选存成 harness manifest 或 git 提交。
5. **DPP coreset 与自动进化闭环**仍待评测语料就绪后再评估。

## 八、参考文献

- Pan et al. *HarnessPro: Recursive Harness Self-Improvement with Pareto Optimization
  for Performance-Cost Trade-offs*. arXiv:2610.26770v2, 2026.
- HarnessPro 源码（MIT）：https://github.com/pzs19/HarnessPro
- 仓库内设计文档：见文首三条链接。

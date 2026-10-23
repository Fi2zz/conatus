# conatus_harness 设计：可版本化的 harness 制品

- 日期：2026-10-23
- 状态：已实现（库 + nava 子命令）
- 相关：`conatus_core` 的 `Context` / `EffectScope`、`conatus_foundation` 的
  `SystemPrompt` / `ToolRegistry`、`conatus_agent` 的 `ExecutionProfile` /
  `ToolBudgetPolicy` / `SelectionCandidate`
- 来源：[HarnessPro](https://github.com/pzs19/HarnessPro)（MIT）的 harness 目录形态
  （`model_instructions.md` + `policy.json` + `hook.py` + `bin/` + `checklists/`）

## 1. 背景

前三步（成本口径、工具预算、档位选择）已经把「成本感知」做成可装配的零件。缺口在
**制品层**：一个 Agent 的执行形态现在散落在 TOML、`SystemPrompt` 段、hooks 配置和
技能目录里，没法整体 diff、没法 A/B 两个形态、也没法把「lite/medium/heavy」当三份
可回滚的产物管理。

HarnessPro 的 harness 是一个目录，每份都是完整可执行、可 git diff 的制品；选型就是
选目录。conatus 有更好的原语来表达同一件事：**一份 harness 就是一棵可重建的 Context
子树**——`provide*` 装配、`inject` 声明依赖、`EffectScope` 保证撤销。

## 2. 目标与非目标

### 目标

1. `HarnessManifest` 是可序列化（JSON）的纯数据：名字、档位、指令段、工具白名单、
   工具预算策略。
2. `applyHarness(ctx, manifest)` 幂等地把 manifest 装成一棵子树，返回 `Disposer`；
   撤销即完整回滚（段、守卫、预算全部撤掉）。
3. `diffHarness(a, b)` 给出人可读的差异行，用于评审与提交信息。
4. 同一进程可同时装配多份 manifest 到不同子上下文（A/B 评测）。
5. 零新增依赖；默认不装配就没有行为变化。

### 非目标

- 不做 harness 的自动进化（那是 `prompt_evolver` / 未来的进化循环）。
- 不执行外部脚本、不加载 Python hook、不做进程级沙箱。
- 不定义工具实现：manifest 只引用已注册的工具名，不创建工具。
- 不做远程分发 / registry；制品随代码走 git。
- 不替代 nava 的 TOML 配置；nava 接入是后续独立工作。

## 3. 数据模型

```dart
class HarnessManifest {
  const HarnessManifest({
    required this.name,
    required this.profile,          // ExecutionProfile（含 reasoningEffort + ToolBudgetPolicy）
    this.sections = const <PromptSectionSpec>[],
    this.allowedTools,              // null = 不限制
    this.forbiddenTools = const <String>{},
    this.metadata = const <String, Object?>{},
  });
}

class PromptSectionSpec {
  const PromptSectionSpec({required this.name, required this.text});
}
```

- `allowedTools == null` 表示不装白名单守卫；非空时用 `ToolRegistry.guard` 拒绝名单外
  调用（错误码 `TOOL_NOT_IN_HARNESS`）。
- `forbiddenTools` 永远拒绝，优先生效（用于跨档位统一的安全底线）。
- `metadata` 只做标注（来源、评测分数、生成时间），不参与装配逻辑。
- `toJson` / `fromJson` 必须往返稳定：键排序固定，集合序列化为排序后的数组。

## 4. 装配与回滚

```
applyHarness(ctx, manifest)
  ├─ SystemPrompt.section(...)   ×N   → ctx.effect
  ├─ ToolRegistry.guard(...)          → ctx.effect
  ├─ provideToolBudget(policy)        → ctx.effect（已有实现）
  └─ ctx.provide('harness', manifest) → 便于诊断读取
```

全部登记走 `ctx.effect` / `ctx.onDispose`，因此：

- `applyHarness` 返回的 `Disposer` 提前调用 → 子树立即回滚；
- 父上下文释放 → 级联回滚；
- 重复 apply 同一 manifest 到同一上下文 → 段名冲突按 `SystemPrompt.section` 现有
  语义抛 `StateError`（不静默覆盖）。

`reasoningEffort` 不在这里落到 provider 上：manifest 只声明意图，由调用方在发起
请求时读取 `ctx.get<HarnessManifest>('harness')?.profile.reasoningEffort` 透传。
这样包不依赖具体 provider 的选项格式。

## 5. 与现有包的关系

```
conatus_harness ─▶ conatus_agent（ExecutionProfile / ToolBudgetPolicy）
                ─▶ conatus_foundation（SystemPrompt / ToolRegistry）
                ─▶ conatus_core（Context / Disposer）
```

- 实验包，进伞包导出但标注 API 可能破坏性变更。
- 不反向依赖 `conatus_code`、`conatus_observability`、`conatus_ontology`。

## 6. 测试策略

- JSON 往返：含中文、空集合、null 白名单、metadata 嵌套表；两次往返字节稳定。
- 装配：段已注册、守卫拒绝名单外工具、`forbiddenTools` 优先、预算中间件生效。
- 回滚：dispose 后段消失、守卫放行、`ctx.get('harness')` 为 null。
- 隔离：两个子上下文各装一份 manifest，互不影响；父上下文看不到子级段。
- 失败：重复 apply 抛 `StateError`；manifest 引用未注册工具名时不报错（只影响守卫
  语义），由诊断工具列出。

## 7. 开放问题

1. 是否需要把「技能目录」也纳入 manifest？技能由 `conatus_skill` 发现，不在
   `SystemPrompt` 里；纳入会引入包依赖。倾向先不纳入，用 `metadata` 记录。
2. `diffHarness` 的输出格式：纯文本行（`sections: +guide`）还是结构化
   `HarnessDiff`？倾向先纯文本，够用于提交信息与评审。
3. 与 `conatus_agent` 的 `ExecutionProfile` 是否会重复：manifest 持有 profile 而不是
   复制字段，避免两处定义阈值。
4. 是否需要 `loadHarnessFile(path)` / `saveHarnessFile`？等有真实多档制品再定，
   先只做 `toJson` / `fromJson`。

## 8. 落地记录

- 库：`packages/conatus_harness`（manifest / apply / diff，20 测试），进伞包导出与 README。
- 中间件复用：`conatus_agent` 暴露 `toolBudgetMiddleware(budget)`，harness 装配复用同一实现，
  不复制预算逻辑。
- nava：`nava harness list|show|diff|check` + 启动开关 `--harness <路径>`；装配点在
  `ConatusTuiRuntime.create` 末尾，headless 与 TUI 共用。
- 偏差：`diffHarness` 输出纯文本（开放问题 2 已定）；技能目录未纳入（开放问题 1 维持不纳入）。
- 制品发现约定：`nava harness list` 缺省扫描 `./harnesses`，可传目录参数。

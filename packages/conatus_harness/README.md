# conatus_harness

conatus 的可版本化 **harness 制品**（实验性）：一份 manifest 描述执行档位、指令段与
工具边界，`applyHarness` 把它装成一棵可回滚的 Context 子树，`diffHarness` 给出
人可读差异。

来源是 [HarnessPro](https://github.com/pzs19/HarnessPro)（MIT）的 harness 目录形态，
但用 conatus 的原语表达：**一份 harness 就是一棵可重建的 Context 子树**——`provide*`
装配、`EffectScope` 保证撤销。

## 快速开始

```dart
import 'package:conatus_harness/conatus_harness.dart';

final manifest = HarnessManifest(
  name: 'standard',
  profile: const ExecutionProfile(
    name: 'standard',
    reasoningEffort: 'medium',
    budget: ToolBudgetPolicy(),
  ),
  sections: const <PromptSectionSpec>[
    PromptSectionSpec(name: 'guide', text: '先读后写；结束前复核。'),
  ],
  allowedTools: const <String>{'read_file', 'shell'},
  forbiddenTools: const <String>{'rm'},
);

final undo = applyHarness(app, manifest);
// …运行 Agent…
undo(); // 段、工具边界、预算、harness 服务全部回滚
```

## 语义

- **工具边界**：`forbiddenTools` 永远拒绝（`TOOL_FORBIDDEN_BY_HARNESS`），优先于
  `allowedTools`；白名单外的工具返回 `TOOL_NOT_IN_HARNESS`。`allowedTools: null`
  表示不限制。
- **工具预算**：`profile.budget` 装成 `'toolBudget'` 中间件；上下文里已有预算时
  不重复安装，保留原有计数器。
- **装配失败不半途生效**：缺 `tools` / `prompt`、段名冲突、重复装配都在产生副作用
  前抛 `StateError`。
- **reasoningEffort 只是声明**：本包不落 provider 选项，由调用方读取
  `ctx.get<HarnessManifest>('harness')?.profile.reasoningEffort` 透传。
- **JSON 稳定**：集合按字典序输出，两次编码字节一致，适合进 git 做 diff。

## 非目标

不做自动进化、不执行外部脚本、不创建工具、不做远程分发；也不替代宿主自身的配置。

## 测试

```bash
dart test
```

覆盖：JSON 往返（含 null 语义与默认值）、装配/回滚、白名单与禁止名单优先级、预算
复用、重复装配与缺依赖的失败路径、diff 的增删改与输出稳定性。

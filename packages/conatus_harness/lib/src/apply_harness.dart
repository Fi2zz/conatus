/// 把 manifest 装成一棵可回滚的 Context 子树。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'manifest.dart';

/// 装配 [manifest]：prompt 段、工具边界、工具预算与 `harness` 服务。
///
/// 返回的 [Disposer] 撤销本次装配的全部效应（LIFO）；不调用它时随上下文释放
/// 级联回滚。缺少必要服务或重复装配会在**产生副作用前**抛 [StateError]。
Disposer applyHarness(
  Context ctx,
  HarnessManifest manifest, {
  SystemPrompt? prompt,
  ToolRegistry? tools,
}) {
  final SystemPrompt? promptRegistry =
      prompt ?? ctx.get<SystemPrompt>('systemPrompt');
  final ToolRegistry? toolRegistry = tools ?? ctx.get<ToolRegistry>('tools');
  final bool installsBudget = ctx.get<ToolBudget>('toolBudget') == null;
  _validate(ctx, manifest, promptRegistry, toolRegistry, installsBudget);

  final List<Disposer> undo = <Disposer>[];
  for (final PromptSectionSpec spec in manifest.sections) {
    undo.add(ctx.effect(() => promptRegistry!.section(
          PromptSection(
            name: spec.name,
            order: spec.order,
            text: () => spec.text,
          ),
        )));
  }
  if (manifest.allowedTools != null || manifest.forbiddenTools.isNotEmpty) {
    undo.add(ctx.effect(() => toolRegistry!.use(
          harnessToolBoundary(manifest),
          tag: 'harnessTools',
        )));
  }
  if (installsBudget) {
    final ToolBudget budget = ToolBudget(
      policy: manifest.profile.budget,
      telemetry: ctx.get<Telemetry>('telemetry'),
    );
    undo.add(ctx.effect(() => toolRegistry!.use(
          toolBudgetMiddleware(budget),
          tag: 'toolBudget',
        )));
    undo.add(ctx.effect(() => ctx.provide('toolBudget', budget)));
  }
  undo.add(ctx.effect(() => ctx.provide('harness', manifest)));
  return () {
    for (final Disposer disposer in undo.reversed) {
      disposer();
    }
  };
}

/// 工具边界中间件：禁止名单优先，其次白名单。
ToolMiddleware harnessToolBoundary(HarnessManifest manifest) =>
    (ToolCall call, Future<ToolResult> Function() next) async {
      final String name = call.name;
      if (manifest.forbiddenTools.contains(name)) {
        return _deny(
          'TOOL_FORBIDDEN_BY_HARNESS',
          '工具 "$name" 被 harness "${manifest.name}" 禁止',
        );
      }
      final Set<String>? allowed = manifest.allowedTools;
      if (allowed != null && !allowed.contains(name)) {
        return _deny(
          'TOOL_NOT_IN_HARNESS',
          '工具 "$name" 不在 harness "${manifest.name}" 的白名单内',
        );
      }
      return next();
    };

void _validate(
  Context ctx,
  HarnessManifest manifest,
  SystemPrompt? prompt,
  ToolRegistry? tools,
  bool installsBudget,
) {
  if (ctx.get<HarnessManifest>('harness') != null) {
    throw StateError('harness "${manifest.name}" 已装配；先撤销再装配新的');
  }
  final bool needsTools = manifest.allowedTools != null ||
      manifest.forbiddenTools.isNotEmpty ||
      installsBudget;
  if (needsTools && tools == null) {
    throw StateError('applyHarness 需要 tools 服务（工具边界或预算安装）');
  }
  if (manifest.sections.isEmpty) return;
  if (prompt == null) {
    throw StateError(
        'manifest 含 ${manifest.sections.length} 个指令段，但没有 prompt 服务');
  }
  final Set<String> existing = <String>{
    for (final PromptSection section in prompt.sections) section.name,
  };
  for (final PromptSectionSpec spec in manifest.sections) {
    if (existing.contains(spec.name)) {
      throw StateError('prompt 段 "${spec.name}" 已注册');
    }
  }
}

ToolResult _deny(String code, String reason) =>
    ToolResult.failure(reason, error: ToolError(code, reason));

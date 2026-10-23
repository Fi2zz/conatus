/// 阶段化工具预算的执行层：计数、收口拒绝、尾部提醒。
///
/// 提醒**追加在工具结果尾部**而不是改 system prompt：系统前缀一变，整段 KV
/// cache 就失效，省下的 token 会被缓存命中率下降吃回去。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'telemetry.dart';
import 'tool_budget_policy.dart';

/// 一次 Agent 轮次内的工具调用计数器；`ctx.get<ToolBudget>('toolBudget')`。
class ToolBudget {
  ToolBudget({this.policy = const ToolBudgetPolicy(), this.telemetry});

  /// 阶段阈值。
  final ToolBudgetPolicy policy;

  /// 可选遥测导出器（事件 `tool.budget`）。
  final Telemetry? telemetry;

  int _calls = 0;

  /// 已发生的调用数（含被拒的调用）。
  int get calls => _calls;

  /// 归零，开始新一轮。
  void reset() => _calls = 0;

  int tick() => ++_calls;

  void record(String tool, int count, ToolBudgetStage stage, bool denied) {
    telemetry?.emit(TelemetryEvent('tool.budget', data: <String, Object?>{
      'tool': tool,
      'count': count,
      'stage': stage.name,
      'denied': denied,
    }));
  }
}

/// 在工具表上安装预算中间件，返回计数器。
///
/// 与驱逐 / 压缩中间件同层；顺序按「后注册者在内层」决定——预算层只追加尾部
/// 文本，不影响后续压缩对原始内容的判断。
ToolBudget provideToolBudget(
  Context ctx, {
  ToolBudgetPolicy? policy,
  ToolRegistry? tools,
  Telemetry? telemetry,
}) {
  final ToolBudget budget = ToolBudget(
    policy: policy ?? const ToolBudgetPolicy(),
    telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
  );
  final ToolRegistry registry = tools ?? ctx.tools;
  ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          final int count = budget.tick();
          final ToolBudgetStage stage = budget.policy.stageOf(count);
          final String? denial = budget.policy.denialFor(count, call.name);
          if (denial != null) {
            budget.record(call.name, count, stage, true);
            return ToolResult.failure(
              denial,
              error: ToolError('TOOL_BUDGET_EXHAUSTED', denial),
            );
          }
          final ToolResult result = await next();
          budget.record(call.name, count, stage, false);
          final String? note = budget.policy.note(count);
          if (note == null) return result;
          return _withNote(result, note, stage, count);
        },
        tag: 'toolBudget',
      ));
  ctx.provide('toolBudget', budget);
  return budget;
}

ToolResult _withNote(
  ToolResult result,
  String note,
  ToolBudgetStage stage,
  int count,
) {
  final String content = '${result.content}\n\n[budget] $note';
  final Map<String, Object?> meta = <String, Object?>{
    ...result.meta,
    'toolCount': count,
    'toolStage': stage.name,
  };
  if (result.isError) {
    return ToolResult.failure(content, error: result.error, meta: meta);
  }
  return ToolResult.success(content, value: result.value, meta: meta);
}

/// approval 的装配：把审批挂到工具调用链上。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'approval.dart';
import 'telemetry.dart';

/// 在工具表上挂审批中间件：对风险不低于 [threshold] 的工具，先经 [approval]
/// 批准再执行；拒绝或超时返回 `APPROVAL_DENIED` 失败结果。返回撤销函数。
///
/// 工具用 `Tool.pathParams` 声明路径参数时，中间件把它们的取值交给
/// [Approval.preapproved]：已获信任（如某工具对某目录）的调用直接放行，
/// 不产生审批请求。声明路径参数的**低风险**工具同样进入审批——这正是
/// 「读文件也要按目录授权」的落点。
///
/// 若上下文提供了 `'telemetry'`，会额外发出 `approval.requested` /
/// `approval.decided` 审计事件。
Disposer instrumentApproval(
  Context ctx, {
  Approval? approval,
  ToolRegistry? tools,
  Telemetry? telemetry,
  ToolRisk threshold = ToolRisk.high,
  Duration timeout = const Duration(minutes: 5),
}) {
  final Approval gate = approval ?? ctx.approval;
  final ToolRegistry registry = tools ?? ctx.tools;
  final Telemetry? sink = telemetry ?? ctx.get<Telemetry>('telemetry');
  return ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          final Tool? tool = registry.get(call.name);
          if (tool == null) return next();
          final List<String> pathArgs = pathArguments(tool, call);
          final bool risky = tool.riskLevel.index >= threshold.index;
          // 声明路径参数的工具即使低风险也要问：读文件按目录授权正是靠这条。
          final bool gated = risky || pathArgs.isNotEmpty;
          if (!gated) return next();
          final ApprovalRequest request = ApprovalRequest(
            id: 'approval-${DateTime.now().microsecondsSinceEpoch}',
            toolName: call.name,
            arguments: call.arguments,
            description: tool.description,
            pathArgs: pathArgs,
          );
          if (pathArgs.isNotEmpty && await gate.preapproved(request)) {
            return next();
          }
          sink?.emit(
              TelemetryEvent('approval.requested', data: <String, Object?>{
            'tool': call.name,
            'risk': tool.riskLevel.name,
          }));
          final bool approved = await gate
              .request(request)
              .timeout(timeout, onTimeout: () => false);
          sink?.emit(TelemetryEvent('approval.decided', data: <String, Object?>{
            'tool': call.name,
            'approved': approved,
          }));
          if (!approved) {
            return ToolResult.failure(
              '用户拒绝执行 "${call.name}"',
              error: const ToolError('APPROVAL_DENIED', 'approval denied'),
            );
          }
          return next();
        },
      ));
}

/// 取出 [tool] 声明的路径参数取值（非空字符串；支持 `a.b` 形式的嵌套取值）。
List<String> pathArguments(Tool tool, ToolCall call) {
  final List<String> declared = tool.pathParams;
  if (declared.isEmpty) return const <String>[];
  final List<String> values = <String>[];
  for (final String key in declared) {
    final Object? raw = _lookup(call.arguments, key);
    final String value = raw == null ? '' : '$raw'.trim();
    if (value.isNotEmpty) values.add(value);
  }
  return values;
}

Object? _lookup(Map<String, Object?> args, String key) {
  final int dot = key.indexOf('.');
  if (dot < 0) return args[key];
  final Object? nested = args[key.substring(0, dot)];
  if (nested is! Map) return null;
  return nested[key.substring(dot + 1)];
}

/// 提供 `'approval'` 服务并安装审批拦截，返回审批端口。
///
/// 默认 [AutoApproval] 拒绝（安全优先）：显式装 `AutoApproval(true)` 便于开发，
/// 或 `AskUserApproval` / `RuleBasedApproval` 供产品使用。
///
/// [instrument] 为 `false` 时只提供服务、不挂拦截——适合拦截阈值由别处动态
/// 决定的装配方（自行调用 [instrumentApproval]，避免两层中间件重复询问）。
Approval provideApproval(
  Context ctx, {
  Approval? approval,
  ToolRegistry? tools,
  ToolRisk threshold = ToolRisk.high,
  Duration timeout = const Duration(minutes: 5),
  bool instrument = true,
}) {
  final Approval gate = approval ?? AutoApproval(false);
  ctx.provide('approval', gate);
  if (instrument) {
    instrumentApproval(
      ctx,
      approval: gate,
      tools: tools,
      threshold: threshold,
      timeout: timeout,
    );
  }
  ctx.onDispose(() => unawaited(gate.close()));
  return gate;
}

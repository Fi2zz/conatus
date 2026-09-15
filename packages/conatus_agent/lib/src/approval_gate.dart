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
          if (tool == null || tool.riskLevel.index < threshold.index) {
            return next();
          }
          final ApprovalRequest request = ApprovalRequest(
            id: 'approval-${DateTime.now().microsecondsSinceEpoch}',
            toolName: call.name,
            arguments: call.arguments,
            description: tool.description,
          );
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

/// 提供 `'approval'` 服务并安装审批拦截，返回审批端口。
///
/// 默认 [AutoApproval] 拒绝（安全优先）：显式装 `AutoApproval(true)` 便于开发，
/// 或 `AskUserApproval` / `RuleBasedApproval` 供产品使用。
Approval provideApproval(
  Context ctx, {
  Approval? approval,
  ToolRegistry? tools,
  ToolRisk threshold = ToolRisk.high,
  Duration timeout = const Duration(minutes: 5),
}) {
  final Approval gate = approval ?? AutoApproval(false);
  ctx.provide('approval', gate);
  instrumentApproval(
    ctx,
    approval: gate,
    tools: tools,
    threshold: threshold,
    timeout: timeout,
  );
  ctx.onDispose(() => unawaited(gate.close()));
  return gate;
}

/// 权限中间件：最外层评估每次工具调用（allow / ask / deny）。
///
/// 与 [instrumentApproval] 的分工：审批只管「风险阈值 + 人」，权限先按
/// `config → project → session` 的规则判定。挂在根上下文最外层（先注册）后，
/// hooks / 驱逐 / lint / story 都只能看到被放行的调用；会话切换只替换
/// [PermissionScopeSlot]，不重挂中间件。
///
/// 遥测：ask 流程发 `permission.requested` / `permission.decided`。旧的
/// `approval.requested` / `approval.decided` 只由仍直接使用
/// `instrumentApproval` 的调用方（如 `provideApproval`）发出；非 inherit
/// 子代理现在也走本中间件的子作用域，不再产生 `approval.*`。
///
/// 零配置兼容：没有任何规则命中时按 [PermissionScope.askThreshold] 回退到旧
/// 审批行为，且（仅在交互模式下）声明了 `Tool.pathParams` 的低风险工具仍会
/// 询问——这正是目录信任的落点，由 [Approval.preapproved] 决定是否免打扰。
/// headless 没人可问，路径兜底不触发（旧行为也不拦）。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../approval.dart';
import '../approval_gate.dart' show kApprovalMiddlewareTag;
import '../telemetry.dart';
import 'permission_decision.dart';
import 'permission_effect.dart';
import 'permission_evaluator.dart';
import 'permission_rule.dart';
import 'permission_scope_slot.dart';

/// 在工具表上挂权限中间件；返回撤销函数。
///
/// [interactive] 为 `false`（headless）时 `ask` 一律拒绝并返回
/// `PERMISSION_ASK_UNATTENDED`；显式 `deny` 照常拒绝，显式 `allow` 照常放行。
/// [timeout] 只约束等人的时长，不包住工具执行体（见 `ToolRegistry._chain`）。
// REASON: 装配入口按能力缝预留注入点，参数形状与既有 instrumentApproval 对齐。
Disposer instrumentPermission(
  Context ctx, {
  ToolRegistry? tools,
  PermissionScopeSlot? scope,
  Approval? approval,
  Telemetry? telemetry,
  bool interactive = true,
  Duration timeout = const Duration(minutes: 30),
}) {
  final _PermissionGate gate = _PermissionGate(
    ctx: ctx,
    registry: tools ?? ctx.tools,
    slot: scope ??
        ctx.get<PermissionScopeSlot>(kPermissionScopeService) ??
        PermissionScopeSlot(),
    approval: approval,
    telemetry: telemetry,
    interactive: interactive,
    timeout: timeout,
  );
  return ctx.effect(
    () => gate.registry.use(gate.handle, tag: kApprovalMiddlewareTag),
  );
}

/// 绑定根上下文的中间件实例。
class _PermissionGate {
  _PermissionGate({
    required this.ctx,
    required this.registry,
    required this.slot,
    this.approval,
    this.telemetry,
    required this.interactive,
    required this.timeout,
  });

  final Context ctx;
  final ToolRegistry registry;
  final PermissionScopeSlot slot;
  final Approval? approval;
  final Telemetry? telemetry;
  final bool interactive;
  final Duration timeout;

  Future<ToolResult> handle(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final Tool? tool = registry.get(call.name);
    if (tool == null) return next();
    final PermissionDecision decision = PermissionEvaluator(
      interactive: interactive,
      workdir:
          ctx.get<String>('permissionWorkdir') ?? ctx.get<String>('workdir'),
    ).evaluate(tool, call, slot.current);
    if (decision.effect == PermissionEffect.allow) return next();
    if (decision.effect == PermissionEffect.deny) return _denied(decision);
    return _ask(call, tool, decision, next);
  }

  Future<ToolResult> _ask(
    ToolCall call,
    Tool tool,
    PermissionDecision decision,
    Future<ToolResult> Function() next,
  ) async {
    final Approval? gate =
        interactive ? (approval ?? ctx.get<Approval>('approval')) : null;
    if (gate == null) {
      return ToolResult.failure(
        '权限规则要求确认 "${call.name}"，但当前无人可应答',
        error: const ToolError(
          'PERMISSION_ASK_UNATTENDED',
          'permission ask unattended',
        ),
      );
    }
    final ApprovalRequest request = _request(call, tool, decision);
    if (decision.fallback &&
        decision.pathArgs.isNotEmpty &&
        await gate.preapproved(request)) {
      return next();
    }
    final Telemetry? sink = telemetry ?? ctx.get<Telemetry>('telemetry');
    _emit(sink, 'permission.requested', decision, approved: null);
    final bool approved =
        await gate.request(request).timeout(timeout, onTimeout: () => false);
    _emit(sink, 'permission.decided', decision, approved: approved);
    if (!approved) {
      return ToolResult.failure(
        '用户拒绝执行 "${call.name}"',
        error: const ToolError('APPROVAL_DENIED', 'approval denied'),
      );
    }
    return next();
  }

  ApprovalRequest _request(
          ToolCall call, Tool tool, PermissionDecision decision) =>
      ApprovalRequest(
        id: 'permission-${DateTime.now().microsecondsSinceEpoch}',
        toolName: call.name,
        arguments: call.arguments,
        description: tool.description,
        pathArgs: decision.pathArgs,
        action: decision.verdict.action,
        resources: decision.verdict.resources,
        rule: decision.verdict.rule?.toString(),
      );

  ToolResult _denied(PermissionDecision decision) {
    final PermissionRule? rule = decision.verdict.rule;
    final String summary = rule?.toString() ??
        '${decision.action} ${decision.resources.join(',')}';
    return ToolResult.failure(
      'Blocked by permission rule: $summary',
      error: ToolError('PERMISSION_DENIED', 'permission denied: $summary'),
    );
  }

  void _emit(
    Telemetry? sink,
    String name,
    PermissionDecision decision, {
    required bool? approved,
  }) {
    sink?.emit(TelemetryEvent(name, data: <String, Object?>{
      'action': decision.action,
      'resources': decision.resources,
      'effect': decision.effect.name,
      if (approved != null) 'approved': approved,
    }));
  }
}

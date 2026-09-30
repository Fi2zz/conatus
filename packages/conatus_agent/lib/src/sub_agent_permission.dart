/// 子代理的权限模式：决定子 Agent 的工具调用如何过审批。
///
/// 与宿主全局权限模式（TUI 三档）不同，这是**子代理级**策略，对齐 Claude Code
/// 子代理的 `permissionMode` 字段。宿主在装配时给默认档，模型可在 `spawn_agent`
/// 里请求，但只允许**收紧**（见 [tightenBelow]）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'approval.dart';
import 'approval_gate.dart';

/// 子代理权限模式。
enum SubAgentPermission {
  /// 继承宿主权限：走宿主同一条审批管线（默认）。
  inherit,

  /// 只读：仅 low 风险工具，medium/high 直接拒（不弹审批）。
  readonly,

  /// 每个子工具调用都要确认（阈值 low）。
  ask,

  /// 子调用免审批（仍在 Layer 2 沙箱内；high 工具仍被白名单风险上限挡掉）。
  auto,
}

extension SubAgentPermissionX on SubAgentPermission {
  /// 宽松度排名（越大越宽）。模型只能请求 `rank <= 默认` 的档位。
  int get rank => switch (this) {
        SubAgentPermission.readonly => 0,
        SubAgentPermission.ask => 1,
        SubAgentPermission.inherit => 2,
        SubAgentPermission.auto => 3,
      };
}

/// 解析模式标识；无法识别返回 `null`。
SubAgentPermission? parseSubAgentPermission(String raw) {
  final String key = raw.trim().toLowerCase();
  for (final SubAgentPermission mode in SubAgentPermission.values) {
    if (mode.name == key) return mode;
  }
  return null;
}

/// 在默认档 [base] 之下取更严的一档：请求缺失或无法识别时用 [base]，
/// 请求比 [base] 宽时回落到 [base]（模型只能收紧，不能放宽）。
SubAgentPermission tightenBelow(SubAgentPermission base, String? requested) {
  final SubAgentPermission? req =
      requested == null ? null : parseSubAgentPermission(requested);
  if (req == null) return base;
  return req.rank <= base.rank ? req : base;
}

/// 把 [mode] 落到子工具注册表上。
///
/// [child] 用于挂审批中间件（随子上下文释放）。调用方需已按模式决定是否从继承
/// 管线里排除宿主审批层：非 [SubAgentPermission.inherit] 时应排除
/// [kApprovalMiddlewareTag]，否则会与本函数装的策略叠成两次审批。
void applySubAgentPermission(
  Context child,
  ToolRegistry childTools,
  SubAgentPermission mode, {
  Approval? gate,
}) {
  switch (mode) {
    case SubAgentPermission.inherit:
    case SubAgentPermission.auto:
      return;
    case SubAgentPermission.readonly:
      childTools.guard(_readonlyGuard(childTools));
    case SubAgentPermission.ask:
      final Approval? approver = gate;
      if (approver == null) {
        // 无人可问（headless 无审批服务）：按只读处理，而不是把所有子工具都
        // 静默拒掉——「无法确认」不等于「什么都不能做」，低风险读取照常。
        childTools.guard(_readonlyGuard(childTools));
        return;
      }
      instrumentApproval(
        child,
        tools: childTools,
        approval: approver,
        threshold: ToolRisk.low,
      );
  }
}

/// 只读守卫：非 low 风险工具一律拒绝。
ToolGuard _readonlyGuard(ToolRegistry tools) => (ToolCall call) {
      final Tool? tool = tools.get(call.name);
      if (tool == null || tool.riskLevel == ToolRisk.low) return null;
      return '子代理为只读模式，拒绝工具 "${call.name}"';
    };

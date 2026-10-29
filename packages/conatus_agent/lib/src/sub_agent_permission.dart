/// 子代理的权限模式：决定子 Agent 的工具调用如何过审批。
///
/// 与宿主全局权限模式（TUI 三档）不同，这是**子代理级**策略，对齐 Claude Code
/// 子代理的 `permissionMode` 字段。宿主在装配时给默认档，模型可在 `task`
/// 里请求，但只允许**收紧**（见 [tightenBelow]）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'approval.dart';
import 'approval_gate.dart' show kApprovalMiddlewareTag;
import 'permissions/permission_effect.dart';
import 'permissions/permission_gate.dart';
import 'permissions/permission_rule.dart';
import 'permissions/permission_scope.dart';
import 'permissions/permission_scope_slot.dart';

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

/// 一次子代理权限装配的附加选项。
class SubAgentPermissionOptions {
  /// 创建选项。
  const SubAgentPermissionOptions({
    this.gate,
    this.extraRules = const <PermissionRule>[],
  });

  /// 审批端口；`null` 表示无人可问。
  final Approval? gate;

  /// Agent profile 自带的规则。
  final List<PermissionRule> extraRules;
}

/// 把 [mode] 落到子工具注册表上。
///
/// [child] 用于挂审批中间件（随子上下文释放）。调用方需已按模式决定是否从继承
/// 管线里排除宿主审批层：非 [SubAgentPermission.inherit] 时应排除
/// [kApprovalMiddlewareTag]，否则会与本函数装的策略叠成两次审批。
///
/// 根上下文的 `instrumentPermission` 也打同一个 tag，因此这条排除同时覆盖
/// 「权限 + 审批」两层；[SubAgentPermission.inherit] 的子代理才会复用宿主
/// 作用域（`PermissionScopeSlot`）与其规则。
///
/// 非 inherit 档不再只靠 readonly guard / 审批层：会装一个**子权限中间件**，
/// 继承宿主的 deny / ask 规则（ask 档还要再过滤掉父级 allow，否则「子代理每次
/// 都要确认」会被父级 allow 直接放行），再按模式收紧阈值：
/// readonly / auto → 不询问（readonly 另有风险守卫），ask → 阈值 low。
///
/// [options] 的 `extraRules` 是 Agent profile 自带的规则。inherit 档传非空规则
/// 时也会装子中间件（宿主中间件已被排除），阈值沿用宿主的
/// [PermissionScope.askThreshold]。
void applySubAgentPermission(
  Context child,
  ToolRegistry childTools,
  SubAgentPermission mode, {
  SubAgentPermissionOptions options = const SubAgentPermissionOptions(),
}) {
  final List<PermissionRule> extraRules = options.extraRules;
  switch (mode) {
    case SubAgentPermission.inherit:
      if (extraRules.isNotEmpty) {
        _installChildPermission(child, childTools, mode, options);
      }
    case SubAgentPermission.auto:
      _installChildPermission(child, childTools, mode, options);
    case SubAgentPermission.readonly:
      childTools.guard(_readonlyGuard(childTools));
      _installChildPermission(child, childTools, mode, options);
    case SubAgentPermission.ask:
      if (options.gate == null) {
        // 无人可问（headless 无审批服务）：按只读处理，而不是把所有子工具都
        // 静默拒掉——「无法确认」不等于「什么都不能做」，低风险读取照常。
        childTools.guard(_readonlyGuard(childTools));
        _installChildPermission(
          child,
          childTools,
          SubAgentPermission.readonly,
          options,
        );
        return;
      }
      _installChildPermission(child, childTools, mode, options);
  }
}

/// 装子代理自己的权限中间件：宿主规则 + profile 规则 + 按模式收紧的兜底阈值。
void _installChildPermission(
  Context child,
  ToolRegistry childTools,
  SubAgentPermission mode,
  SubAgentPermissionOptions options,
) {
  final Approval? gate = options.gate;
  final PermissionScope? host =
      child.get<PermissionScopeSlot>(kPermissionScopeService)?.current;
  final ToolRisk? threshold = switch (mode) {
    SubAgentPermission.ask => ToolRisk.low,
    SubAgentPermission.inherit => host?.askThreshold,
    SubAgentPermission.auto || SubAgentPermission.readonly => null,
  };
  final List<PermissionRule> inherited =
      host?.rules ?? const <PermissionRule>[];
  instrumentPermission(
    child,
    tools: childTools,
    scope: PermissionScopeSlot(PermissionScope(
      // ask 档要逐次确认：父级 allow 会把「本应询问」的调用直接放行，
      // 只继承更严的 deny / ask 才符合子代理语义。
      rules: _childRules(
        mode == SubAgentPermission.ask
            ? <PermissionRule>[
                for (final PermissionRule rule in inherited)
                  if (rule.effect != PermissionEffect.allow) rule,
              ]
            : inherited,
        options.extraRules,
      ),
      askThreshold: threshold,
      agentId: host?.agentId ?? 'build',
    )),
    approval: gate,
    interactive: gate != null,
  );
}

/// 合并宿主规则与 profile 规则：profile 的 allow 不能放宽宿主已有的 deny / ask。
List<PermissionRule> _childRules(
  List<PermissionRule> hostRules,
  List<PermissionRule> extraRules,
) {
  if (extraRules.isEmpty) return hostRules;
  final Set<String> restricted = <String>{
    for (final PermissionRule rule in hostRules)
      if (rule.effect != PermissionEffect.allow) rule.action,
  };
  return <PermissionRule>[
    ...hostRules,
    for (final PermissionRule rule in extraRules)
      if (rule.effect != PermissionEffect.allow ||
          !restricted.contains(rule.action))
        rule,
  ];
}

/// 只读守卫：非 low 风险工具一律拒绝。
ToolGuard _readonlyGuard(ToolRegistry tools) => (ToolCall call) {
      final Tool? tool = tools.get(call.name);
      if (tool == null || tool.riskLevel == ToolRisk.low) return null;
      return '子代理为只读模式，拒绝工具 "${call.name}"';
    };

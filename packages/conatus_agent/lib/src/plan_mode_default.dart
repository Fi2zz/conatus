/// plan-mode 的默认实现与装配。
///
/// [DefaultPlanMode] 把状态变更接到四个能力缝上：`session` 持久化
/// `plan/mode` 事件、`systemPrompt` 注入/撤销 `plan:policy` 段、`approval`
/// 审批计划（缺省自动批准）、`telemetry` 埋点。全部可选，缺省时降级。
/// [providePlanMode] 一次装好服务、注册 `exit_plan_mode` 工具，并挂拦截
/// 中间件：Plan Mode 激活时拒绝 `riskLevel >= medium` 的工具调用
/// （`PLAN_MODE_BLOCKED`），不限制只读工具。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'approval.dart';
import 'exit_plan_mode.dart';
import 'plan.dart';
import 'plan_mode.dart';
import 'telemetry.dart';

/// [PlanMode] 的默认实现。
class DefaultPlanMode implements PlanMode {
  /// 各 seam 显式传入优先；缺省时从 [ctx] 惰性解析；再缺省则降级
  /// （不持久化 / 无提示词注入 / 自动批准 / 无埋点）。
  DefaultPlanMode({
    Session? session,
    SystemPrompt? prompt,
    Approval? approval,
    Telemetry? telemetry,
    Context? ctx,
  })  : _session = session,
        _prompt = prompt,
        _approval = approval,
        _telemetry = telemetry,
        _ctx = ctx {
    final Session? resolved = resolveSession();
    if (resolved != null &&
        restorePlanModeState(resolved) == PlanModeState.active) {
      _state = PlanModeState.active;
      attachPolicy();
    }
  }

  final Context? _ctx;
  Session? _session;
  SystemPrompt? _prompt;
  Approval? _approval;
  Telemetry? _telemetry;
  PlanModeState _state = PlanModeState.inactive;
  Disposer? _policyDisposer;
  bool _disposed = false;

  final StreamController<PlanModeState> _changes =
      StreamController<PlanModeState>.broadcast();

  @override
  PlanModeState get state => _state;

  @override
  Stream<PlanModeState> get changes => _changes.stream;

  /// 解析 session（显式 > 上下文服务），首次解析后缓存。
  Session? resolveSession() => _session ??= _ctx?.get<Session>('session');

  SystemPrompt? _resolvePrompt() =>
      _prompt ??= _ctx?.get<SystemPrompt>('systemPrompt');

  Approval? _resolveApproval() => _approval ??= _ctx?.get<Approval>('approval');

  Telemetry? _resolveTelemetry() =>
      _telemetry ??= _ctx?.get<Telemetry>('telemetry');

  @override
  void enter() {
    if (_state == PlanModeState.active || _disposed) return;
    attachPolicy();
    resolveSession()
        ?.append(kPlanModeEvent, data: <String, Object?>{'state': 'active'});
    _state = PlanModeState.active;
    _changes.add(_state);
    _resolveTelemetry()?.emit(TelemetryEvent('plan.entered'));
  }

  @override
  void exit() {
    if (_state != PlanModeState.active) return;
    _policyDisposer?.call();
    _policyDisposer = null;
    resolveSession()
        ?.append(kPlanModeEvent, data: <String, Object?>{'state': 'inactive'});
    _state = PlanModeState.inactive;
    _changes.add(_state);
    _resolveTelemetry()?.emit(TelemetryEvent('plan.exited'));
  }

  /// 注册 `plan:policy` 段（重复调用先撤销旧段，幂等）。
  void attachPolicy() {
    final SystemPrompt? prompt = _resolvePrompt();
    if (prompt == null) return;
    _policyDisposer?.call();
    _policyDisposer = prompt.section(PromptSection(
      name: 'plan:policy',
      order: 100,
      text: () => kPlanModePolicy,
    ));
  }

  @override
  Future<bool> submitPlan(Plan plan) async {
    _resolveTelemetry()
        ?.emit(TelemetryEvent('plan.submitted', data: <String, Object?>{
      'goal': plan.goal,
      'steps': plan.steps.length,
    }));
    final Approval? gate = _resolveApproval();
    if (gate == null) return true;
    return gate.requestPlan(plan);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_state == PlanModeState.active) exit();
    unawaited(_changes.close());
  }
}

/// 提供 `'planMode'` 服务，注册 `exit_plan_mode` 工具并挂拦截中间件。
///
/// 依赖（全部可选，缺省时降级）：`session` 持久化、`systemPrompt` 注入、
/// `approval` 计划审批（缺省自动批准）、`telemetry` 埋点；`tools` 必需，
/// 缺省取 `ctx.tools`。
PlanMode providePlanMode(
  Context ctx, {
  PlanMode? planMode,
  Session? session,
  SystemPrompt? prompt,
  Approval? approval,
  ToolRegistry? tools,
  Telemetry? telemetry,
}) {
  final PlanMode resolved = planMode ??
      DefaultPlanMode(
        session: session,
        prompt: prompt,
        approval: approval,
        telemetry: telemetry,
        ctx: ctx,
      );
  final ToolRegistry registry = tools ?? ctx.tools;
  ctx.provide('planMode', resolved);
  ctx.effect(() => registry.register(ExitPlanModeTool(planMode: resolved)));
  _blockMutations(ctx, registry, resolved);
  ctx.onDispose(resolved.dispose);
  return resolved;
}

/// Plan Mode 激活时拒绝 `riskLevel >= medium` 的工具调用。
void _blockMutations(Context ctx, ToolRegistry registry, PlanMode planMode) {
  ctx.effect(() => registry.use(
        (ToolCall call, Future<ToolResult> Function() next) async {
          if (planMode.state != PlanModeState.active) return next();
          final Tool? tool = registry.get(call.name);
          if (tool == null || tool.riskLevel.index < ToolRisk.medium.index) {
            return next();
          }
          return ToolResult.failure(
            'Plan mode is active. Please submit a plan through '
            'exit_plan_mode first.',
            error: const ToolError('PLAN_MODE_BLOCKED', 'plan mode is active'),
          );
        },
      ));
}

/// plan-mode 插件：Plan Mode 的端口与词汇。
///
/// Plan Mode 是行为引导：激活时向 system prompt 注入 `plan:policy` 段
/// （软指引），`exit_plan_mode` 工具提交计划走 [Approval] 评审闭环；状态以
/// `plan/mode` 事件持久化到 [Session]（append-only，折叠最后一条）。派生状态
/// 只折叠会话自身后缀（[Session.ownEvents]），fork 出的会话不继承 Plan Mode。
/// 与 `plan.dart` 的 `plan_write` 共存：前者写草稿，后者提交定稿。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'plan.dart';

/// Plan Mode 变更事件类型。
const String kPlanModeEvent = 'plan/mode';

/// `plan:policy` 段文本：只提 `web_search` 与 `ask_user`，不提读本地文件
/// （语音优先场景）。
const String kPlanModePolicy =
    'You are in plan mode. Use web_search and ask_user to gather '
    'information before presenting a complete plan through '
    'exit_plan_mode. Do not execute mutating operations until the '
    'plan is approved.';

/// Plan Mode 状态。
enum PlanModeState { inactive, active }

/// Plan Mode 服务端口。
abstract class PlanMode {
  /// 当前状态。
  PlanModeState get state;

  /// 进入 Plan Mode。
  void enter();

  /// 退出 Plan Mode。由审批通过后调用。
  void exit();

  /// 提交计划供审批。返回用户是否批准。
  Future<bool> submitPlan(Plan plan);

  /// 状态变更流。
  Stream<PlanModeState> get changes;

  /// 释放资源。幂等。
  void dispose();
}

/// `ctx.planMode`：当前上下文可见的 Plan Mode 服务。
extension PlanModeContext on Context {
  /// 取当前上下文可见的 [PlanMode]（未提供时抛 [StateError]）。
  PlanMode get planMode => require<PlanMode>('planMode');
}

/// 折叠会话自身后缀里最后一个 `plan/mode` 事件，还原 Plan Mode 状态。
PlanModeState restorePlanModeState(Session session) {
  for (final SessionEvent event in session.ownEvents.reversed) {
    if (event.type != kPlanModeEvent) continue;
    final Object? data = event.data;
    if (data is Map && data['state'] == 'active') {
      return PlanModeState.active;
    }
    return PlanModeState.inactive;
  }
  return PlanModeState.inactive;
}

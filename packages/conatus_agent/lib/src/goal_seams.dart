/// goal 插件的能力缝集合。
///
/// [GoalSeams] 集中解析 `session` / `systemPrompt` / `approval` / `telemetry`
/// 四个可选依赖（显式传入优先，缺省从 [Context] 惰性解析，再缺省降级），
/// 并承载它们的全部使用点：持久化 `goal/changed` 事件、注入/撤销 `goal` 段、
/// clear / complete 确认、埋点。不从 barrel 导出，属于包内实现细节。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'approval.dart';
import 'goal.dart';
import 'telemetry.dart';

/// goal 的四个能力缝及其使用点。
class GoalSeams {
  /// [ctx] 仅用于惰性解析未显式传入的 seam。
  GoalSeams({
    Session? session,
    SystemPrompt? prompt,
    Approval? approval,
    Telemetry? telemetry,
    Context? ctx,
  })  : _session = session,
        _prompt = prompt,
        _approval = approval,
        _telemetry = telemetry,
        _ctx = ctx;

  final Context? _ctx;
  Session? _session;
  SystemPrompt? _prompt;
  Approval? _approval;
  Telemetry? _telemetry;
  Disposer? _sectionDisposer;

  /// 解析 session（显式 > 上下文服务），首次解析后缓存。
  Session? resolveSession() => _session ??= _ctx?.get<Session>('session');

  /// 显式绑定 session（restore 用）；之后 [resolveSession] 优先返回它。
  void bindSession(Session session) {
    _session = session;
  }

  SystemPrompt? _resolvePrompt() =>
      _prompt ??= _ctx?.get<SystemPrompt>('systemPrompt');

  Approval? _resolveApproval() => _approval ??= _ctx?.get<Approval>('approval');

  Telemetry? _resolveTelemetry() =>
      _telemetry ??= _ctx?.get<Telemetry>('telemetry');

  /// 追加一条 `goal/changed` 事件（整值替换）。
  void appendEvent(Goal goal) =>
      resolveSession()?.append(kGoalEvent, data: goal.toJson());

  /// 发出一个 `goal.*` 埋点事件。
  void emit(String eventName, Goal goal) =>
      _resolveTelemetry()?.emit(TelemetryEvent(eventName,
          data: <String, Object?>{'id': goal.id, 'status': goal.status.name}));

  /// 经 approval 确认动作；gate 不可用自动批准，拒绝抛 [GoalException]。
  Future<void> confirm(String toolName, String description, Goal goal) async {
    final Approval? gate = _resolveApproval();
    if (gate == null) return;
    final bool ok = await gate.request(ApprovalRequest(
      id: '$toolName-${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      arguments: goal.toJson(),
      description: description,
    ));
    if (!ok) throw const GoalException('cancelled', '用户取消');
  }

  /// 按 [current] 的最新值同步 `goal` 段：有目标时注入（order 50，排在
  /// persona 之后、`plan:policy` 之前），无目标时撤销。段文本闭包每次
  /// 装配重新求值，改动在下一轮生效。
  void syncSection(Goal? Function() current) {
    final Goal? goal = current();
    if (goal == null) {
      detachSection();
      return;
    }
    if (_sectionDisposer != null) return;
    _sectionDisposer = _resolvePrompt()?.section(PromptSection(
        name: 'goal', order: 50, text: () => GoalSeams.sectionText(current)));
  }

  /// `goal` 段文本；无目标时为空串。
  static String sectionText(Goal? Function() current) {
    final Goal? goal = current();
    if (goal == null) return '';
    final String progress =
        goal.round > 0 ? '\n进度：第 ${goal.round} / ${goal.maxRounds} 轮' : '';
    return '[当前目标]\n${goal.text}$progress';
  }

  /// 撤销 `goal` 段（幂等）。
  void detachSection() {
    _sectionDisposer?.call();
    _sectionDisposer = null;
  }
}

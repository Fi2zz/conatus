/// approval 插件：高危工具执行前的人机协作审批。
///
/// 审批是一个能力缝：[Approval] 只声明 `request` 与 `pending`，默认实现有
/// 自动批准/拒绝（测试）、按规则批准、经 `ask_user` 询问用户；超时视为拒绝。
/// [instrumentApproval] 把它挂到 [ToolRegistry] 的调用链上，只对不低于阈值的
/// 工具拦截；`provideApproval` 一次装好服务与拦截。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'plan.dart';

/// 一条审批请求。
class ApprovalRequest {
  ApprovalRequest({
    required this.id,
    required this.toolName,
    this.arguments = const <String, Object?>{},
    this.description = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 请求 id。
  final String id;

  /// 待审批的工具名（`plan` 表示整份计划）。
  final String toolName;

  /// 工具参数。
  final Map<String, Object?> arguments;

  /// 面向用户的说明。
  final String description;

  /// 请求时间。
  final DateTime createdAt;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'toolName': toolName,
        'arguments': arguments,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'ApprovalRequest($id, $toolName)';
}

/// 审批端口。
abstract class Approval {
  /// 是否批准该请求。
  Future<bool> request(ApprovalRequest request);

  /// 待处理请求流（供 UI/外部系统订阅）。
  Stream<ApprovalRequest> get pending;

  /// 一次性审批整份计划（默认走同一条 [request]，`toolName` 为 `plan`）。
  Future<bool> requestPlan(Plan plan) => request(ApprovalRequest(
        id: 'plan-${DateTime.now().microsecondsSinceEpoch}',
        toolName: 'plan',
        arguments: plan.toJson(),
        description: plan.summary(),
      ));

  /// 释放资源（默认无操作）。幂等。
  Future<void> close() async {}
}

/// 自动批准或拒绝（测试/默认provider）。
class AutoApproval extends Approval {
  AutoApproval(this.approved);

  /// 是否批准。
  final bool approved;

  final StreamController<ApprovalRequest> _pending =
      StreamController<ApprovalRequest>.broadcast();

  /// 收到过的请求数。
  int requests = 0;

  @override
  Stream<ApprovalRequest> get pending => _pending.stream;

  @override
  Future<bool> request(ApprovalRequest request) async {
    requests++;
    if (!_pending.isClosed) _pending.add(request);
    return approved;
  }

  @override
  Future<void> close() async {
    if (!_pending.isClosed) await _pending.close();
  }
}

/// 按规则批准：返回 true 即放行。
class RuleBasedApproval extends Approval {
  RuleBasedApproval({required this.allow});

  /// 判定规则。
  final bool Function(ApprovalRequest request) allow;

  final StreamController<ApprovalRequest> _pending =
      StreamController<ApprovalRequest>.broadcast();

  @override
  Stream<ApprovalRequest> get pending => _pending.stream;

  @override
  Future<bool> request(ApprovalRequest request) async {
    if (!_pending.isClosed) _pending.add(request);
    return allow(request);
  }

  @override
  Future<void> close() async {
    if (!_pending.isClosed) await _pending.close();
  }
}

/// 经 `ask_user` 询问用户；超时或异常视为拒绝。
class AskUserApproval extends Approval {
  AskUserApproval({
    required this.askUser,
    this.yesWords = const <String>{'y', 'yes', '是', '允许', '可以', '好'},
    Duration? timeout,
  }) : timeout = timeout ?? const Duration(minutes: 5);

  /// 提问器。
  final AskUser askUser;

  /// 视为「是」的回答（小写比较）。
  final Set<String> yesWords;

  /// 审批超时，超时视为拒绝。
  final Duration timeout;

  final StreamController<ApprovalRequest> _pending =
      StreamController<ApprovalRequest>.broadcast();

  @override
  Stream<ApprovalRequest> get pending => _pending.stream;

  @override
  Future<bool> request(ApprovalRequest request) async {
    if (!_pending.isClosed) _pending.add(request);
    final String prompt = '是否允许执行 "${request.toolName}"？'
        '${request.description.isEmpty ? '' : '（${request.description}）'} (y/N)';
    try {
      final String answer = await askUser.ask(prompt).timeout(timeout);
      return yesWords.contains(answer.trim().toLowerCase());
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (!_pending.isClosed) await _pending.close();
  }
}

/// `ctx.approval`：当前上下文可见的审批端口。
extension ApprovalContext on Context {
  /// 取当前上下文可见的 [Approval]（未提供时抛 [StateError]）。
  Approval get approval => require<Approval>('approval');
}

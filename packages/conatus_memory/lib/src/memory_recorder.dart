/// 轮次记录器：把写入策略接到 Agent Loop 的轮次生命周期上。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'memory_write_policy.dart';

/// 一轮结束后按 [policy] 决定是否写入 [memory]。
///
/// 失败语义：策略判定为不写、轮次失败、未开始轮次都不写；写入失败（存储后端
/// 抛错）被吞掉，不影响当轮结果。
class MemoryRecorder implements AgentTurnTracker {
  MemoryRecorder({
    required this.memory,
    this.policy = const PolicyMemoryWritePolicy(),
    this.onStore,
  });

  /// 长记忆库（存储机制）。
  final MemoryStore memory;

  /// 写入策略。
  final MemoryWritePolicy policy;

  /// 每次判定后的观察口（含不写的判定），供埋点 / 测试使用。
  final void Function(MemoryWriteDecision decision)? onStore;

  String? _input;

  @override
  Future<void> beginTurn(String userInput) async {
    _input = userInput;
  }

  @override
  Future<void> endTurn({Object? result, Object? error}) async {
    final String? input = _input;
    _input = null;
    if (input == null || error != null) return;
    final MemoryWriteDecision decision = policy.review(
      userInput: input,
      reply: result is String ? result : '',
      existing: memory.entries,
    );
    onStore?.call(decision);
    final String? text = decision.text;
    if (text == null) return;
    try {
      await memory.remember(text, tags: const <String>{'conversation'});
    } on Object {
      // fail-open：记忆是尽力而为，写入失败不能影响一轮对话的结果。
    }
  }
}

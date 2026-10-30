/// `/undo` 的撤销点与结果类型。
///
/// [RevertStage] 只在内存里存活一轮撤销——用户发下一条 prompt（提交语义）
/// 或 `/redo` 之后即清空，不做持久化。
library;

import '../../conatus_checkpoint.dart';

/// 一次撤销留下的状态，供 `/redo` 回到撤销前。
class RevertStage {
  const RevertStage({
    required this.originalSessionId,
    required this.forkSessionId,
    required this.fromTurn,
    required this.toTurn,
    required this.prompt,
  });

  /// 撤销前的会话 id（`/redo` 切回它并恢复到 [fromTurn]）。
  final String originalSessionId;

  /// 撤销后切过去的会话 id（对话切点处的 fork，或全新空会话）。
  final String forkSessionId;

  /// 撤销前的轮次（`/redo` 的文件恢复目标）。
  final int fromTurn;

  /// 撤销到的轮次。
  final int toTurn;

  /// 被撤回的最新一条用户 prompt（回填输入框）；无 prompt 时为空串。
  final String prompt;

  @override
  String toString() => 'RevertStage($originalSessionId -> $forkSessionId, '
      '$fromTurn -> $toTurn)';
}

/// 撤销 / 重做无法执行时抛出；[message] 直接上屏。
class RevertException implements Exception {
  const RevertException(this.message);

  /// 人可读原因。
  final String message;

  @override
  String toString() => 'RevertException: $message';
}

/// 一次撤销的结果：撤销点 + 文件恢复计数。
class UndoResult {
  const UndoResult({required this.stage, required this.restore});

  /// 留给 `/redo` 的撤销点。
  final RevertStage stage;

  /// 文件恢复计数（checkpoint 关闭时全 0）。
  final CheckpointRestore restore;
}

/// 一次重做的结果。
class RedoResult {
  const RedoResult({required this.restored});

  /// 是否恢复了工作区文件（checkpoint 关闭时为 false）。
  final bool restored;
}

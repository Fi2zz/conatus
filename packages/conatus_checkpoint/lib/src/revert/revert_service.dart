/// `/undo` `/redo` 的编排：恢复工作区文件、在切点分叉对话、暂存 prompt。
///
/// 与 `/rewind` 的分工：`/undo` 留下 [RevertStage]，`/redo` 能回到撤销前；
/// `/rewind` 是一次性回滚、没有重做。文件恢复复用 [CheckpointManager]，
/// 对话回滚沿用「`Session.fork` + `SessionStore.adopt`」的 append-only 派生。
library;

import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../../conatus_checkpoint.dart';
import 'revert_compensate.dart';
import 'revert_confirm.dart';
import 'revert_prompts.dart';
import 'revert_stage.dart';

/// 撤销 / 重做服务。
class RevertService {
  RevertService({
    required CheckpointManager checkpoint,
    required SessionStore sessions,
    Future<bool> Function(String message)? confirm,
  })  : _checkpoint = checkpoint,
        _sessions = sessions,
        _confirmation =
            RevertConfirmation(checkpoint: checkpoint, ask: confirm);

  final CheckpointManager _checkpoint;
  final SessionStore _sessions;
  final RevertConfirmation _confirmation;

  /// 撤销 [steps] 轮（缺省 1）：恢复文件 + 对话回到目标切点，并暂存 prompt。
  Future<UndoResult> undo(Session current, int steps) async {
    final int count = steps < 1 ? 1 : steps;
    if (!_checkpoint.enabled) return _undoConversationOnly(current, count);
    await _checkpoint.flush();
    final int fromTurn = _checkpoint.turn;
    if (count > fromTurn) {
      throw RevertException('没有可撤销的 $count 轮（当前第 $fromTurn 轮）。');
    }
    final int toTurn = fromTurn - count;
    if (toTurn >= fromTurn) {
      throw RevertException('没有可撤销的轮次（当前第 $fromTurn 轮）。');
    }
    final bool known = _checkpoint.list().any(
          (CheckpointInfo info) => info.turn == toTurn,
        );
    if (!known) {
      throw RevertException('找不到第 $toTurn 轮检查点（可能已被裁剪）。');
    }
    await _confirmation.confirm(current.id, fromTurn, toTurn);
    final CheckpointRewindResult? restored = await _checkpoint.restoreTo(
      current.id,
      toTurn,
    );
    if (restored == null) {
      throw RevertException('恢复第 $toTurn 轮检查点失败，文件未改动。');
    }
    final String forkId = await _forkAfterRestore(
      current,
      restored.lastEventId,
      fromTurn,
    );
    final List<String> prompts = revertPromptsAfter(
      current,
      restored.lastEventId,
    );
    return UndoResult(
      stage: RevertStage(
        originalSessionId: current.id,
        forkSessionId: forkId,
        fromTurn: fromTurn,
        toTurn: toTurn,
        prompt: _latest(prompts),
      ),
      restore: restored.restore,
    );
  }

  /// 重做一次撤销：把文件恢复到撤销前的轮次。
  ///
  /// 会话切回由调用方做（切会话是界面职责）；checkpoint 关闭时无从恢复文件，
  /// 返回 `restored: false` 让调用方只切回原会话。
  Future<RedoResult> redo(RevertStage stage) async {
    if (!_checkpoint.enabled) return const RedoResult(restored: false);
    await _checkpoint.flush();
    final CheckpointRewindResult? restored = await _checkpoint.restoreTo(
      stage.originalSessionId,
      stage.fromTurn,
    );
    if (restored == null) {
      throw RevertException('找不到第 ${stage.fromTurn} 轮检查点，无法重做。');
    }
    return const RedoResult(restored: true);
  }

  /// checkpoint 关闭：只把对话分叉回 [count] 轮之前，文件一律不动。
  ///
  /// 没有用户消息时明确报错——否则会「撤销」出一个空会话，让用户以为真撤了。
  Future<UndoResult> _undoConversationOnly(Session current, int count) async {
    final int prompts = revertPromptCount(current);
    if (prompts == 0) {
      throw const RevertException('没有可撤销的对话（当前会话没有用户消息）。');
    }
    if (count > prompts) {
      throw RevertException('没有可撤销的 $count 轮（当前会话只有 $prompts 条用户消息）。');
    }
    final String? cut = revertCutBefore(current, count);
    final List<String> undone = revertPromptsAfter(current, cut);
    final int fromTurn = _boundTurn(current);
    final int rounds = undone.isEmpty ? 1 : undone.length;
    return UndoResult(
      stage: RevertStage(
        originalSessionId: current.id,
        forkSessionId: _forkAt(current, cut),
        fromTurn: fromTurn,
        toTurn: math.max(0, fromTurn - rounds),
        prompt: _latest(undone),
      ),
      restore: const CheckpointRestore(restored: 0, deleted: 0),
    );
  }

  /// 管理器当前轮次；未绑定 [current] 时按 0。
  int _boundTurn(Session current) =>
      _checkpoint.sessionId == current.id ? _checkpoint.turn : 0;

  /// 恢复文件后 fork 对话；fork 失败先把工作区补偿回 [fromTurn] 再报错。
  Future<String> _forkAfterRestore(
    Session current,
    String? cut,
    int fromTurn,
  ) async {
    try {
      return _forkAt(current, cut);
    } catch (error) {
      final String? failed = await compensateRevertWorkspace(
        _checkpoint,
        current.id,
        fromTurn,
      );
      final String tail =
          failed == null ? '工作区已恢复到第 $fromTurn 轮。' : '工作区补偿失败：$failed。';
      throw RevertException('无法分叉对话（$error）；$tail');
    }
  }

  /// 从 [cut] 处 fork 会话并注册；[cut] 为 `null` 时建全新空会话。
  String _forkAt(Session current, String? cut) {
    if (cut == null) return _sessions.create().id;
    final Session fork = current.fork(
      fromEventId: cut,
      id: 'session_${newUuidV4()}',
    );
    return _sessions.adopt(fork).id;
  }

  static String _latest(List<String> prompts) =>
      prompts.isEmpty ? '' : prompts.last;
}

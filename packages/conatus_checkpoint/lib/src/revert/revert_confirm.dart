/// 撤销前的确认：**始终**询问一次。
///
/// 只按 `changesBetween` 决定是否询问是不够的：最后一次快照之后的外部改动不在
/// 任何清单里，撤销会静默覆盖它们。因此有交互通道时一律确认，差异只用来在文案
/// 里给出改动规模。
library;

import '../../conatus_checkpoint.dart';

import 'revert_stage.dart';

/// 一次撤销的确认器。
class RevertConfirmation {
  const RevertConfirmation({required this.checkpoint, this.ask});

  /// 检查点管理器（只读，用于统计区间改动数）。
  final CheckpointManager checkpoint;

  /// 提问钩子；`null` 表示无交互通道（headless / 纯服务测试），不阻塞。
  final Future<bool> Function(String message)? ask;

  /// 确认是否继续撤销；被拒绝时抛出 [RevertException]。
  Future<void> confirm(String sessionId, int fromTurn, int toTurn) async {
    final Future<bool> Function(String message)? ask = this.ask;
    if (ask == null) return;
    final int changed = await _changedFiles(sessionId, fromTurn, toTurn);
    final String detail = changed > 0 ? '（记录到 $changed 个文件改动）' : '';
    final bool ok = await ask(
      '撤销会把工作区恢复到第 $toTurn 轮$detail。'
      '尚未快照的外部改动也会丢失，继续？',
    );
    if (!ok) throw const RevertException('已取消撤销：工作区保持原样。');
  }

  /// 两轮之间的文件变化数；读不到差异按 0（确认仍然会发）。
  Future<int> _changedFiles(String id, int fromTurn, int toTurn) async {
    try {
      final List<CheckpointFileChange> changes =
          await checkpoint.changesBetween(id, fromTurn, toTurn);
      return changes.length;
    } catch (_) {
      return 0;
    }
  }
}

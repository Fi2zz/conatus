/// 撤销在「文件已恢复、对话还没分叉/切过去」阶段失败后的工作区补偿。
library;

import '../../conatus_checkpoint.dart';

/// 把 [sessionId] 的工作区恢复到 [turn]；成功返回 `null`，失败返回原因。
Future<String?> compensateRevertWorkspace(
  CheckpointManager checkpoint,
  String sessionId,
  int turn,
) async {
  try {
    final CheckpointRewindResult? restored = await checkpoint.restoreTo(
      sessionId,
      turn,
    );
    return restored == null ? '找不到第 $turn 轮检查点' : null;
  } catch (error) {
    return '$error';
  }
}

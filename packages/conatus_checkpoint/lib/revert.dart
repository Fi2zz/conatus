/// conatus 的 undo/redo 入口：`/undo` `/redo` 的编排能力。
///
/// 主入口 [conatus_checkpoint.dart] 只管快照与恢复；undo/redo 依赖会话存储
/// （`SessionStore`），因此作为**第二入口**单独暴露，按需引入：
///
/// ```dart
/// import 'package:conatus_checkpoint/revert.dart';
/// ```
///
/// * 编排 [RevertService]：恢复工作区文件 + 在切点分叉对话 + 暂存 prompt。
/// * 撤销点 [RevertStage] 与结果 [UndoResult] / [RedoResult]。
/// * 确认 [RevertConfirmation]：有交互通道时始终问一次，避免静默覆盖外部改动。
/// * prompt 推算 [revertCutBefore] / [revertPromptsAfter] / [revertPromptCount]。
/// * 补偿 [compensateRevertWorkspace]：分叉失败时把工作区退回撤销前。
library;

export 'src/revert/revert_compensate.dart' show compensateRevertWorkspace;
export 'src/revert/revert_confirm.dart' show RevertConfirmation;
export 'src/revert/revert_prompts.dart'
    show revertCutBefore, revertPromptCount, revertPromptsAfter;
export 'src/revert/revert_service.dart' show RevertService;
export 'src/revert/revert_stage.dart'
    show RedoResult, RevertException, RevertStage, UndoResult;

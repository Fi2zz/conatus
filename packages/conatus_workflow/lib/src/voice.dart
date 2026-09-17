/// Workflow 语音播报 seam：把运行事件转成 TTS 文案。
///
/// conatus_workflow 不直接依赖 conatus_tts，通过 [WorkflowVoice] 抽象
/// 注入。装配方在主程序侧用 TTS 适配 [WorkflowVoice.say]；文案生成是
/// 纯函数，可独立测试。语音审批由装配方把 [AskUserApproval] 的语音版
/// 注入引擎的 approval seam——本包不感知。
library;

import 'definition.dart';
import 'run.dart';
import 'run_node.dart';
import 'status.dart';

/// Workflow 语音播报端口。
abstract class WorkflowVoice {
  /// 播报一句话。
  void say(String text);

  /// 不播报的单例。
  static const WorkflowVoice noop = _NoopVoice();
}

class _NoopVoice implements WorkflowVoice {
  const _NoopVoice();

  @override
  void say(String text) {}
}

/// 流程创建播报：「我创建了「X」流程，共 N 步。要现在试一下吗？」
String workflowCreatedMessage(WorkflowDefinition definition) {
  return '好的，我创建了一个「${definition.name}」流程，共 '
      '${definition.nodes.length} 步。要现在试一下吗？';
}

/// 进度播报：「「X」已经跑到第 N 步（共 M 步）。」
String workflowProgressMessage(WorkflowRun run) {
  final done =
      run.nodes.values.where((RunNode node) => node.status.isTerminal).length;
  final total = run.nodes.length;
  final current = done >= total ? total : done + 1;
  return '「${run.workflowName}」已经跑到第 $current 步（共 $total 步）。';
}

/// 结果播报：「「X」跑完了，结果：……」
String workflowResultMessage(WorkflowRun run) {
  if (run.status != RunStatus.completed) {
    return '「${run.workflowName}」还没跑完。';
  }
  if (run.outputs.isEmpty) {
    return '「${run.workflowName}」跑完了，没有输出。';
  }
  final summary = run.outputs.entries
      .map((MapEntry<String, Object?> entry) => '${entry.key}: ${entry.value}')
      .join('；');
  return '「${run.workflowName}」跑完了，结果：$summary。';
}

/// 失败播报：「「X」跑失败了：……」
String workflowFailedMessage(WorkflowRun run) {
  return '「${run.workflowName}」跑失败了：${run.error}。';
}

/// 流程调整播报：「好的，以后「X」按新流程跑。」
String workflowUpdatedMessage(String name) => '好的，以后「$name」按新流程跑。';

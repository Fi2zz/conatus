/// 后处理：流程完成后执行，可替换的 seam。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'automation.dart';
import 'engine.dart';
import 'run.dart';

/// 后处理上下文。
class PostContext {
  const PostContext({
    required this.automation,
    required this.result,
    required this.workflow,
  });

  /// 本次运行的自动化。
  final Automation automation;

  /// 终态运行（completed / failed）。
  final WorkflowRun result;

  /// 编排引擎（链式触发用）。
  final WorkflowEngine workflow;
}

/// 后处理。
sealed class PostAction {
  const PostAction();

  Future<void> execute(PostContext ctx);
}

/// 通知用户。模板支持 {name} / {status} 占位。
class NotifyAction extends PostAction {
  const NotifyAction({
    required this.askUser,
    this.template = '流程「{name}」已完成',
  });

  final AskUser askUser;
  final String template;

  @override
  Future<void> execute(PostContext ctx) async {
    final message = template
        .replaceAll('{name}', ctx.automation.name)
        .replaceAll('{status}', ctx.result.status.name);
    await askUser.ask(message);
  }
}

/// 记录到 Session。
class RecordAction extends PostAction {
  const RecordAction({required this.session});

  final Session session;

  @override
  Future<void> execute(PostContext ctx) async {
    session.append('automation/completed', data: <String, Object?>{
      'name': ctx.automation.name,
      'runId': ctx.result.id,
      'status': ctx.result.status.name,
    });
  }
}

/// 触发下一个流程。
class ChainAction extends PostAction {
  const ChainAction({required this.workflowName, this.inputs = const {}});

  final String workflowName;
  final Map<String, Object?> inputs;

  @override
  Future<void> execute(PostContext ctx) async {
    await ctx.workflow.start(workflowName, inputs: inputs);
  }
}

/// 复合后处理，按序执行。
class CompositeAction extends PostAction {
  const CompositeAction(this.actions);

  final List<PostAction> actions;

  @override
  Future<void> execute(PostContext ctx) async {
    for (final action in actions) {
      await action.execute(ctx);
    }
  }
}

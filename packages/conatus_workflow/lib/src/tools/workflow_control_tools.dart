/// 面向模型的流程控制工具：pause / resume / cancel / rerun。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../engine.dart';
import '../errors.dart';

/// `workflow_pause`：暂停运行（当前节点完成后生效）。
class WorkflowPauseTool extends Tool {
  WorkflowPauseTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_pause';
  @override
  String get description => '暂停一次运行，当前节点完成后生效。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('run_id', required: true, description: '运行 id'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await engine.pause(ctx.str('run_id'));
    return ToolResult.success('已请求暂停 ${ctx.str('run_id')}');
  }
}

/// `workflow_resume`：恢复暂停的运行。
class WorkflowResumeTool extends Tool {
  WorkflowResumeTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_resume';
  @override
  String get description => '恢复一次暂停的运行。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('run_id', required: true, description: '运行 id'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final run = await engine.resume(ctx.str('run_id'));
      return ToolResult.success(
        '已恢复 ${run.id}（${run.status.name}）',
        value: run.toJson(),
      );
    } on WorkflowException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// `workflow_cancel`：取消运行（medium 风险）。
class WorkflowCancelTool extends Tool {
  WorkflowCancelTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_cancel';
  @override
  String get description => '取消一次运行。';
  @override
  ToolRisk get riskLevel => ToolRisk.medium;
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('run_id', required: true, description: '运行 id'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await engine.cancel(ctx.str('run_id'));
    return ToolResult.success('已请求取消 ${ctx.str('run_id')}');
  }
}

/// `workflow_rerun`：重跑指定节点，级联重置下游（medium 风险）。
class WorkflowRerunTool extends Tool {
  WorkflowRerunTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_rerun';
  @override
  String get description => '重跑指定节点并级联重置其下游节点。';
  @override
  ToolRisk get riskLevel => ToolRisk.medium;
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('run_id', required: true, description: '运行 id'),
        ParamSpec.string('node_id', required: true, description: '节点 id'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final run = await engine.rerun(ctx.str('run_id'), ctx.str('node_id'));
      return ToolResult.success(
        '已重跑节点 ${ctx.str('node_id')}（${run.status.name}）',
        value: run.toJson(),
      );
    } on WorkflowException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

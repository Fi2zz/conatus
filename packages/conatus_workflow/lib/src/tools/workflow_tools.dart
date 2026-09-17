/// 面向模型的流程工具：create / run / status / list + 装配。
///
/// 调用 [provideWorkflowTools] 一次性注册全部 8 个流程工具（含
/// [workflow_control_tools] 的 4 个）。`workflow_run` / `workflow_cancel` /
/// `workflow_rerun` 是 medium 风险，运行时由 [WorkflowHooks] 的 approval
/// seam 拦截（引擎节点执行前检查）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../definition.dart';
import '../engine.dart';
import '../errors.dart';
import '../provider.dart' show WorkflowContext;
import '../run.dart';
import '../run_node.dart';
import 'workflow_control_tools.dart';

/// `workflow_create`：创建/注册一个流程定义。
class WorkflowCreateTool extends Tool {
  WorkflowCreateTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_create';
  @override
  String get description => '创建/注册一个流程定义（JSON 对象）。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.object(
          'definition',
          properties: const <String, ParamSpec>{},
          required: true,
          description: '流程定义 JSON',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final raw = ctx.require<Map<String, Object?>>('definition');
    try {
      final definition = WorkflowDefinition.fromJson(raw);
      await engine.register(definition);
      return ToolResult.success(
        '已注册流程「${definition.name}」v${definition.version}',
      );
    } on WorkflowException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// `workflow_run`：启动一次执行（medium 风险）。
class WorkflowRunTool extends Tool {
  WorkflowRunTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_run';
  @override
  String get description => '启动一次流程执行，返回 run_id。';
  @override
  ToolRisk get riskLevel => ToolRisk.medium;
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('name', required: true, description: '流程名'),
        ParamSpec.object(
          'inputs',
          properties: const <String, ParamSpec>{},
          description: '运行输入',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final run = await engine.start(
        ctx.str('name'),
        inputs: ctx.object('inputs') ?? const <String, Object?>{},
      );
      return ToolResult.success(
        '已启动流程「${run.workflowName}」，runId=${run.id}',
        value: run.id,
      );
    } on WorkflowException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// `workflow_status`：查询运行状态与进度。
class WorkflowStatusTool extends Tool {
  WorkflowStatusTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_status';
  @override
  String get description => '查询一次运行的状态与节点进度。';
  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('run_id', required: true, description: '运行 id'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final run = engine.run(ctx.str('run_id'));
    if (run == null) {
      return ToolResult.failure(
        '未知运行: ${ctx.str('run_id')}',
        error: const ToolError('UNKNOWN_RUN', 'unknown run'),
      );
    }
    final done =
        run.nodes.values.where((RunNode node) => node.status.isTerminal).length;
    return ToolResult.success(
      '${run.workflowName} 状态: ${run.status.name}（$done/${run.nodes.length}）',
      value: run.toJson(),
    );
  }
}

/// `workflow_list`：列出已注册流程与运行。
class WorkflowListTool extends Tool {
  WorkflowListTool(this.engine);

  final WorkflowEngine engine;

  @override
  String get name => 'workflow_list';
  @override
  String get description => '列出已注册的流程与运行。';

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final defs =
        engine.definitions.map((WorkflowDefinition d) => d.name).join('、');
    final runs = engine.runs
        .map((WorkflowRun r) => '${r.id}:${r.status.name}')
        .join('、');
    return ToolResult.success(
      '流程: ${defs.isEmpty ? '无' : defs}\n运行: ${runs.isEmpty ? '无' : runs}',
    );
  }
}

/// 把 8 个流程工具注册到 [ctx] 的 `tools` 服务。
///
/// - [workflow]：缺省取 `ctx.workflow`（需先 [provideWorkflow]）。
/// - [tools]：缺省取 `ctx.tools`。
void provideWorkflowTools(
  Context ctx, {
  WorkflowEngine? workflow,
  ToolRegistry? tools,
}) {
  final WorkflowEngine engine = workflow ?? ctx.workflow;
  final ToolRegistry registry = tools ?? ctx.tools;
  for (final Tool tool in <Tool>[
    WorkflowCreateTool(engine),
    WorkflowRunTool(engine),
    WorkflowStatusTool(engine),
    WorkflowListTool(engine),
    WorkflowPauseTool(engine),
    WorkflowResumeTool(engine),
    WorkflowCancelTool(engine),
    WorkflowRerunTool(engine),
  ]) {
    ctx.effect(() => registry.register(tool));
  }
}

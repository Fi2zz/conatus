/// run_code 工具：`codeRuntime` 服务的面向模型封装，治理集成挂在工具上。
///
/// 审批靠 [ToolRisk.high] 自动挂载（`instrumentApproval` 拦截），工具内不
/// 手动调 approval；taskCenter / sessionLog / telemetry 缺省时降级，不阻塞
/// 执行。失败是结果字段：代码执行的失败转为 `ToolResult.error`，不抛异常
/// （异常只在治理本身失败时上抛，由注册表收敛）。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';

import '../binding/tool_binding.dart';
import '../runtime/code_run_request.dart';
import '../runtime/code_run_result.dart';
import '../runtime/code_runtime.dart';

/// 执行一段程序。程序内可调用 `tools.*` 命名空间下的工具。
class RunCodeTool extends Tool {
  const RunCodeTool({
    required CodeRuntime runtime,
    required ToolRegistry tools,
    this.taskCenter,
    this.sessionLog,
    this.telemetry,
    this.maxProgramBytes = 100000,
  })  : _runtime = runtime,
        _tools = tools;

  final CodeRuntime _runtime;
  final ToolRegistry _tools;

  /// 任务中心。可选，缺省不追踪。
  final TaskCenter? taskCenter;

  /// 会话日志记录器。可选，缺省不记录。
  final SessionLogRecorder? sessionLog;

  /// 遥测。可选，缺省不埋点。
  final Telemetry? telemetry;

  /// 程序大小上限（字符数）。
  final int maxProgramBytes;

  @override
  String get name => 'run_code';

  @override
  String get description => '执行一段程序。程序内可调用 tools.* 命名空间下的工具。'
      '失败是结果字段，不是异常。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('program', required: true, description: '程序源码'),
        ParamSpec.boolean(
          'expose_tools',
          description: '是否暴露工具绑定，默认 true',
        ),
      ];

  @override
  ToolRisk get riskLevel => ToolRisk.high;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String program = ctx.str('program');
    if (program.length > maxProgramBytes) {
      return ToolResult.failure(
        '程序超过 $maxProgramBytes 字符',
        error: ToolError('PROGRAM_TOO_LARGE', '程序超过 $maxProgramBytes 字符'),
      );
    }
    return _execute(ctx, program);
  }

  Future<ToolResult> _execute(ToolContext ctx, String program) async {
    final TaskCenter? center = taskCenter;
    final String? taskId = await _createTask(program);
    final Stopwatch stopwatch = Stopwatch()..start();
    telemetry?.emit(TelemetryEvent('code.run.started', data: <String, Object?>{
      'language': _runtime.language,
      'isolation': _runtime.isolation,
    }));
    unawaited(sessionLog?.record('code/run', data: <String, Object?>{
      'language': _runtime.language,
      'program': program,
    }));
    try {
      if (center != null) {
        await center.update(taskId!, status: TaskStatus.running);
      }
      final bool exposeTools = ctx.optional<bool>('expose_tools') ?? true;
      final List<CodeBindingNamespace> bindings = exposeTools
          ? toolsAsBindings(_tools)
          : const <CodeBindingNamespace>[];
      final CodeRunResult result = await _runtime.run(CodeRunRequest(
        program: program,
        bindings: bindings,
      ));
      return _finish(result, taskId, stopwatch);
    } catch (error) {
      await _fail(error, taskId);
      rethrow;
    }
  }

  Future<String?> _createTask(String program) async {
    final String? sessionId = sessionLog?.sessionId;
    final Task? task = await taskCenter?.create(
      kind: TaskKind.custom,
      description: '执行代码 (${_runtime.language})',
      metadata: <String, Object?>{
        'language': _runtime.language,
        'isolation': _runtime.isolation,
        'programBytes': program.length,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
    return task?.id;
  }

  Future<ToolResult> _finish(
    CodeRunResult result,
    String? taskId,
    Stopwatch stopwatch,
  ) async {
    final TaskCenter? center = taskCenter;
    if (center != null) {
      await center.update(
        taskId!,
        status: result.isSuccess ? TaskStatus.completed : TaskStatus.failed,
        result: result.value,
        error: result.error,
      );
    }
    telemetry?.emit(TelemetryEvent('code.run.finished', data: <String, Object?>{
      'language': _runtime.language,
      'durationMs': stopwatch.elapsedMilliseconds,
      'success': result.isSuccess,
      'failureKind': result.error?.kind.name,
    }));
    unawaited(sessionLog?.record('code/result', data: <String, Object?>{
      'success': result.isSuccess,
      'error': result.error?.message,
      'logs': result.logs,
    }));
    if (!result.isSuccess) {
      final String message = result.error!.message;
      return ToolResult.failure(
        message,
        error: ToolError(
          'CODE_${result.error!.kind.name.toUpperCase()}',
          message,
        ),
      );
    }
    return ToolResult.success(
      result.value?.toString() ?? '',
      value: <String, Object?>{
        'value': result.value,
        'logs': result.logs,
      },
    );
  }

  Future<void> _fail(Object error, String? taskId) async {
    final TaskCenter? center = taskCenter;
    if (center != null) {
      await center.update(taskId!, status: TaskStatus.failed, error: error);
    }
    telemetry?.emit(TelemetryEvent('code.run.failed', data: <String, Object?>{
      'error': '$error',
    }));
  }
}

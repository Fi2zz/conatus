import 'dart:async';
import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

ToolContext _ctx(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'run_code', arguments: args));

RunCodeTool _tool(
  _FakeRuntime runtime, {
  ToolRegistry? tools,
  TaskCenter? taskCenter,
  SessionLogRecorder? sessionLog,
  Telemetry? telemetry,
  int maxProgramBytes = 100000,
}) =>
    RunCodeTool(
      runtime: runtime,
      tools: tools ?? ToolRegistry(),
      taskCenter: taskCenter,
      sessionLog: sessionLog,
      telemetry: telemetry,
      maxProgramBytes: maxProgramBytes,
    );

void main() {
  group('RunCodeTool', () {
    test('成功 → content 为 value 文本，value 携带 value 与 logs', () async {
      final _FakeRuntime runtime = _FakeRuntime(
          CodeRunResult.success('hi', logs: const <String>['warn']));

      final ToolResult result = await _tool(runtime)
          .call(_ctx(<String, Object?>{'program': 'print(1)'}));

      expect(result.isError, isFalse);
      expect(result.content, 'hi');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['value'], 'hi');
      expect(value['logs'], <String>['warn']);
      expect(runtime.calls, 1);
      expect(runtime.lastProgram, 'print(1)');
    });

    test('失败 → CODE_<KIND> 错误码，不抛异常', () async {
      final _FakeRuntime runtime = _FakeRuntime(
          CodeRunResult.failure(CodeRunFailureKind.exception, 'boom'));

      final ToolResult result =
          await _tool(runtime).call(_ctx(<String, Object?>{'program': 'x'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'CODE_EXCEPTION');
      expect(result.content, 'boom');
    });

    test('超上限 → PROGRAM_TOO_LARGE，runtime 不被调用', () async {
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success(''));

      final ToolResult result = await _tool(runtime, maxProgramBytes: 3)
          .call(_ctx(<String, Object?>{'program': 'abcd'}));

      expect(result.error!.code, 'PROGRAM_TOO_LARGE');
      expect(runtime.calls, 0);
    });

    test('expose_tools 默认 true → bindings 含 tools 命名空间', () async {
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success(''));
      final ToolRegistry tools = ToolRegistry();
      tools.register(const _EchoTool());

      await _tool(runtime, tools: tools)
          .call(_ctx(<String, Object?>{'program': 'x'}));

      expect(runtime.lastBindings, hasLength(1));
      expect(runtime.lastBindings!.single.global, 'tools');
      expect(runtime.lastBindings!.single.functions.keys, contains('echo'));
    });

    test('expose_tools=false → bindings 为空', () async {
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success(''));
      final ToolRegistry tools = ToolRegistry();
      tools.register(const _EchoTool());

      await _tool(runtime, tools: tools)
          .call(_ctx(<String, Object?>{'program': 'x', 'expose_tools': false}));

      expect(runtime.lastBindings, isEmpty);
    });

    test('taskCenter：成功 → pending → running → completed，带元数据', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'));

      await _tool(runtime, taskCenter: tasks)
          .call(_ctx(<String, Object?>{'program': 'print(1)'}));

      final Task task = tasks.all.single;
      expect(task.status, TaskStatus.completed);
      expect(task.kind, TaskKind.custom);
      expect(task.description, contains('执行代码'));
      expect(task.metadata['language'], 'dart');
      expect(task.metadata['isolation'], 'process');
      expect(task.metadata['programBytes'], 8);
      expect(task.startedAt, isNotNull);
      expect(task.finishedAt, isNotNull);
    });

    test('taskCenter：失败 → Task 标记 failed 并携带错误', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final _FakeRuntime runtime =
          _FakeRuntime(CodeRunResult.failure(CodeRunFailureKind.timeout, '超时'));

      await _tool(runtime, taskCenter: tasks)
          .call(_ctx(<String, Object?>{'program': 'x'}));

      final Task task = tasks.all.single;
      expect(task.status, TaskStatus.failed);
      expect(task.error, isA<CodeRunFailure>());
    });

    test('telemetry：started → finished 事件序列', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'));

      await _tool(runtime, telemetry: telemetry)
          .call(_ctx(<String, Object?>{'program': 'x'}));

      final List<TelemetryEvent> events = telemetry.recent;
      expect(events.map((TelemetryEvent e) => e.name),
          <String>['code.run.started', 'code.run.finished']);
      expect(events[0].data['language'], 'dart');
      expect(events[1].data['success'], isTrue);
      expect(events[1].data['failureKind'], isNull);
      expect(events[1].data['durationMs'], isA<int>());
    });

    test('telemetry：失败 → finished 带 success=false 与 failureKind', () async {
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final _FakeRuntime runtime = _FakeRuntime(
          CodeRunResult.failure(CodeRunFailureKind.outputLimit, '太大'));

      await _tool(runtime, telemetry: telemetry)
          .call(_ctx(<String, Object?>{'program': 'x'}));

      final Map<String, Object?> finished = telemetry.recent[1].data;
      expect(finished['success'], isFalse);
      expect(finished['failureKind'], 'outputLimit');
    });

    test('sessionLog：记录 code/run 与 code/result，含完整程序', () async {
      final InMemorySessionLog log = InMemorySessionLog();
      final SessionLogRecorder recorder = SessionLogRecorder(log: log);
      recorder.attach(Session(id: 's1'));
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'));

      await _tool(runtime, sessionLog: recorder)
          .call(_ctx(<String, Object?>{'program': 'print(1)'}));

      final List<SessionEvent> events = await log.read('s1').toList();
      final SessionEvent run =
          events.singleWhere((SessionEvent e) => e.type == 'code/run');
      final SessionEvent result =
          events.singleWhere((SessionEvent e) => e.type == 'code/result');
      expect((run.data! as Map<String, Object?>)['program'], 'print(1)');
      expect((result.data! as Map<String, Object?>)['success'], isTrue);
    });

    test('sessionLog：未 attach 时静默不报错', () async {
      final SessionLogRecorder recorder =
          SessionLogRecorder(log: InMemorySessionLog());
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'));

      final ToolResult result = await _tool(runtime, sessionLog: recorder)
          .call(_ctx(<String, Object?>{'program': 'x'}));

      expect(result.isError, isFalse);
    });

    test('runtime 抛异常 → 上抛，Task 标记 failed，emit code.run.failed', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final InMemoryTelemetry telemetry = InMemoryTelemetry();
      final _FakeRuntime runtime = _FakeRuntime();
      runtime.throwError = StateError('oops');

      await expectLater(
        _tool(runtime, taskCenter: tasks, telemetry: telemetry)
            .call(_ctx(<String, Object?>{'program': 'x'})),
        throwsA(isA<StateError>()),
      );

      expect(tasks.all.single.status, TaskStatus.failed);
      expect(telemetry.recent.map((TelemetryEvent e) => e.name),
          contains('code.run.failed'));
    });

    test('执行期间任务被取消 → 状态 cancelled、结果正常返回、cancel 回调被调', () async {
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'))
        ..gate = Completer<void>();
      final RunCodeTool tool = _tool(runtime, taskCenter: tasks);

      final Future<ToolResult> pending =
          tool.call(_ctx(<String, Object?>{'program': 'x'}));
      while (tasks.all.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final String id = tasks.all.single.id;
      await tasks.cancel(id);
      runtime.gate!.complete();

      final ToolResult result = await pending;

      expect(tasks.all.single.status, TaskStatus.cancelled);
      expect(runtime.cancelCount, 1);
      expect(result.isError, isFalse, reason: '取消后不抛 already-terminal');
    });

    test('端到端：真实子进程可被 cancel 终止', () async {
      if (Platform.isWindows) {
        markTestSkipped('端到端取消测试依赖 bash');
      }
      final LocalShellExecutor shell = LocalShellExecutor();
      final DefaultTaskCenter tasks = DefaultTaskCenter();
      final SubprocessCodeRuntime runtime = SubprocessCodeRuntime(
        shell: shell,
        executable: 'bash',
        extension: '.sh',
      );
      final RunCodeTool tool = RunCodeTool(
        runtime: runtime,
        tools: ToolRegistry(),
        taskCenter: tasks,
      );

      final Future<ToolResult> pending =
          tool.call(_ctx(<String, Object?>{'program': 'sleep 30'}));
      while (tasks.all.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final String id = tasks.all.single.id;
      await tasks.cancel(id);

      final ToolResult result = await pending;

      expect(tasks.all.single.status, TaskStatus.cancelled);
      expect(result.isError, isTrue);
      expect(result.error!.code, 'CODE_ABORT');
    });

    test('降级：无治理组件仍能执行', () async {
      final _FakeRuntime runtime = _FakeRuntime(CodeRunResult.success('ok'));

      final ToolResult result =
          await _tool(runtime).call(_ctx(<String, Object?>{'program': 'x'}));

      expect(result.isError, isFalse);
    });
  });
}

class _FakeRuntime implements CodeRuntime {
  _FakeRuntime([this.result]);

  CodeRunResult? result;
  Object? throwError;
  Completer<void>? gate;
  int calls = 0;
  int cancelCount = 0;
  String? lastProgram;
  List<CodeBindingNamespace>? lastBindings;

  @override
  String get language => 'dart';

  @override
  String get isolation => 'process';

  @override
  Future<CodeRunResult> run(CodeRunRequest request) async {
    calls++;
    lastProgram = request.program;
    lastBindings = request.bindings;
    await gate?.future;
    final Object? error = throwError;
    if (error != null) throw error;
    return result!;
  }

  @override
  Future<void> cancelCurrent() async {
    cancelCount++;
  }

  @override
  void dispose() {}
}

class _EchoTool extends Tool {
  const _EchoTool();

  @override
  String get name => 'echo';

  @override
  String get description => '回显文本';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('text', required: true),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async =>
      ToolResult.success(ctx.str('text'));
}

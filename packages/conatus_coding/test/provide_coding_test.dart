import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_coding/conatus_coding.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:conatus_tasks/conatus_tasks.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

Context _ctx(LocalFileSystem fs) {
  final Context ctx = Context.root();
  provideFileSystemLocal(ctx, fs: fs);
  provideTools(ctx);
  return ctx;
}

void main() {
  late Directory dir;
  late LocalFileSystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-coding-');
    fs = LocalFileSystem(cwd: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('provideCoding', () {
    test('无 shell → 注册 4 个工具（无 rg），随上下文释放撤销', () {
      final Context ctx = _ctx(fs);
      final ToolRegistry tools = ctx.tools;

      final List<Tool> registered = provideCoding(ctx, fs: fs);

      expect(
        registered.map((Tool t) => t.name),
        containsAll(<String>['read_file', 'write_file', 'edit_file', 'glob']),
      );
      expect(registered.map((Tool t) => t.name), isNot(contains('rg')));
      expect(
        tools.names,
        containsAll(<String>['read_file', 'write_file', 'edit_file', 'glob']),
      );
      ctx.dispose();
      expect(tools.names, isEmpty);
    });

    test('注入 shell + ripgrep → 注册 rg', () {
      final Context ctx = _ctx(fs);
      final ToolRegistry tools = ctx.tools;

      final List<Tool> registered = provideCoding(
        ctx,
        fs: fs,
        shell: FakeShellExecutor(),
        ripgrep: const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
      );

      expect(registered.map((Tool t) => t.name), contains('rg'));
      expect(tools.names, contains('rg'));
    });

    test('enableSearch=false → 不注册 glob 与 rg', () {
      final Context ctx = _ctx(fs);

      final List<Tool> registered =
          provideCoding(ctx, fs: fs, enableSearch: false);

      expect(registered.map((Tool t) => t.name), isNot(contains('glob')));
      expect(registered.map((Tool t) => t.name), isNot(contains('rg')));
    });

    test('enableRuntime=false → 不提供 codeRuntime 服务', () {
      final Context ctx = _ctx(fs);

      provideCoding(ctx, fs: fs);

      expect(ctx.get<CodeRuntime>('codeRuntime'), isNull);
    });

    test('enableRuntime=true → 提供服务，随上下文释放调用 dispose', () {
      final Context ctx = _ctx(fs);
      final _CountingRuntime runtime = _CountingRuntime();

      provideCoding(ctx, fs: fs, enableRuntime: true, codeRuntime: runtime);

      expect(ctx.require<CodeRuntime>('codeRuntime'), same(runtime));
      ctx.dispose();
      expect(runtime.disposeCount, 1);
    });

    test('返回的工具列表与 ctx.tools.names 一致', () {
      final Context ctx = _ctx(fs);

      final List<Tool> registered = provideCoding(ctx, fs: fs);

      expect(registered.map((Tool t) => t.name).toList(), ctx.tools.names);
    });
    test('enableRuntime=true → 注册 run_code 工具', () {
      final Context ctx = _ctx(fs);

      final List<Tool> registered = provideCoding(
        ctx,
        fs: fs,
        enableRuntime: true,
        codeRuntime: _CountingRuntime(),
      );

      expect(registered.map((Tool t) => t.name), contains('run_code'));
      expect(ctx.tools.names, contains('run_code'));
    });

    test('enableRuntime=false → 不注册 run_code', () {
      final Context ctx = _ctx(fs);

      final List<Tool> registered = provideCoding(ctx, fs: fs);

      expect(registered.map((Tool t) => t.name), isNot(contains('run_code')));
      expect(ctx.tools.names, isNot(contains('run_code')));
    });

    test('approval：AutoApproval(false) 拦截 run_code（high 风险）', () async {
      final Context ctx = _ctx(fs);
      provideApproval(ctx, approval: AutoApproval(false));
      final _CountingRuntime runtime = _CountingRuntime();

      provideCoding(
        ctx,
        fs: fs,
        shell: FakeShellExecutor(),
        enableRuntime: true,
        codeRuntime: runtime,
      );

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'run_code',
        arguments: <String, Object?>{'program': 'x'},
      ));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'APPROVAL_DENIED');
      expect(runtime.runCount, 0);
    });

    test('approval：AutoApproval(true) 放行并执行', () async {
      final Context ctx = _ctx(fs);
      provideApproval(ctx, approval: AutoApproval(true));
      final _CountingRuntime runtime = _CountingRuntime();

      provideCoding(
        ctx,
        fs: fs,
        shell: FakeShellExecutor(),
        enableRuntime: true,
        codeRuntime: runtime,
      );

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'run_code',
        arguments: <String, Object?>{'program': 'x'},
      ));

      expect(result.isError, isFalse);
      expect(runtime.runCount, 1);
    });

    test('治理自动接入：提供 tasks 服务后 run_code 自动追踪', () async {
      final Context ctx = _ctx(fs);
      final TaskCenter tasks = provideTaskCenter(ctx);
      final _CountingRuntime runtime = _CountingRuntime();

      provideCoding(
        ctx,
        fs: fs,
        shell: FakeShellExecutor(),
        enableRuntime: true,
        codeRuntime: runtime,
      );

      await ctx.tools.call(const ToolCall(
        name: 'run_code',
        arguments: <String, Object?>{'program': 'x'},
      ));

      expect(tasks.all, hasLength(1));
      expect(tasks.all.single.status, TaskStatus.completed);
    });
  });
}

class _CountingRuntime implements CodeRuntime {
  int disposeCount = 0;
  int runCount = 0;

  @override
  String get language => 'dart';

  @override
  String get isolation => 'process';

  @override
  void dispose() {
    disposeCount++;
  }

  @override
  Future<CodeRunResult> run(CodeRunRequest request) async {
    runCount++;
    return CodeRunResult.success(null);
  }
}

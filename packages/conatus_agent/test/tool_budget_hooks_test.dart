import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Future<ToolResult> _ok(ToolContext ctx) async => ToolResult.success('BASE');

void _install(
  Context ctx, {
  ToolBudgetPolicy policy = const ToolBudgetPolicy(economyAfter: 1),
  Telemetry? telemetry,
}) {
  provideTools(ctx);
  ctx.tools.fn('noop', handler: _ok);
  ctx.tools.fn('read_file', handler: _ok);
  provideToolBudget(ctx, policy: policy, telemetry: telemetry);
}

void main() {
  test('提醒追加在结果尾部，原始内容前缀不变', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    _install(ctx);

    final ToolResult result =
        await ctx.tools.call(const ToolCall(name: 'noop'));

    expect(result.content, startsWith('BASE'));
    expect(result.content, contains('经济阶段'));
    expect(result.value, isNull);
    expect(result.meta['toolStage'], 'economy');
  });

  test('收口阶段拒绝非白名单，白名单仍放行', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    _install(
      ctx,
      policy: const ToolBudgetPolicy(
        strictAfter: 0,
        finalizeAfter: 1,
      ),
    );

    await ctx.tools.call(const ToolCall(name: 'noop'));
    final ToolResult denied =
        await ctx.tools.call(const ToolCall(name: 'noop'));
    final ToolResult allowed =
        await ctx.tools.call(const ToolCall(name: 'read_file'));

    expect(denied.isError, isTrue);
    expect(denied.error?.code, 'TOOL_BUDGET_EXHAUSTED');
    expect(denied.content, contains('预算'));
    expect(allowed.isError, isFalse);
  });

  test('失败结果保留错误，同时追加提醒', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.tools.fn(
      'broken',
      handler: (ToolContext c) async =>
          ToolResult.failure('坏了', error: const ToolError('BROKEN', 'x')),
    );
    provideToolBudget(ctx, policy: const ToolBudgetPolicy(economyAfter: 1));

    final ToolResult result =
        await ctx.tools.call(const ToolCall(name: 'broken'));

    expect(result.isError, isTrue);
    expect(result.error?.code, 'BROKEN');
    expect(result.content, startsWith('坏了'));
    expect(result.content, contains('经济阶段'));
  });

  test('两个 Context 的计数互不影响', () async {
    final Context left = Context.root();
    final Context right = Context.root();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    _install(left, policy: const ToolBudgetPolicy(finalizeAfter: 0));
    _install(right, policy: const ToolBudgetPolicy(finalizeAfter: 0));

    await left.tools.call(const ToolCall(name: 'noop'));
    await left.tools.call(const ToolCall(name: 'noop'));
    await right.tools.call(const ToolCall(name: 'noop'));

    expect(left.get<ToolBudget>('toolBudget')!.calls, 2);
    expect(right.get<ToolBudget>('toolBudget')!.calls, 1);
  });

  test('被拒的调用也计数，reset 后从头开始', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    _install(
      ctx,
      policy: const ToolBudgetPolicy(
        strictAfter: 0,
        finalizeAfter: 1,
      ),
    );
    final ToolBudget budget = ctx.get<ToolBudget>('toolBudget')!;

    await ctx.tools.call(const ToolCall(name: 'noop'));
    await ctx.tools.call(const ToolCall(name: 'noop'));
    expect(budget.calls, 2);

    budget.reset();
    expect(budget.calls, 0);
    final ToolResult afterReset =
        await ctx.tools.call(const ToolCall(name: 'noop'));
    expect(afterReset.isError, isFalse);
  });

  test('每次调用发 tool.budget 事件', () async {
    final InMemoryTelemetry sink = InMemoryTelemetry();
    addTearDown(sink.close);
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    _install(ctx, telemetry: sink);

    await ctx.tools.call(const ToolCall(name: 'noop'));

    final TelemetryEvent event =
        sink.recent.firstWhere((TelemetryEvent e) => e.name == 'tool.budget');
    expect(event.data['tool'], 'noop');
    expect(event.data['count'], 1);
    expect(event.data['stage'], 'economy');
    expect(event.data['denied'], isFalse);
  });

  test('未安装中间件时行为与从前一致', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.tools.fn('noop', handler: _ok);

    final ToolResult result =
        await ctx.tools.call(const ToolCall(name: 'noop'));

    expect(result.content, 'BASE');
    expect(ctx.get<ToolBudget>('toolBudget'), isNull);
  });
}

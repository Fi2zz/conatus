import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_harness/conatus_harness.dart';
import 'package:test/test.dart';

const ExecutionProfile _profile = ExecutionProfile(
  name: 'standard',
  reasoningEffort: 'medium',
  budget: ToolBudgetPolicy(economyAfter: 1, finalizeAfter: 0),
);

HarnessManifest _manifest({
  Set<String>? allowed,
  Set<String> forbidden = const <String>{},
  List<PromptSectionSpec> sections = const <PromptSectionSpec>[
    PromptSectionSpec(name: 'harness-guide', text: '先读后写。'),
  ],
}) =>
    HarnessManifest(
      name: 'test-harness',
      profile: _profile,
      sections: sections,
      allowedTools: allowed,
      forbiddenTools: forbidden,
    );

Context _context() {
  final Context ctx = Context.root();
  provideTools(ctx);
  provideSystemPrompt(ctx);
  ctx.tools.fn(
    'shell',
    handler: (ToolContext c) async => ToolResult.success('shell-ok'),
  );
  ctx.tools.fn(
    'read_file',
    handler: (ToolContext c) async => ToolResult.success('read-ok'),
  );
  ctx.tools.fn(
    'rm',
    handler: (ToolContext c) async => ToolResult.success('rm-ok'),
  );
  return ctx;
}

void main() {
  test('装配：prompt 段、harness 服务、预算中间件都生效', () async {
    final Context ctx = _context();
    addTearDown(ctx.dispose);

    applyHarness(ctx, _manifest());

    final SystemPrompt prompt = ctx.require<SystemPrompt>('systemPrompt');
    expect(prompt.sections.map((PromptSection s) => s.name),
        contains('harness-guide'));
    expect(ctx.get<HarnessManifest>('harness')?.name, 'test-harness');
    expect(ctx.get<ToolBudget>('toolBudget'), isNotNull);
    expect(
      (await ctx.tools.call(const ToolCall(name: 'shell'))).content,
      contains('经济阶段'),
    );
  });

  test('撤销后段、服务、守卫、预算全部回滚', () async {
    final Context ctx = _context();
    addTearDown(ctx.dispose);
    final Disposer undo = applyHarness(ctx, _manifest());

    undo();

    final SystemPrompt prompt = ctx.require<SystemPrompt>('systemPrompt');
    expect(prompt.sections.map((PromptSection s) => s.name),
        isNot(contains('harness-guide')));
    expect(ctx.get<HarnessManifest>('harness'), isNull);
    expect(ctx.get<ToolBudget>('toolBudget'), isNull);
    expect((await ctx.tools.call(const ToolCall(name: 'shell'))).content,
        'shell-ok');
  });

  test('白名单拒绝名单外工具，放行名单内工具', () async {
    final Context ctx = _context();
    addTearDown(ctx.dispose);
    applyHarness(ctx, _manifest(allowed: <String>{'read_file'}));

    final ToolResult denied =
        await ctx.tools.call(const ToolCall(name: 'shell'));
    final ToolResult allowed =
        await ctx.tools.call(const ToolCall(name: 'read_file'));

    expect(denied.isError, isTrue);
    expect(denied.error?.code, 'TOOL_NOT_IN_HARNESS');
    expect(allowed.isError, isFalse);
  });

  test('禁止名单优先于白名单', () async {
    final Context ctx = _context();
    addTearDown(ctx.dispose);
    applyHarness(
      ctx,
      _manifest(
        allowed: <String>{'rm', 'read_file'},
        forbidden: <String>{'rm'},
      ),
    );

    final ToolResult denied = await ctx.tools.call(const ToolCall(name: 'rm'));

    expect(denied.isError, isTrue);
    expect(denied.error?.code, 'TOOL_FORBIDDEN_BY_HARNESS');
  });

  test('已有预算时不重复安装，保留原计数器', () async {
    final Context ctx = _context();
    addTearDown(ctx.dispose);
    final ToolBudget existing = provideToolBudget(ctx);

    applyHarness(ctx, _manifest());

    expect(ctx.get<ToolBudget>('toolBudget'), same(existing));
  });

  test('重复装配抛 StateError', () {
    final Context ctx = _context();
    addTearDown(ctx.dispose);
    applyHarness(ctx, _manifest());

    expect(() => applyHarness(ctx, _manifest()), throwsStateError);
  });

  test('没有 tools 时拒绝装配', () {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideSystemPrompt(ctx);

    expect(() => applyHarness(ctx, _manifest()), throwsStateError);
  });

  test('没有 prompt 且 manifest 无段时仍可装配工具策略', () async {
    final Context ctx = Context.root();
    addTearDown(ctx.dispose);
    provideTools(ctx);
    ctx.tools.fn('shell',
        handler: (ToolContext c) async => ToolResult.success('ok'));

    applyHarness(
      ctx,
      const HarnessManifest(
        name: 'tools-only',
        profile: _profile,
        allowedTools: <String>{'shell'},
      ),
    );

    expect(
        (await ctx.tools.call(const ToolCall(name: 'shell'))).isError, isFalse);
  });
}

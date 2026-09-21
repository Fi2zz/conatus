// 离线 Demo：无需任何 API Key。
//
// 用脚本化模型跑通「提问 → 工具调用 → 回填 → 收口」，并顺带演示
// telemetry 埋点、技能沉淀与快照恢复。
//
// 运行：
//   dart run example/demo.dart

import 'package:conatus/conatus.dart';

/// 脚本化模型：首轮请求 get_time，次轮读到工具结果后收口。
class _DemoModel implements LlmProvider {
  int calls = 0;

  @override
  String get name => 'demo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    if (calls == 1) {
      return const LlmResult(
        content: '',
        provider: 'demo',
        model: 'demo-1',
        toolCalls: <LlmToolCall>[
          LlmToolCall(id: 'call_1', name: 'get_time'),
        ],
      );
    }
    final List<LlmMessage> toolMessages =
        messages.where((LlmMessage m) => m.role == 'tool').toList();
    if (toolMessages.isEmpty) {
      return const LlmResult(
        content: '未能获取到工具返回结果，无法回答当前问题。',
        provider: 'demo',
        model: 'demo-1',
      );
    }
    final LlmMessage tool = toolMessages.last;
    return LlmResult(
      content: '现在是 ${tool.content}。',
      provider: 'demo',
      model: 'demo-1',
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<void> main() async {
  final Context app = Context.root(name: 'demo');

  // ── 工具 + 可观测性 ──────────────────────────────────────────
  provideTools(app);
  app.effect(() => app.tools.fn(
        'get_time',
        description: '返回当前本地时间（RFC 3339，带时区偏移）',
        handler: (ToolContext ctx) async {
          final DateTime now = DateTime.now();
          return ToolResult.success('${now.toIso8601String()}'
              '${formatClockOffset(now.timeZoneOffset)}');
        },
      ));
  app.effect(() => app.tools.fn(
        'echo',
        description: '回显文本',
        params: <ParamSpec>[ParamSpec.string('text', required: true)],
        handler: (ToolContext ctx) async => ToolResult.success(ctx.str('text')),
      ));
  final InMemoryTelemetry telemetry = InMemoryTelemetry();
  provideTelemetry(app, telemetry: telemetry);
  instrumentTools(app);

  // ── 模型 + 会话 + 上下文 + 记忆 + 循环 ───────────────────────
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_DemoModel()]));
  final Session session = provideSessions(app).create(id: 'demo');
  provideSystemPrompt(app).section(
    PromptSection(name: 'persona', text: () => '你是"助手"，需要实时信息时调用工具。'),
  );
  provideTimePrompt(app); // 日期锚点：模型不必调工具就知道今天
  provideMemory(app);
  provideCompaction(app);
  final AgentLoop agent = provideAgentLoop(app, session: session);

  // ── 1. Agent 闭环 ───────────────────────────────────────────
  print('=== 1. Agent Loop ===');
  final AgentTurn turn = await agent.run('现在几点？');
  for (final AgentStep step in turn.steps) {
    print('· 工具 ${step.result.isError ? '✗' : '✓'} ${step.call.name}'
        ' → ${step.result.content}');
  }
  print('AI > ${turn.reply}');

  // ── 2. 遥测埋点 ─────────────────────────────────────────────
  print('\n=== 2. Telemetry ===');
  print(telemetry.recent.map((TelemetryEvent e) => e.name).join(', '));

  // ── 3. 技能沉淀（同一序列 3 次后自动提取） ───────────────────
  print('\n=== 3. Skill ===');
  final SkillLibrary skills = provideSkillLibrary(app, tools: app.tools);
  for (int i = 0; i < 3; i++) {
    skills.record('报时并复述', const <SkillStep>[
      SkillStep(toolName: 'get_time'),
      SkillStep(
          toolName: 'echo', arguments: <String, Object?>{'text': '{{text}}'}),
    ]);
  }
  final SkillTool? skill = await skills.maybeExtract(
    tools: app.tools,
    namer: deterministicSkillNamer,
  );
  print('沉淀技能：${skill?.name}（${skill?.description}）');
  if (skill != null) {
    final ToolResult skillResult = await app.tools.call(
      const ToolCall(
        name: 'skill_get_time_echo',
        arguments: <String, Object?>{'text': '报时完成'},
      ),
    );
    print('技能执行结果：${skillResult.content}');
  } else {
    print('技能提取未完成，跳过技能调用演示');
  }

  // ── 4. 快照与恢复 ───────────────────────────────────────────
  print('\n=== 4. Persistence & Recovery ===');
  final RecoveryService recovery = provideRecovery(app);
  await recovery.snapshot(session);
  final Session resumed = await recovery.restore('demo');
  print('会话 "${resumed.id}" 恢复事件数：${resumed.length}');

  app.dispose();
  print('\n完成。');
}

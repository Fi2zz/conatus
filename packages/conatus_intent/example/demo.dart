// conatus_intent 端到端 Demo：完全离线，无需任何 API Key。
//
// 演示意图路由的完整链路：正则命中（零模型调用）→ 工具动作（模型收口）
// → 向量命中（本地嵌入）→ 从 JSON 加载配置 → 未命中落回 Agent Loop
// → 未命中积累出候选意图。
//
// 运行：
//   cd packages/conatus_intent
//   dart run example/demo.dart

import 'dart:convert';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_intent/conatus_intent.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 离线替身模型：只回一句话，并记录被调用了几次。
///
/// 用它来证明「命中意图的输入不产生模型调用」。
class OfflineModel implements LlmProvider {
  int calls = 0;
  final List<String> _seen = <String>[];

  /// 被问过的用户输入。
  List<String> get seen => List<String>.unmodifiable(_seen);

  @override
  String get name => 'offline';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    final String lastUser = messages
        .lastWhere(
          (LlmMessage m) => m.role == 'user',
          orElse: () => const LlmMessage('user', ''),
        )
        .content;
    _seen.add(lastUser);
    return LlmResult(
      content: '（离线模型）我理解你的意思是「$lastUser」，需要更多信息才能处理。',
      provider: 'offline',
      model: 'offline-1',
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

/// 假的设备状态，代替真实硬件。
final Map<String, bool> devices = <String, bool>{'light': false, 'ac': false};

Future<void> main() async {
  final Context app = Context.root(name: 'intent-demo');
  final OfflineModel model = OfflineModel();
  final InMemoryTelemetry telemetry = InMemoryTelemetry();

  // ── 基础设施：遥测 / 工具 / system prompt / 模型 / 会话 ──────────
  provideTelemetry(app, telemetry: telemetry);
  final ToolRegistry tools = provideTools(app);
  provideSystemPrompt(app);
  app.provide('llm', model);
  final Session session = Session(id: 'intent-demo');

  tools.fn(
    'device_control',
    description: '开关设备',
    params: <ParamSpec>[
      ParamSpec.string('device', required: true),
      ParamSpec.string('op', required: true),
    ],
    handler: (ToolContext ctx) async {
      final String device = ctx.str('device');
      final bool on = ctx.str('op') == 'on';
      devices[device] = on;
      return ToolResult.success('$device 已${on ? '打开' : '关闭'}');
    },
  );
  tools.fn(
    'weather_now',
    description: '查当前天气',
    handler: (ToolContext ctx) async => ToolResult.success('北京晴，26 度'),
  );

  // ── 意图路由器：必须早于 provideAgentLoop（它构造时读取 'router'）──
  final IntentRouter router = provideIntentRouter(
    app,
    session: session,
    embedder: LocalEmbeddingProvider(),
  );

  // 1. 代码里直接注册：直接动作
  router.register(Intent(
    name: 'greeting',
    description: '问候',
    patterns: <Pattern>[RegExp(r'^(你好|hi|hello)')],
    action: const DirectAction.respond('你好，有什么可以帮你？'),
  ));

  // 2. 代码里直接注册：工具动作 + 参数插值
  router.register(Intent(
    name: 'light_on',
    description: '开灯',
    patterns: <Pattern>[RegExp(r'^(开灯|把灯打开)')],
    examples: <String>['把灯打开'],
    priority: 10,
    action: const ToolAction(
      tool: 'device_control',
      argsTemplate: <String, Object?>{'device': 'light', 'op': 'on'},
    ),
  ));

  // 3. 从 JSON 加载配置：respond / tool / builtin / delegate 四种动作
  await IntentLoader(
    router: router,
    handlers: <String, IntentHandler>{
      'morning': (RouteContext ctx) async => '早上好。今天 26 度，晴。',
    },
  ).loadFromJson(jsonDecode(_config) as Map<String, Object?>);

  final AgentLoop agent = provideAgentLoop(app, session: session);
  print('已注册 ${router.intents.length} 个意图、${tools.names.length} 个工具。\n');

  // ── 场景 ────────────────────────────────────────────────────────
  await _run(agent, '你好', '直接动作：零模型调用');
  await _run(agent, '开灯', '工具动作：预置调用后由模型收口');
  await _run(agent, '早上好', '内置处理器：零模型调用');
  await _run(agent, '把灯打开', '正则命中（priority 10）');
  await _run(agent, '今天天气怎么样', '未命中：落回完整 Agent Loop');

  _printRouting(telemetry);
  await _printLearner(router);

  print('\n设备状态：$devices');
  print('模型总调用次数：${model.calls}');
  print('  · 直接动作 / 内置处理器命中：0 次');
  print('  · 工具动作命中：每次 1 次（由模型收口）');
  print('  · 未命中：每次 1 次（完整 Agent Loop）');
  app.dispose();
  print('\n完成。');
}

Future<void> _run(AgentLoop agent, String input, String label) async {
  final AgentTurn turn = await agent.run(input);
  print(label);
  print('  用户：$input');
  print('  助手：${turn.reply}');
  if (turn.steps.isNotEmpty) {
    print(
        '  工具：${turn.steps.map((AgentStep s) => s.result.content).join('；')}');
  }
  print('');
}

void _printRouting(InMemoryTelemetry telemetry) {
  print('── 路由埋点 ──');
  for (final TelemetryEvent event in telemetry.recent) {
    if (event.name.startsWith('intent.')) {
      print('  ${event.name} ${jsonEncode(event.data)}');
    }
  }
  print('');
}

Future<void> _printLearner(IntentRouter router) async {
  // 未命中的输入被学习器记下来；攒够次数后让模型提取候选（这里用离线替身）。
  final IntentLearner learner = IntentLearner(
    llm: _CandidateModel(),
    minOccurrences: 2,
  );
  learner.attach(router);
  for (var i = 0; i < 2; i++) {
    await router.route('帮我订一张去上海的票');
  }
  await Future<void>.delayed(const Duration(milliseconds: 10));

  final List<IntentCandidate> candidates = await learner.extractCandidates();
  print('── 学习器候选（只产出候选，不自动注册）──');
  for (final IntentCandidate candidate in candidates) {
    print('  ${jsonEncode(candidate.toJson())}');
  }
}

/// 学习器的离线替身模型：直接给出一段 JSON。
class _CandidateModel implements LlmProvider {
  @override
  String get name => 'candidate';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      const LlmResult(
        content: '{"candidates": [{"name": "book_ticket", "description": "订票", '
            '"patterns": ["^(订票|订一张)"], "examples": ["帮我订一张去上海的票"]}]}',
        provider: 'candidate',
        model: 'candidate-1',
      );

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

const String _config = '''
{
  "intents": [
    {
      "name": "morning_routine",
      "description": "晨间例行",
      "patterns": ["^(早上好|晨间播报)"],
      "action": {"type": "builtin", "handler": "morning"}
    },
    {
      "name": "weather",
      "description": "查天气",
      "patterns": ["^(查天气|天气怎么样)"],
      "examples": ["今天天气", "外面冷不冷"],
      "action": {
        "type": "tool",
        "tool": "weather_now",
        "args": {"query": "{{input}}"}
      }
    },
    {
      "name": "code_review",
      "description": "代码审查",
      "patterns": ["^(审查代码|review code)"],
      "action": {"type": "delegate", "skill": "code-review"}
    },
    {
      "name": "thanks",
      "description": "道谢",
      "patterns": ["^(谢谢|thanks)"],
      "action": {"type": "respond", "text": "不客气。"}
    }
  ]
}
''';

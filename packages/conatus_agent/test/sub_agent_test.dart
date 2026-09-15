import 'dart:async';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.script);

  final List<LlmResult> script;
  final List<List<Map<String, dynamic>>?> toolSchemas =
      <List<Map<String, dynamic>>?>[];

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    toolSchemas.add(tools);
    final int index = toolSchemas.length - 1 < script.length
        ? toolSchemas.length - 1
        : script.length - 1;
    return script[index];
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

class _ThrowingProvider implements LlmProvider {
  @override
  String get name => 'boom';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      throw const LlmException('boom', '模型不可用');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

class _BlockingProvider implements LlmProvider {
  final Completer<LlmResult> gate = Completer<LlmResult>();
  int calls = 0;

  @override
  String get name => 'blocking';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    calls++;
    if (calls == 1) return gate.future;
    return Future<LlmResult>.value(
      const LlmResult(content: 'late', provider: 'blocking', model: 'm'),
    );
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

LlmResult _call(String id, String name, [String args = '{}']) => LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: args)
      ],
    );

ToolRegistry _parentTools() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    description: '返回当前时间',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  return tools;
}

Set<String> _schemaNames(List<Map<String, dynamic>>? schemas) => <String>{
      for (final Map<String, dynamic> schema
          in schemas ?? const <Map<String, dynamic>>[])
        schema['name'] as String,
    };

void main() {
  group('SpawnAgentTool — 隔离与白名单', () {
    test('显式白名单只暴露指定工具，只回传结论', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      parent.fn(
        'danger',
        riskLevel: ToolRisk.high,
        handler: (ToolContext ctx) async => ToolResult.success('boom'),
      );
      final _ScriptedProvider provider = _ScriptedProvider(
          <LlmResult>[_call('c1', 'get_time'), _text('结论是 12:00')]);
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
      );

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': '查现在几点',
          'tools': <Object?>['get_time'],
        },
      )));

      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['status'], 'success');
      expect(value['output'], '结论是 12:00');
      expect(value['tool_calls'], <String>['get_time']);
      expect(_schemaNames(provider.toolSchemas.first), <String>{'get_time'});
      host.dispose();
    });

    test('默认白名单排除 high 风险与 spawn_agent 自身', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      parent.fn('write',
          riskLevel: ToolRisk.medium,
          handler: (ToolContext ctx) async => ToolResult.success(''));
      parent.fn('danger',
          riskLevel: ToolRisk.high,
          handler: (ToolContext ctx) async => ToolResult.success(''));
      final _ScriptedProvider provider =
          _ScriptedProvider(<LlmResult>[_text('ok')]);
      final SpawnAgentTool spawn =
          SpawnAgentTool(host: host, llm: provider, tools: parent);
      parent.register(spawn);

      await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '随便做点什么'},
      )));

      expect(_schemaNames(provider.toolSchemas.first),
          <String>{'get_time', 'write'});
      host.dispose();
    });

    test('子 Agent 失败收敛为 status=failed', () async {
      final Context host = Context.root();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: _ThrowingProvider(),
        tools: _parentTools(),
      );

      final ToolResult result = await spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': 'x'},
      )));

      expect((result.value! as Map<String, Object?>)['status'], 'failed');
      host.dispose();
    });

    test('宿主释放终止在途子 Agent', () async {
      final Context host = Context.root();
      final ToolRegistry parent = _parentTools();
      final _BlockingProvider provider = _BlockingProvider();
      final SpawnAgentTool spawn = SpawnAgentTool(
        host: host,
        llm: provider,
        tools: parent,
        defaultTools: <String>['get_time'],
      );

      final Future<ToolResult> pending = spawn.call(const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{'task': '长时间任务'},
      )));
      await Future<void>.delayed(Duration.zero);
      host.dispose();
      provider.gate.complete(_call('c1', 'get_time'));

      final ToolResult result = await pending;
      expect((result.value! as Map<String, Object?>)['status'], 'failed');
    });
  });

  group('provideSpawnAgent', () {
    test('从上下文取 llm/tools 并注册 spawn_agent', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = _parentTools();
      provideLlm(
        ctx,
        llm: FallbackLlm(<LlmProvider>[
          _ScriptedProvider(<LlmResult>[_text('ok')])
        ]),
      );

      provideSpawnAgent(ctx, tools: tools);

      expect(tools.get('spawn_agent'), isNotNull);
      ctx.dispose();
      expect(tools.get('spawn_agent'), isNull);
    });
  });
}

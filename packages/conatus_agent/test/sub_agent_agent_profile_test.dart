/// `spawn_agent` 的 `agent` 参数：profile 白名单 / 步数 / 人设 / 模型与未知 Agent。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _Resolver implements SubAgentProfileResolver {
  _Resolver(this.profiles);

  final Map<String, SubAgentProfile> profiles;

  @override
  Future<SubAgentProfile?> resolve(String agentId) async => profiles[agentId];
}

class _RecordingProvider implements LlmProvider {
  _RecordingProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> messages = <List<LlmMessage>>[];
  final List<List<Map<String, dynamic>>?> toolSchemas =
      <List<Map<String, dynamic>>?>[];
  int calls = 0;

  @override
  String get name => 'recording';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    this.messages.add(messages);
    toolSchemas.add(tools);
    final int index = calls < script.length ? calls : script.length - 1;
    calls++;
    return script[index];
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

LlmResult _text(String content) =>
    LlmResult(content: content, provider: 'recording', model: 'm');

LlmResult _call(String id, String name) => LlmResult(
      content: '',
      provider: 'recording',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

ToolRegistry _registry() {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  tools.fn(
    'read_file',
    handler: (ToolContext ctx) async => ToolResult.success('文件内容'),
  );
  tools.fn(
    'write_file',
    riskLevel: ToolRisk.medium,
    handler: (ToolContext ctx) async => ToolResult.success('w'),
  );
  return tools;
}

Set<String> _names(List<Map<String, dynamic>>? schemas) => <String>{
      for (final Map<String, dynamic> schema
          in schemas ?? const <Map<String, dynamic>>[])
        schema['name'] as String,
    };

String _system(List<LlmMessage> messages) => messages
    .where((LlmMessage message) => message.role == 'system')
    .map((LlmMessage message) => message.content)
    .join('\n');

void main() {
  test('profile 决定工具交集、步数与人设，并使用 profile 模型', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final ToolRegistry registry = _registry();
    final _RecordingProvider assigned = _RecordingProvider(<LlmResult>[
      _call('c1', 'get_time'),
      _call('c2', 'get_time'),
      _text('done'),
    ]);
    final _RecordingProvider hostLlm =
        _RecordingProvider(<LlmResult>[_text('host')]);
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: hostLlm,
      tools: registry,
      profileResolver: _Resolver(<String, SubAgentProfile>{
        'reviewer': SubAgentProfile(
          id: 'reviewer',
          system: 'REVIEW ONLY',
          steps: 2,
          tools: const <String>['read_file'],
          llm: assigned,
        ),
      }),
    );

    final ToolResult result = await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{'task': 'review', 'agent': 'reviewer'},
    )));

    expect(result.isError, isFalse);
    expect(hostLlm.calls, 0, reason: 'profile 模型优先于宿主模型');
    expect(assigned.calls, 2, reason: 'profile.steps 覆盖默认步数');
    expect(_names(assigned.toolSchemas.first), <String>{'read_file'});
    expect(_system(assigned.messages.first), contains('REVIEW ONLY'));
    expect(
        (result.value! as Map<String, Object?>)['output'], contains('最大步数 2'));
  });

  test('profile.disabledTools 从默认白名单中减去', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final _RecordingProvider provider =
        _RecordingProvider(<LlmResult>[_text('ok')]);
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: provider,
      tools: _registry(),
      defaultTools: const <String>['get_time', 'read_file'],
      profileResolver: _Resolver(<String, SubAgentProfile>{
        'reader': const SubAgentProfile(
          id: 'reader',
          system: 'READ',
          disabledTools: <String>['get_time'],
        ),
      }),
    );

    await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{'task': 'read', 'agent': 'reader'},
    )));

    expect(_names(provider.toolSchemas.first), <String>{'read_file'});
  });

  test('未知 agent 返回 UNKNOWN_AGENT，不静默降级', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final _RecordingProvider provider =
        _RecordingProvider(<LlmResult>[_text('ok')]);
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: provider,
      tools: _registry(),
      profileResolver: _Resolver(const <String, SubAgentProfile>{}),
    );

    final ToolResult result = await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{'task': 'x', 'agent': 'missing'},
    )));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'UNKNOWN_AGENT');
    expect(provider.calls, 0);
  });
}

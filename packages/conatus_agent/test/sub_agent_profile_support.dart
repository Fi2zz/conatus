/// `spawn_agent` profile 测试的共用替身。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

class FakeProfileResolver implements SubAgentProfileResolver {
  FakeProfileResolver(this.profile);

  final SubAgentProfile profile;

  @override
  Future<SubAgentProfile?> resolve(String agentId) async =>
      agentId == profile.id ? profile : null;
}

class RecordingProvider implements LlmProvider {
  RecordingProvider(this.script);

  final List<LlmResult> script;
  final List<List<LlmMessage>> messages = <List<LlmMessage>>[];
  final List<List<Map<String, dynamic>>?> schemas =
      <List<Map<String, dynamic>>?>[];
  int calls = 0;

  @override
  String get name => 'provider';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    this.messages.add(messages);
    schemas.add(tools);
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

class RecordingWrapper implements LlmProvider {
  RecordingWrapper(this.base);

  final LlmProvider base;
  int calls = 0;

  @override
  String get name => 'wrapped-${base.name}';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    calls++;
    return base.chat(messages, options: options, tools: tools);
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      base.chatStream(messages, options: options, tools: tools);

  @override
  void close() {}
}

LlmResult textResult(String content) =>
    LlmResult(content: content, provider: 'p', model: 'm');

LlmResult callResult(String id, String name) => LlmResult(
      content: '',
      provider: 'p',
      model: 'm',
      toolCalls: <LlmToolCall>[LlmToolCall(id: id, name: name)],
    );

ToolRegistry fakeTools({List<String>? writes}) {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_time',
    handler: (ToolContext ctx) async => ToolResult.success('12:00'),
  );
  tools.fn(
    'read_file',
    handler: (ToolContext ctx) async => ToolResult.success('内容'),
  );
  tools.fn(
    'write_file',
    riskLevel: ToolRisk.medium,
    handler: (ToolContext ctx) async {
      writes?.add('write_file');
      return ToolResult.success('w');
    },
  );
  return tools;
}

Set<String> schemaNames(List<Map<String, dynamic>>? schemas) => <String>{
      for (final Map<String, dynamic> schema
          in schemas ?? const <Map<String, dynamic>>[])
        schema['name'] as String,
    };

String systemText(List<LlmMessage> messages) => messages
    .where((LlmMessage message) => message.role == 'system')
    .map((LlmMessage message) => message.content)
    .join('\n');

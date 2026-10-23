/// profile 的工具交集、人设回退与模型包装。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import 'sub_agent_profile_support.dart';

void main() {
  test('requested ∩ profile.tools，profile.steps 覆盖 max_rounds', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final RecordingProvider provider = RecordingProvider(<LlmResult>[
      callResult('c1', 'get_time'),
      callResult('c2', 'get_time'),
      callResult('c3', 'get_time'),
      textResult('done'),
    ]);
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: provider,
      tools: fakeTools(),
      profileResolver: FakeProfileResolver(const SubAgentProfile(
        id: 'reader',
        system: 'READ',
        steps: 2,
        tools: <String>['read_file'],
      )),
    );

    await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{
        'task': 'x',
        'agent': 'reader',
        'max_rounds': 5,
        'tools': <Object?>['read_file', 'get_time'],
      },
    )));

    expect(schemaNames(provider.schemas.first), <String>{'read_file'});
    expect(provider.calls, 2);
  });

  test('profile.llm 经 childLlm 包装，宿主模型不参与', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final RecordingProvider hostLlm =
        RecordingProvider(<LlmResult>[textResult('host')]);
    final RecordingProvider profileLlm =
        RecordingProvider(<LlmResult>[textResult('profile')]);
    final List<LlmProvider> wrappedBases = <LlmProvider>[];
    RecordingWrapper? wrapper;
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: hostLlm,
      tools: fakeTools(),
      profileResolver: FakeProfileResolver(SubAgentProfile(
        id: 'custom',
        system: 'CUSTOM',
        llm: profileLlm,
      )),
      childLlm: (LlmProvider base) {
        wrappedBases.add(base);
        return wrapper = RecordingWrapper(base);
      },
    );

    await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{'task': 'x', 'agent': 'custom'},
    )));

    expect(wrappedBases.single, same(profileLlm));
    expect(wrapper!.calls, 1);
    expect(profileLlm.calls, 1, reason: '包装层委托给 profile 模型');
    expect(hostLlm.calls, 0);
  });

  test('profile.system 为空串时回落到默认人设', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final RecordingProvider provider =
        RecordingProvider(<LlmResult>[textResult('done')]);
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: provider,
      tools: fakeTools(),
      profileResolver: FakeProfileResolver(const SubAgentProfile(
        id: 'empty',
        system: '',
      )),
    );

    await spawn.call(const ToolContext(ToolCall(
      name: 'spawn_agent',
      arguments: <String, Object?>{'task': 'x', 'agent': 'empty'},
    )));

    expect(
        systemText(provider.messages.first), contains(kDefaultSubAgentPrompt));
  });
}

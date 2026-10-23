/// 宿主权限档是硬上限：profile 与模型请求只能收紧。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

import 'sub_agent_profile_support.dart';

const SubAgentProfile _inheritGeneral = SubAgentProfile(
  id: 'general',
  system: 'GENERAL',
);

Future<void> _spawn(SpawnAgentTool spawn) => spawn.call(
      const ToolContext(ToolCall(
        name: 'spawn_agent',
        arguments: <String, Object?>{
          'task': 'x',
          'agent': 'general',
          'permission_mode': 'auto',
        },
      )),
    );

void main() {
  test('宿主 readonly + profile inherit + 请求 auto → 写工具不执行', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final List<String> writes = <String>[];
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: RecordingProvider(<LlmResult>[
        callResult('c1', 'write_file'),
        textResult('done'),
      ]),
      tools: fakeTools(writes: writes),
      permissionMode: SubAgentPermission.readonly,
      profileResolver: FakeProfileResolver(_inheritGeneral),
    );
    await _spawn(spawn);

    expect(writes, isEmpty);
  });

  test('宿主 ask + profile inherit + 请求 auto → 仍逐次审批', () async {
    final Context host = Context.root();
    addTearDown(host.dispose);
    final AutoApproval gate = AutoApproval(false);
    host.provide('approval', gate);
    final List<String> writes = <String>[];
    final SpawnAgentTool spawn = SpawnAgentTool(
      host: host,
      llm: RecordingProvider(<LlmResult>[
        callResult('c1', 'write_file'),
        textResult('done'),
      ]),
      tools: fakeTools(writes: writes),
      permissionMode: SubAgentPermission.ask,
      profileResolver: FakeProfileResolver(_inheritGeneral),
    );
    await _spawn(spawn);

    expect(writes, isEmpty);
    expect(gate.requests, greaterThan(0));
  });
}

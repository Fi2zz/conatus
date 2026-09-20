import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_intent/conatus_intent.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const String _skillJson = '好的，这是模式：\n```json\n{"patterns": ["^(查环境|环境怎么样)"], '
    '"examples": ["空气好吗", "外面冷不冷"]}\n```';

SkillTool _skill(String name, List<String> toolNames) {
  final ToolRegistry tools = ToolRegistry();
  return SkillTool(
    name: name,
    description: '查 $name',
    steps: <SkillStep>[
      for (final String toolName in toolNames) SkillStep(toolName: toolName),
    ],
    tools: tools,
  );
}

void main() {
  group('SkillIntentBridge', () {
    test('propose 生成候选但不注册', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>[_skillJson]);
      final SkillIntentBridge bridge =
          SkillIntentBridge(router: router, llm: llm);

      final Intent? candidate =
          await bridge.propose(_skill('check_env', <String>['web_search']));

      expect(candidate, isNotNull);
      expect(candidate!.name, 'skill_check_env');
      expect(candidate.description, '查 check_env');
      expect(candidate.patterns, hasLength(1));
      expect(candidate.examples, <String>['空气好吗', '外面冷不冷']);
      expect(candidate.action, isA<ToolAction>());
      expect((candidate.action as ToolAction).tool, 'check_env');
      expect(bridge.pending, <Intent>[candidate]);
      expect(router.intents, isEmpty);
    });

    test('propose 的 prompt 带上技能名与步骤', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>[_skillJson]);

      await SkillIntentBridge(router: router, llm: llm)
          .propose(_skill('check_env', <String>['web_search', 'read_file']));

      expect(
        llm.requests.single.last.content,
        contains('web_search → read_file'),
      );
    });

    test('模型输出解析不出时返回 null', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>['我不知道']);

      final Intent? candidate =
          await SkillIntentBridge(router: router, llm: llm)
              .propose(_skill('check_env', <String>['web_search']));

      expect(candidate, isNull);
    });

    test('confirm 注册并出队，reject 只出队', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>[_skillJson, _skillJson]);
      final SkillIntentBridge bridge =
          SkillIntentBridge(router: router, llm: llm);

      final Intent accepted =
          (await bridge.propose(_skill('check_env', <String>['web_search'])))!;
      final Intent rejected =
          (await bridge.propose(_skill('other', <String>['web_search'])))!;

      bridge.reject(rejected);
      expect(bridge.pending, <Intent>[accepted]);

      bridge.confirm(accepted);
      expect(bridge.pending, isEmpty);
      expect(router.intents.single.name, 'skill_check_env');
    });

    test('confirm 重名时抛出且候选仍在待确认里', () async {
      final DefaultIntentRouter router = DefaultIntentRouter();
      addTearDown(router.dispose);
      final FakeLlm llm = FakeLlm(<String>[_skillJson]);
      final SkillIntentBridge bridge =
          SkillIntentBridge(router: router, llm: llm);
      router.register(const Intent(
        name: 'skill_check_env',
        description: '',
        action: DirectAction.respond('已存在'),
      ));

      final Intent candidate =
          (await bridge.propose(_skill('check_env', <String>['web_search'])))!;

      expect(
        () => bridge.confirm(candidate),
        throwsA(isA<IntentException>()),
      );
      expect(bridge.pending, <Intent>[candidate]);
    });
  });

  group('ToolIntentGenerator', () {
    ToolRegistry tools() {
      final ToolRegistry registry = ToolRegistry();
      registry.fn(
        'web_search',
        description: '联网搜索',
        handler: (ToolContext ctx) async => ToolResult.success('ok'),
      );
      registry.fn(
        'read_file',
        description: '读文件',
        handler: (ToolContext ctx) async => ToolResult.success('ok'),
      );
      return registry;
    }

    test('为每个工具生成候选且不注册', () async {
      final FakeLlm llm = FakeLlm(<String>[_skillJson, _skillJson]);

      final List<Intent> intents =
          await ToolIntentGenerator(tools: tools(), llm: llm).generate();

      expect(
        intents.map((Intent i) => i.name),
        <String>['tool_web_search', 'tool_read_file'],
      );
      expect(intents.first.description, '联网搜索');
      expect((intents.first.action as ToolAction).tool, 'web_search');
    });

    test('only 限定生成范围', () async {
      final FakeLlm llm = FakeLlm(<String>[_skillJson]);

      final List<Intent> intents = await ToolIntentGenerator(
        tools: tools(),
        llm: llm,
      ).generate(only: <String>['read_file']);

      expect(intents.single.name, 'tool_read_file');
      expect(llm.requests, hasLength(1));
    });

    test('生成不出的工具被跳过', () async {
      final FakeLlm llm = FakeLlm(<String>['没有 JSON', '没有 JSON']);

      expect(
        await ToolIntentGenerator(tools: tools(), llm: llm).generate(),
        isEmpty,
      );
    });
  });
}

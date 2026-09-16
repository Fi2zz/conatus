import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

class _FixedProvider implements SkillProvider {
  _FixedProvider(this.candidates);

  final List<SkillCandidate> candidates;

  @override
  String get name => 'fake';

  @override
  Future<List<SkillCandidate>> list() async => candidates;

  @override
  Future<SkillDefinition?> load(SkillSummary summary) async => null;
}

SkillSummary _summary(String name, {bool modelInvocable = true}) =>
    SkillSummary(
      name: name,
      description: '$name 的说明。',
      source: kSkillSourceCustom,
      provider: 'fake',
      modelInvocable: modelInvocable,
    );

SkillRegistry _runtimeRegistry({String content = '第一步\n第二步'}) {
  final SkillRegistry registry = SkillRegistry();
  addTearDown(registry.dispose);
  registry.register(SkillRegistration(
    name: 'demo',
    description: '演示技能。',
    content: content,
  ));
  return registry;
}

/// 用 `ctx.tools` 真实调用一次 `skill`，与 `provideSkillTool` 的装配一致。
Future<ToolResult> _call(
  SkillRegistry registry,
  Map<String, Object?> arguments,
) async {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  ctx.effect(() => ctx.tools.register(SkillLoadTool(registry: registry)));
  return ctx.tools.call(ToolCall(name: 'skill', arguments: arguments));
}

String _renderHint(SkillResourceBase? base) => renderSkillResourceHint(
      base,
      'filesystem',
    );

void main() {
  group('SkillLoadTool 形状', () {
    test('名字、参数与风险等级', () {
      final SkillRegistry registry = _runtimeRegistry();
      final SkillLoadTool tool = SkillLoadTool(registry: registry);

      expect(tool.name, 'skill');
      expect(tool.riskLevel, ToolRisk.low);
      expect(tool.params, hasLength(1));
      expect(tool.params.single.name, 'name');
      expect(tool.params.single.required, isTrue);
      expect(tool.params.single.type, ParamType.string);
      expect(tool.toSchema()['name'], 'skill');
    });
  });

  group('SkillLoadTool 加载', () {
    test('正常加载返回技能正文块与规范值', () async {
      final SkillRegistry registry = _runtimeRegistry();
      await registry.refresh();

      final ToolResult result = await _call(
        registry,
        const <String, Object?>{'name': 'demo'},
      );

      expect(result.isError, isFalse);
      expect(result.error, isNull);
      expect(result.content, startsWith('<skill_content name="demo">'));
      expect(result.content, contains('<skill_resources>'));
      expect(result.content, contains('<skill_instructions>'));
      expect(result.content, contains('第一步\n第二步'));
      expect(
        result.content,
        contains('managed by provider "runtime"'),
      );
      expect(
        result.value,
        <String, Object?>{
          'name': 'demo',
          'provider': 'runtime',
          'content': '第一步\n第二步',
        },
      );
    });

    test('名字首尾空白被裁剪后照常加载', () async {
      final SkillRegistry registry = _runtimeRegistry(content: '正文');
      await registry.refresh();

      final ToolResult result = await _call(
        registry,
        const <String, Object?>{'name': ' demo '},
      );

      expect(result.isError, isFalse);
      expect(result.content, contains('正文'));
    });
  });

  group('SkillLoadTool 拒绝', () {
    test('未知技能名返回 SKILL_UNKNOWN', () async {
      final SkillRegistry registry = _runtimeRegistry();
      await registry.refresh();

      final ToolResult result = await _call(
        registry,
        const <String, Object?>{'name': 'ghost'},
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'SKILL_UNKNOWN');
      expect(
        result.error!.message,
        'skill "ghost" is unknown or no longer available',
      );
      expect(result.value, isNull);
    });

    test('已列出但加载不到正文时返回 SKILL_UNKNOWN', () async {
      final SkillRegistry registry = SkillRegistry();
      addTearDown(registry.dispose);
      registry.registerProvider(_FixedProvider(<SkillCandidate>[
        SkillCandidate(summary: _summary('gone')),
      ]));
      await registry.refresh();

      final ToolResult result = await _call(
        registry,
        const <String, Object?>{'name': 'gone'},
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'SKILL_UNKNOWN');
      expect(
        result.error!.message,
        'skill "gone" is unknown or no longer available',
      );
    });

    test('非法技能名返回 SKILL_UNAVAILABLE', () async {
      final SkillRegistry registry = _runtimeRegistry();
      await registry.refresh();

      for (final String name in <String>['Bad Name', '', '带中文']) {
        final ToolResult result = await _call(
          registry,
          <String, Object?>{'name': name},
        );

        expect(result.isError, isTrue);
        expect(result.error!.code, 'SKILL_UNAVAILABLE');
        expect(result.error!.message, 'invalid skill name "$name"');
      }
    });

    test('模型不可调用的技能返回 SKILL_UNAVAILABLE', () async {
      final SkillRegistry registry = SkillRegistry();
      addTearDown(registry.dispose);
      registry.registerProvider(_FixedProvider(<SkillCandidate>[
        SkillCandidate(summary: _summary('quiet', modelInvocable: false)),
      ]));
      await registry.refresh();
      expect(registry.modelInvocable, isEmpty);

      final ToolResult result = await _call(
        registry,
        const <String, Object?>{'name': 'quiet'},
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'SKILL_UNAVAILABLE');
      expect(
        result.error!.message,
        'skill "quiet" is not available for model invocation',
      );
    });
  });

  group('renderSkillContent', () {
    test('四种资源基址给出各自的提示', () {
      expect(
        _renderHint(null),
        'Resources for this skill are managed by provider "filesystem". '
        'Load referenced resources only as needed.',
      );
      expect(
        _renderHint(const SkillDirectoryResource('/tmp/skills/alpha')),
        'Base directory for this skill: /tmp/skills/alpha\n'
        'Resolve relative paths mentioned by this skill against the base '
        'directory before using them. '
        'Load referenced resources only as needed.',
      );
      expect(
        _renderHint(const SkillUrlResource('https://e.com/skills/alpha')),
        'Base URL for this skill: https://e.com/skills/alpha\n'
        'Resolve relative URLs mentioned by this skill against the base URL '
        'before using them. '
        'Load referenced resources only as needed.',
      );
      expect(
        _renderHint(const SkillOpaqueResource('由宿主托管')),
        'Resources for this skill: 由宿主托管\n'
        'Load referenced resources only as needed.',
      );
    });

    test('正文块包裹资源提示与指令', () {
      final SkillDefinition definition = SkillDefinition(
        summary: _summary('alpha'),
        content: '按步骤执行。',
        resourceBase: const SkillDirectoryResource('/tmp/skills/alpha'),
      );

      final String text = renderSkillContent(definition);

      expect(text, startsWith('<skill_content name="alpha">\n'));
      expect(
        text,
        contains('<skill_resources>\n'
            'Base directory for this skill: /tmp/skills/alpha\n'),
      );
      expect(
        text,
        endsWith('</skill_resources>\n\n<skill_instructions>\n'
            '按步骤执行。\n</skill_instructions>\n</skill_content>'),
      );
    });

    test('名字里的引号在属性值中转义', () {
      final String text = renderSkillContent(SkillDefinition(
        summary: _summary('a"b'),
        content: '正文',
      ));

      expect(text, startsWith('<skill_content name="a&quot;b">\n'));
    });
  });
}

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

SkillSummary _summary(String name, String description) => SkillSummary(
      name: name,
      description: description,
      source: kSkillSourceRuntime,
      provider: kSkillRuntimeProvider,
    );

/// 手工装配的 SystemPrompt + SkillRegistry 现场，覆盖 `provideSkillCatalog`
/// 的等价行为而不牵涉 Context。
class _Rig {
  _Rig() {
    section = SkillCatalogSection(registry: registry, prompt: prompt);
    detach = section.attach();
  }

  final SystemPrompt prompt = SystemPrompt();
  final SkillRegistry registry =
      SkillRegistry(refreshDebounce: const Duration(milliseconds: 5));
  late final SkillCatalogSection section;
  late final Disposer detach;

  String render() => prompt.render(prompt.assemble());

  void dispose() {
    detach();
    registry.dispose();
  }
}

void main() {
  group('renderSkillCatalog', () {
    test('框架与逐行格式按传入顺序展开', () {
      final String text = renderSkillCatalog(<SkillSummary>[
        _summary('alpha', '第一件技能。'),
        _summary('beta', '第二件技能。'),
      ]);

      expect(
        text,
        startsWith('<system-reminder>\n$kSkillCatalogIntro\n\n'
            '<available_skills>\n'),
      );
      expect(text, endsWith('\n</system-reminder>'));
      expect(text, contains(kSkillCatalogInstruction));
      expect(
        text,
        contains('- `alpha`: 第一件技能。\n- `beta`: 第二件技能。\n'),
      );
    });

    test('描述折叠换行与连续空白并转义标记', () {
      final String text = renderSkillCatalog(<SkillSummary>[
        _summary('fold', '多行\n描述   带\t空白 & <tag>'),
      ]);

      expect(text, contains('- `fold`: 多行 描述 带 空白 &amp; &lt;tag&gt;\n'));
    });

    test('超长描述截断到上限', () {
      final String text = renderSkillCatalog(
        <SkillSummary>[_summary('long', 'a' * 40)],
        descriptionMaxLength: 20,
      );
      final String head = 'a' * 17;
      final String truncated = '$head...';

      expect(truncated.length, 20);
      expect(text, contains('- `long`: $truncated\n'));
      expect(text, isNot(contains('a' * 21)));
    });
  });

  group('normalizeSkillDescription', () {
    test('正好等于上限时不截断', () {
      final String exact = 'x' * 30;

      expect(normalizeSkillDescription(exact, maxLength: 30), exact);
      expect(normalizeSkillDescription('$exact\n\n', maxLength: 30), exact);
    });

    test('超过上限时截断并以省略号结尾', () {
      final String head = 'b' * 9;
      final String normalized =
          normalizeSkillDescription('b' * 40, maxLength: 12);

      expect(normalized, '$head...');
      expect(normalized.length, 12);
    });

    test('折叠所有空白并去掉首尾', () {
      expect(
        normalizeSkillDescription('  a\n\n b \t c  ', maxLength: 100),
        'a b c',
      );
      expect(normalizeSkillDescription('  \n ', maxLength: 100), isEmpty);
    });
  });

  group('SkillCatalogSection', () {
    test('技能为空时不注册任何段', () {
      final _Rig rig = _Rig();
      addTearDown(rig.dispose);

      expect(rig.prompt.sections, isEmpty);
      expect(rig.render(), isEmpty);
    });

    test('refresh 出现技能后注册段，渲染含技能名', () async {
      final _Rig rig = _Rig();
      addTearDown(rig.dispose);
      expect(rig.prompt.sections, isEmpty);

      rig.registry.register(const SkillRegistration(
        name: 'alpha',
        description: '第一件技能。',
        content: '按步骤执行。',
      ));
      await rig.registry.refresh();

      expect(
        rig.prompt.sections.map((PromptSection s) => s.name),
        <String>[kSkillCatalogSectionName],
      );
      expect(rig.prompt.sections.single.order, kSkillCatalogSectionOrder);
      expect(rig.render(), contains('- `alpha`: 第一件技能。'));
    });

    test('技能撤销并 refresh 后段被撤销', () async {
      final _Rig rig = _Rig();
      addTearDown(rig.dispose);
      final Disposer remove = rig.registry.register(const SkillRegistration(
        name: 'alpha',
        description: '第一件技能。',
      ));
      await rig.registry.refresh();
      expect(rig.prompt.sections, hasLength(1));

      remove();
      await rig.registry.refresh();

      expect(rig.prompt.sections, isEmpty);
      expect(rig.render(), isEmpty);
    });

    test('attach 撤销后段消失且不再重生', () async {
      final _Rig rig = _Rig();
      addTearDown(rig.dispose);
      rig.registry.register(const SkillRegistration(
        name: 'alpha',
        description: '第一件技能。',
      ));
      await rig.registry.refresh();
      expect(rig.prompt.sections, hasLength(1));

      rig.detach();

      expect(rig.prompt.sections, isEmpty);
      rig.registry.register(const SkillRegistration(
        name: 'beta',
        description: '第二件技能。',
      ));
      await rig.registry.refresh();

      expect(rig.prompt.sections, isEmpty);
    });
  });
}

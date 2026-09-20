import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

/// 建一个自带 `dispose` 清理的注册表；合并窗口长到测试期间不会自己触发。
SkillRegistry _registry({
  SkillRegistry? parent,
  SkillVisibility? visible,
  void Function(String message)? onWarning,
}) {
  final SkillRegistry registry = SkillRegistry(
    refreshDebounce: const Duration(hours: 1),
    parent: parent,
    visible: visible,
    onWarning: onWarning,
  );
  addTearDown(registry.dispose);
  return registry;
}

SkillRegistration _skill(
  String name, {
  String description = '说明',
  String content = '正文',
}) =>
    SkillRegistration(name: name, description: description, content: content);

List<String> _namesOf(List<SkillSummary> summaries) => <String>[
      for (final SkillSummary summary in summaries) summary.name,
    ];

/// 只产出一条不可被模型调用的技能，用于验证可见性与 `modelInvocable` 取交集。
class _HiddenProvider implements SkillProvider {
  const _HiddenProvider();

  @override
  String get name => 'hidden';

  @override
  Future<List<SkillCandidate>> list() async => <SkillCandidate>[
        const SkillCandidate(
          summary: SkillSummary(
            name: 'hidden-alpha',
            description: '不可被模型调用',
            source: kSkillSourceCustom,
            provider: 'hidden',
            modelInvocable: false,
          ),
        ),
      ];

  @override
  Future<SkillDefinition?> load(SkillSummary summary) async =>
      SkillDefinition(summary: summary, content: '隐藏正文');
}

void main() {
  group('父子分层', () {
    test('子作用域看到父级技能与自己的技能，父级不受影响', () async {
      final SkillRegistry root = _registry();
      root.register(_skill('alpha'));
      await root.refresh();
      final SkillRegistry child = _registry(parent: root);
      child.register(_skill('beta'));

      await child.refresh();

      expect(_namesOf(child.available), <String>['alpha', 'beta']);
      expect(child.parent, same(root));
      expect(_namesOf(root.available), <String>['alpha']);
    });

    test('同名由子作用域赢下并告警，加载也取子级的正文', () async {
      final List<String> warnings = <String>[];
      final SkillRegistry root = _registry();
      root.register(_skill('alpha', description: '父级说明', content: '父级正文'));
      await root.refresh();
      final SkillRegistry child =
          _registry(parent: root, onWarning: warnings.add);
      child.register(_skill('alpha', description: '子级说明', content: '子级正文'));

      await child.refresh();

      expect(child.available.single.description, '子级说明');
      expect(warnings.single, contains('alpha'));
      expect((await child.load('alpha'))?.content, '子级正文');
      expect((await root.load('alpha'))?.content, '父级正文');
    });

    test('父级新增技能级联到子作用域，子作用域不重跑自己的 provider', () async {
      final SkillRegistry root = _registry();
      root.register(_skill('alpha'));
      await root.refresh();
      final SkillRegistry child = _registry(parent: root);
      await child.refresh();
      int notifications = 0;
      final Disposer off = child.onChange(() => notifications++);
      addTearDown(off);

      root.register(_skill('beta'));
      await root.refresh();

      expect(notifications, 1);
      expect(_namesOf(child.available), <String>['alpha', 'beta']);
    });

    test('子作用域释放后不再跟随父级', () async {
      final SkillRegistry root = _registry();
      root.register(_skill('alpha'));
      await root.refresh();
      final SkillRegistry child = SkillRegistry(parent: root);
      await child.refresh();

      child.dispose();
      root.register(_skill('beta'));
      await root.refresh();

      expect(child.available, isEmpty);
      expect(child.disposed, isTrue);
    });
  });

  group('可见性过滤', () {
    test('被过滤的父级技能不在快照里，也 load 不到', () async {
      final SkillRegistry root = _registry();
      root.register(_skill('proj-alpha', content: '项目正文'));
      root.register(_skill('user-beta', content: '用户正文'));
      await root.refresh();
      final SkillRegistry child = _registry(
        parent: root,
        visible: (SkillSummary summary) => summary.name.startsWith('proj-'),
      );

      await child.refresh();

      expect(child.visibility, isNotNull);
      expect(_namesOf(child.available), <String>['proj-alpha']);
      expect(_namesOf(child.modelInvocable), <String>['proj-alpha']);
      expect(await child.load('user-beta'), isNull);
      expect((await child.load('proj-alpha'))?.content, '项目正文');
    });

    test('过滤只作用于继承的条目，本注册表自己的技能始终可见', () async {
      final SkillRegistry root = _registry();
      root.register(_skill('alpha'));
      await root.refresh();
      final SkillRegistry child =
          _registry(parent: root, visible: (SkillSummary summary) => false);
      child.register(_skill('own-skill'));

      await child.refresh();

      expect(_namesOf(child.available), <String>['own-skill']);
    });

    test('可见性与 modelInvocable 取交集', () async {
      final SkillRegistry root = _registry();
      root.registerProvider(const _HiddenProvider());
      await root.refresh();
      final SkillRegistry child = _registry(parent: root);

      await child.refresh();

      expect(_namesOf(child.available), <String>['hidden-alpha']);
      expect(child.modelInvocable, isEmpty);
      expect((await child.load('hidden-alpha'))?.content, '隐藏正文');
    });
  });

  group('作用域化装配', () {
    test('父子各挂一段目录、各注册一个 skill 工具，互不干扰', () async {
      final Context root = Context.root();
      addTearDown(root.dispose);
      provideTools(root);
      final SystemPrompt rootPrompt = provideSystemPrompt(root);
      final SkillRegistry rootRegistry = await provideSkillRegistry(root);
      provideSkillCatalog(root);
      provideSkillTool(root);
      rootRegistry.register(_skill('alpha', description: '父级技能'));
      await rootRegistry.refresh();

      final SystemPrompt scopedPrompt = SystemPrompt();
      final Context child = root.plugin('scoped', (Context ctx) {});
      provideSystemPrompt(child, prompt: scopedPrompt);
      final SkillRegistry scoped = SkillRegistry(
        parent: rootRegistry,
        visible: (SkillSummary summary) => summary.name != 'hidden',
      );
      addTearDown(scoped.dispose);
      await provideSkillRegistry(child, registry: scoped);
      scoped.register(_skill('scoped-only', description: '子作用域技能'));
      provideSkillTool(child, name: 'skill-scoped');
      final SkillCatalogSection section =
          SkillCatalogSection(registry: scoped, prompt: scopedPrompt);
      child.effect(() => section.attach(name: 'skills-scoped'));
      await scoped.refresh();

      expect(rootPrompt.render(rootPrompt.assemble()),
          allOf(contains('alpha'), isNot(contains('scoped-only'))));
      expect(scopedPrompt.render(scopedPrompt.assemble()),
          allOf(contains('alpha'), contains('scoped-only')));
      expect(rootPrompt.sections.map((PromptSection s) => s.name),
          <String>['skills']);
      expect(scopedPrompt.sections.map((PromptSection s) => s.name),
          <String>['skills-scoped']);
      expect(root.tools.names, containsAll(<String>['skill', 'skill-scoped']));
      expect(identical(child.skillRegistry, scoped), isTrue);
    });

    test('子作用域的 skill 工具只加载本作用域可见的技能', () async {
      final Context root = Context.root();
      addTearDown(root.dispose);
      provideTools(root);
      provideSystemPrompt(root);
      final SkillRegistry rootRegistry = await provideSkillRegistry(root);
      rootRegistry.register(_skill('alpha', content: '父级正文'));
      rootRegistry.register(_skill('blocked', content: '不该被取到'));
      await rootRegistry.refresh();

      final Context child = root.plugin('scoped', (Context ctx) {});
      final SkillRegistry scoped = SkillRegistry(
        parent: rootRegistry,
        visible: (SkillSummary summary) => summary.name != 'blocked',
      );
      addTearDown(scoped.dispose);
      await provideSkillRegistry(child, registry: scoped);
      provideSkillTool(child, name: 'skill-scoped');

      final ToolResult ok = await root.tools.call(const ToolCall(
        name: 'skill-scoped',
        arguments: <String, Object?>{'name': 'alpha'},
      ));
      final ToolResult blocked = await root.tools.call(const ToolCall(
        name: 'skill-scoped',
        arguments: <String, Object?>{'name': 'blocked'},
      ));

      expect(ok.isError, isFalse);
      expect(ok.content, contains('<skill_content name="alpha">'));
      expect(ok.content, contains('父级正文'));
      expect(blocked.isError, isTrue);
      expect(blocked.error?.code, 'SKILL_UNKNOWN');
    });
  });
}

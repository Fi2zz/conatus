/// 技能斜杠命令（`/skill:<技能名>`）：投影、展开、折叠与分发。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 记录每次模型调用的假 provider。
class _RecordingProvider implements LlmProvider {
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];

  @override
  String get name => 'recording';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(messages);
    return const LlmResult(content: '好的', provider: 'recording', model: 'm');
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

  /// 最近一次调用里最后一条 user 消息的正文。
  String get lastUserText => calls.last
      .where((LlmMessage message) => message.role == 'user')
      .last
      .content;
}

/// 只产出一条 `disable-model-invocation` 技能的 provider。
class _UserOnlyProvider implements SkillProvider {
  @override
  String get name => 'filesystem';

  @override
  Future<List<SkillCandidate>> list() async => <SkillCandidate>[
        const SkillCandidate(
          summary: SkillSummary(
            name: 'user-only',
            description: '只给用户手动触发',
            source: kSkillSourceCustom,
            provider: 'filesystem',
            modelInvocable: false,
          ),
        ),
      ];

  @override
  Future<SkillDefinition?> load(SkillSummary summary) async =>
      SkillDefinition(summary: summary, content: '只在用户调用时执行的正文。');
}

SkillDefinition _definition({
  String name = 'release-notes',
  String content = '先读 git log。',
}) =>
    SkillDefinition(
      summary: SkillSummary(
        name: name,
        description: '发布说明',
        source: kSkillSourceRuntime,
        provider: kSkillRuntimeProvider,
      ),
      content: content,
    );

Future<(ConatusTuiController, Context, SkillRegistry, _RecordingProvider)>
    _build({bool withUserOnlySkill = false}) async {
  final Context app = Context.root();
  provideTools(app);
  final _RecordingProvider provider = _RecordingProvider();
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  provideMemory(app);
  final SkillRegistry registry = await provideSkillRegistry(
    app,
    providers: withUserOnlySkill
        ? <SkillProvider>[_UserOnlyProvider()]
        : const <SkillProvider>[],
  );
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'recording',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, registry, provider);
}

void main() {
  group('命令投影', () {
    test('把注册表里的技能投影成 /skill:<技能名> 命令', () async {
      final (_, Context app, SkillRegistry registry, _) = await _build();
      registry.register(const SkillRegistration(
        name: 'release-notes',
        description: '把合并记录改写成发布说明',
        content: '先读 git log。',
      ));
      await registry.refresh();

      final List<TuiCommand> commands = skillTuiCommands(registry);

      expect(commands.map((TuiCommand c) => c.name),
          <String>['skill:release-notes']);
      expect(commands.single.token, '/skill:release-notes');
      expect(commands.single.description, '把合并记录改写成发布说明');
      expect(commands.single.takesArgs, isFalse);
      app.dispose();
    });

    test('未装配注册表时不产出命令', () {
      expect(skillTuiCommands(null), isEmpty);
    });

    test('长描述按菜单宽度截断', () async {
      final (_, Context app, SkillRegistry registry, _) = await _build();
      registry.register(SkillRegistration(
        name: 'verbose',
        description: '说明' * 80,
        content: '正文',
      ));
      await registry.refresh();

      final String description = skillTuiCommands(registry).single.description;

      expect(description.length, kTuiSkillDescriptionMaxLength);
      expect(description, endsWith('...'));
      app.dispose();
    });

    test('skill: 前缀与静态命令命名空间隔离，同名不再冲突', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry registry,
          _) = await _build();
      registry.register(const SkillRegistration(
          name: 'help', description: '技能版帮助', content: '正文'));
      await registry.refresh();

      expect(skillTuiCommands(registry).map((TuiCommand c) => c.name),
          <String>['skill:help']);
      final List<String> names = controller.commands
          .map((TuiCommand c) => c.name)
          .toList();
      expect(names, contains('help'));
      expect(names, contains('skill:help'));
      app.dispose();
    });

    test('disable-model-invocation 的技能对模型隐藏但进用户命令表', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry registry,
          _) = await _build(withUserOnlySkill: true);

      expect(registry.modelInvocable, isEmpty);
      expect(skillTuiCommands(registry).map((TuiCommand c) => c.name),
          <String>['skill:user-only']);
      expect(controller.commands.map((TuiCommand c) => c.name),
          contains('skill:user-only'));
      app.dispose();
    });
  });

  group('展开与折叠', () {
    test('展开成正文块，可选追加补充要求', () {
      final SkillDefinition definition = _definition();

      final String bare = renderSkillPrompt(definition, '');

      expect(bare, startsWith('<skill_content name="release-notes">'));
      expect(bare, contains('先读 git log。'));
      expect(bare, endsWith('</skill_content>'));
      expect(renderSkillPrompt(definition, '生成 1.2.0 的说明'),
          endsWith('生成 1.2.0 的说明'));
    });

    test('折叠回 /skill:<技能名> <补充要求>', () {
      final SkillDefinition definition = _definition();

      expect(collapseSkillPrompt(renderSkillPrompt(definition, '')),
          '/skill:release-notes');
      expect(collapseSkillPrompt(renderSkillPrompt(definition, '生成说明')),
          '/skill:release-notes 生成说明');
      expect(collapseSkillPrompt('普通输入'), '普通输入');
    });
  });

  group('命令菜单', () {
    test('技能命令一并进入 / 菜单过滤', () {
      final TuiCommandMenu menu = TuiCommandMenu(
        commands: () => <TuiCommand>[
          ...tuiCommands,
          const TuiCommand(name: 'skill:release-notes', description: '发布说明'),
        ],
      );

      menu.syncInput('/skill:rel');

      expect(menu.matches.single.name, 'skill:release-notes');
    });

    test('缺省仍只用静态命令表', () {
      final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/');

      expect(menu.matches.length, tuiCommands.length);
    });
  });

  group('分发', () {
    test('/skill:<技能名>：展开正文交给模型，屏上折叠成一行', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry registry,
          _RecordingProvider provider) = await _build();
      registry.register(const SkillRegistration(
        name: 'release-notes',
        description: '发布说明',
        content: '先读 git log。',
      ));
      await registry.refresh();

      await controller.handleLine('/skill:release-notes 生成 1.2.0 的说明');

      expect(provider.lastUserText,
          contains('<skill_content name="release-notes">'));
      expect(provider.lastUserText, contains('先读 git log。'));
      expect(provider.lastUserText, endsWith('生成 1.2.0 的说明'));
      expect(
        controller.transcript.messages
            .where((TuiMessage m) => m.role == TuiRole.user)
            .last
            .text,
        '/skill:release-notes 生成 1.2.0 的说明',
      );
      app.dispose();
    });

    test('disable-model-invocation 的技能用户能直接调用', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry _,
          _RecordingProvider provider) = await _build(withUserOnlySkill: true);

      await controller.handleLine('/skill:user-only');

      expect(provider.lastUserText, contains('只在用户调用时执行的正文。'));
      app.dispose();
    });

    test('裸 /skill 给出用法提示', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry _, _) =
          await _build();

      await controller.handleLine('/skill');

      expect(controller.transcript.messages.last.text, contains(kTuiSkillUsage));
      app.dispose();
    });

    test('skill: 前缀的未知技能仍按未知命令提示', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry _, _) =
          await _build();

      await controller.handleLine('/skill:nope');

      expect(controller.transcript.messages.last.text,
          contains('未知命令：/skill:nope'));
      app.dispose();
    });

    test('未知技能仍按未知命令提示', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry _, _) =
          await _build();

      await controller.handleLine('/nope');

      expect(controller.transcript.messages.last.text,
          contains('未知命令：/nope'));
      app.dispose();
    });

    test('/help 列出技能命令', () async {
      final (ConatusTuiController controller, Context app, SkillRegistry registry,
          _) = await _build();
      registry.register(const SkillRegistration(
          name: 'release-notes', description: '发布说明', content: '正文'));
      await registry.refresh();

      await controller.handleLine('/help');

      expect(controller.transcript.messages.last.text,
          contains('/skill:release-notes'));
      app.dispose();
    });
  });
}

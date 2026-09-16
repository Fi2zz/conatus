import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

Directory _createSkillsDirectory() {
  final Directory root = Directory.systemTemp.createTempSync('conatus-skill-');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  final Directory skills = Directory(
    '${root.path}${Platform.pathSeparator}skills',
  )..createSync();
  return skills;
}

void _writeSkill(Directory directory, String name, String description) {
  File('${directory.path}${Platform.pathSeparator}$name.md').writeAsStringSync(
    '---\nname: $name\ndescription: $description\n---\n做完 $name 的步骤。\n',
  );
}

SkillRoot _skillRoot(Directory skills) => SkillRoot(
      path: skills.path,
      source: kSkillSourceCustom,
      rank: 100,
    );

void main() {
  group('技能插件装配', () {
    test('注册表 → 目录段 → 工具 → 文件系统一条链走通', () async {
      final Directory skills = _createSkillsDirectory();
      _writeSkill(skills, 'greet', '打招呼的技能。');

      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      final SkillRegistry registry = await provideSkillRegistry(ctx);
      provideSkillCatalog(ctx);
      provideSkillTool(ctx);
      await provideSkillFilesystem(ctx, roots: <SkillRoot>[_skillRoot(skills)]);

      expect(registry.available.map((SkillSummary s) => s.name),
          <String>['greet']);
      expect(
        ctx.tools.describe().map((Map<String, Object?> s) => s['name']),
        contains('skill'),
      );
      expect(prompt.render(prompt.assemble()), contains('- `greet`: 打招呼的技能。'));

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'skill',
        arguments: <String, Object?>{'name': 'greet'},
      ));

      expect(result.isError, isFalse);
      expect(result.content, contains('<skill_content name="greet">'));
      expect(result.content, contains('做完 greet 的步骤。'));
    });

    test('watch: false 时目录变化不进入后续快照', () async {
      final Directory skills = _createSkillsDirectory();
      _writeSkill(skills, 'greet', '打招呼的技能。');

      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      provideSystemPrompt(ctx);
      final SkillRegistry registry = await provideSkillRegistry(ctx);
      provideSkillCatalog(ctx);
      provideSkillTool(ctx);
      await provideSkillFilesystem(
        ctx,
        roots: <SkillRoot>[_skillRoot(skills)],
        watch: false,
      );

      // 装配期的 provider 注册还会排一次收集，先等它落地再制造目录变化。
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(registry.available.map((SkillSummary s) => s.name),
          <String>['greet']);

      _writeSkill(skills, 'later', '后加的技能。');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(registry.available.map((SkillSummary s) => s.name),
          <String>['greet']);
    });

    test('缺少 systemPrompt 服务时抛 StateError', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      await provideSkillRegistry(ctx);

      expect(() => provideSkillCatalog(ctx), throwsStateError);
    });

    test('缺少 skillRegistry 服务时装配工具与监听都抛 StateError', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      provideSystemPrompt(ctx);

      expect(() => provideSkillTool(ctx), throwsStateError);
      await expectLater(
        provideSkillFilesystem(ctx),
        throwsStateError,
      );
    });

    test('ctx 释放后服务与目录段都被撤销', () async {
      final Directory skills = _createSkillsDirectory();
      _writeSkill(skills, 'greet', '打招呼的技能。');

      final Context ctx = Context.root();
      provideTools(ctx);
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      final SkillRegistry registry = await provideSkillRegistry(ctx);
      provideSkillCatalog(ctx);
      provideSkillTool(ctx);
      await provideSkillFilesystem(ctx, roots: <SkillRoot>[_skillRoot(skills)]);
      expect(prompt.sections, hasLength(1));

      ctx.dispose();

      expect(ctx.disposed, isTrue);
      expect(registry.disposed, isTrue);
      expect(ctx.localServiceKeys, isNot(contains('skillRegistry')));
      expect(prompt.sections, isEmpty);
      expect(prompt.render(prompt.assemble()), isEmpty);
    });
  });
}

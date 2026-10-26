/// OpenCode / Claude 技能发现根：路径、来源与优先级。
library;

import 'dart:io';

import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

String _path(Directory root, String relative) =>
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

void _writeSkillDocument(String path, String name) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '---\nname: $name\ndescription: 一件用于测试的技能。\n---\n正文\n',
  );
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('conatus-skill-opencode-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  test('项目发现根包含 .opencode/skills 与 .claude/skills', () {
    final List<SkillRoot> roots = defaultSkillRoots(
      projectRoot: root.path,
      includeUserRoots: false,
    );
    final Map<String, SkillRoot> bySource = <String, SkillRoot>{
      for (final SkillRoot root in roots) root.source: root,
    };

    expect(
      bySource[kSkillSourceProjectOpenCode]!.path,
      _path(root, '.opencode/skills'),
    );
    expect(
      bySource[kSkillSourceProjectClaude]!.path,
      _path(root, '.claude/skills'),
    );
  });

  test('项目根优先级：.conatus > .opencode > .agents > .claude', () {
    final List<SkillRoot> roots = defaultSkillRoots(
      projectRoot: root.path,
      includeUserRoots: false,
    );
    final Map<String, int> ranks = <String, int>{
      for (final SkillRoot root in roots) root.source: root.rank,
    };

    expect(ranks[kSkillSourceProjectConatus]!, lessThan(
      ranks[kSkillSourceProjectOpenCode]!,
    ));
    expect(ranks[kSkillSourceProjectOpenCode]!, lessThan(
      ranks[kSkillSourceProjectAgents]!,
    ));
    expect(ranks[kSkillSourceProjectAgents]!, lessThan(
      ranks[kSkillSourceProjectClaude]!,
    ));
  });

  test('用户发现根包含 ~/.config/opencode/skills 与 ~/.claude/skills', () {
    final List<SkillRoot> roots = defaultSkillRoots(
      projectRoot: root.path,
    );
    final Map<String, SkillRoot> bySource = <String, SkillRoot>{
      for (final SkillRoot root in roots) root.source: root,
    };

    expect(
      bySource[kSkillSourceUserOpenCode]!.path,
      endsWith(_path(Directory(''), '.config/opencode/skills')),
    );
    expect(
      bySource[kSkillSourceUserClaude]!.path,
      endsWith(_path(Directory(''), '.claude/skills')),
    );
  });

  test('.opencode/skills 里的技能能被默认根发现', () async {
    _writeSkillDocument(_path(root, '.opencode/skills/release/SKILL.md'), 'release');
    final SkillFilesystemProvider provider = SkillFilesystemProvider(
      roots: defaultSkillRoots(
        projectRoot: root.path,
        includeUserRoots: false,
      ),
    );

    final List<SkillCandidate> candidates = await provider.list();

    expect(candidates.map((SkillCandidate c) => c.summary.name), <String>[
      'release',
    ]);
    expect(
      candidates.single.summary.source,
      kSkillSourceProjectOpenCode,
    );
  });
}

/// 目录发现型 provider：从若干发现根读取 `SKILL.md` 与 `<name>.md`。
library;

import 'dart:io';

import 'skill_markdown.dart';
import 'skill_provider.dart';
import 'skill_types.dart';

/// 一个发现根：[rank] 小的先赢下同名技能。
class SkillRoot {
  /// 构造发现根。
  const SkillRoot({
    required this.path,
    required this.source,
    required this.rank,
  });

  /// 根目录路径。
  final String path;

  /// 来源标签。
  final String source;

  /// 层内权重。
  final int rank;

  @override
  String toString() => '$source($rank): $path';
}

/// 默认发现根：项目根下的 `.conatus/skills`、`.agents/skills`，以及用户目录下
/// `$CONATUS_HOME/skills`、`$CONATUS_AGENTS_HOME/skills`。
List<SkillRoot> defaultSkillRoots({
  String? projectRoot,
  bool includeUserRoots = true,
}) {
  final String root = projectRoot ?? findProjectRoot();
  final List<SkillRoot> roots = <SkillRoot>[
    SkillRoot(
      path: _under(root, '.conatus/skills'),
      source: kSkillSourceProjectConatus,
      rank: 100,
    ),
    SkillRoot(
      path: _under(root, '.agents/skills'),
      source: kSkillSourceProjectAgents,
      rank: 200,
    ),
  ];
  if (includeUserRoots) {
    roots.add(SkillRoot(
      path: _under(_home('CONATUS_HOME', '.conatus'), 'skills'),
      source: kSkillSourceUserConatus,
      rank: 400,
    ));
    roots.add(SkillRoot(
      path: _under(_home('CONATUS_AGENTS_HOME', '.agents'), 'skills'),
      source: kSkillSourceUserAgents,
      rank: 500,
    ));
  }
  return roots;
}

/// 最近的含 `.git` 的祖先目录；找不到时返回 [from]（缺省当前工作目录）。
String findProjectRoot({String? from}) {
  final String fallback = from ?? Directory.current.path;
  String current = fallback;
  while (true) {
    if (Directory(_under(current, '.git')).existsSync()) return current;
    final String parent = Directory(current).parent.path;
    if (parent == current) return fallback;
    current = parent;
  }
}

/// 从发现根读取技能的 provider。
class SkillFilesystemProvider extends SkillProvider {
  /// 构造 provider。
  SkillFilesystemProvider({required this.roots, this.onWarning});

  /// 发现根，按调用方给定顺序。
  final List<SkillRoot> roots;

  /// 条目级失败的上报出口。
  final void Function(String message)? onWarning;

  @override
  String get name => kSkillFilesystemProvider;

  @override
  Future<List<SkillCandidate>> list() async {
    final List<SkillCandidate> candidates = <SkillCandidate>[];
    for (final SkillRoot root in roots) {
      candidates.addAll(await _listRoot(root));
    }
    return candidates;
  }

  @override
  Future<SkillDefinition?> load(SkillSummary summary) async {
    final String? path = summary.path;
    if (path == null) return null;
    final File file = File(path);
    if (!file.existsSync()) return null;
    final SkillDocument document = await _readDocument(file);
    if (document.frontmatter == null) return null;
    return SkillDefinition(
      summary: summary,
      content: document.body,
      resourceBase: SkillDirectoryResource(file.parent.path),
    );
  }

  Future<List<SkillCandidate>> _listRoot(SkillRoot root) async {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(root.path).listSync();
    } on FileSystemException {
      return const <SkillCandidate>[];
    }
    entries.sort(
      (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
    );
    final List<SkillCandidate> candidates = <SkillCandidate>[];
    for (final FileSystemEntity entry in entries) {
      final File? file = _skillFileOf(entry);
      if (file == null) continue;
      final SkillCandidate? candidate = await _candidateFrom(root, file);
      if (candidate != null) candidates.add(candidate);
    }
    return candidates;
  }

  Future<SkillCandidate?> _candidateFrom(SkillRoot root, File file) async {
    final SkillDocument document;
    try {
      document = await _readDocument(file);
    } on FileSystemException catch (error) {
      onWarning?.call('技能文件 ${file.path} 读取失败：$error');
      return null;
    }
    final SkillFrontmatter? frontmatter = document.frontmatter;
    if (frontmatter == null) return null;
    return SkillCandidate(
      rank: root.rank,
      summary: SkillSummary(
        name: frontmatter.name,
        description: frontmatter.description,
        whenToUse: frontmatter.whenToUse,
        modelInvocable: frontmatter.modelInvocable,
        source: root.source,
        provider: name,
        path: file.path,
      ),
    );
  }

  Future<SkillDocument> _readDocument(File file) async {
    final SkillDocument document =
        parseSkillDocument(await file.readAsString());
    final String? error = document.error;
    if (error != null) {
      onWarning?.call('技能文件 ${file.path} 被忽略：$error');
    }
    return document;
  }
}

File? _skillFileOf(FileSystemEntity entry) {
  if (entry is Directory) {
    final File nested = File(_under(entry.path, 'SKILL.md'));
    return nested.existsSync() ? nested : null;
  }
  return entry is File && entry.path.endsWith('.md') ? entry : null;
}

String _under(String base, String relative) =>
    '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

String _home(String envKey, String fallbackDir) {
  final String? fromEnv = Platform.environment[envKey];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final String home = Platform.environment['HOME'] ?? Directory.current.path;
  return _under(home, fallbackDir);
}

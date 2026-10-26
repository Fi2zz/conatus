/// 默认技能发现根：项目根与用户目录的目录列表。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'skill_filesystem_provider.dart' show SkillRoot;
import 'skill_types.dart';

/// 默认发现根。
///
/// 项目根（rank 小者优先）：`.conatus/skills` → `.opencode/skills` →
/// `.agents/skills` → `.claude/skills`。用户根：`$CONATUS_HOME/skills` →
/// `~/.config/opencode/skills` → `$CONATUS_AGENTS_HOME/skills` →
/// `~/.claude/skills`。nava 自己的根始终优先于兼容根。
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
      path: _under(root, '.opencode/skills'),
      source: kSkillSourceProjectOpenCode,
      rank: 150,
    ),
    SkillRoot(
      path: _under(root, '.agents/skills'),
      source: kSkillSourceProjectAgents,
      rank: 200,
    ),
    SkillRoot(
      path: _under(root, '.claude/skills'),
      source: kSkillSourceProjectClaude,
      rank: 275,
    ),
  ];
  if (!includeUserRoots) return roots;
  roots.addAll(<SkillRoot>[
    SkillRoot(
      path: _under(_home('CONATUS_HOME', '.conatus'), 'skills'),
      source: kSkillSourceUserConatus,
      rank: 400,
    ),
    SkillRoot(
      path: _under(resolveHomeDir(), '.config/opencode/skills'),
      source: kSkillSourceUserOpenCode,
      rank: 450,
    ),
    SkillRoot(
      path: _under(_home('CONATUS_AGENTS_HOME', '.agents'), 'skills'),
      source: kSkillSourceUserAgents,
      rank: 500,
    ),
    SkillRoot(
      path: _under(resolveHomeDir(), '.claude/skills'),
      source: kSkillSourceUserClaude,
      rank: 550,
    ),
  ]);
  return roots;
}

/// 最近的含 `.git` 的祖先目录；找不到时返回 [from]（缺省当前工作目录）。
///
/// `.git` 既可能是目录，也可能是工作树 / 子模块里的 gitfile，两者都算项目根。
String findProjectRoot({String? from}) {
  final String fallback = from ?? Directory.current.path;
  String current = fallback;
  while (true) {
    if (_hasGit(current)) return current;
    final String parent = Directory(current).parent.path;
    if (parent == current) return fallback;
    current = parent;
  }
}

bool _hasGit(String dir) {
  final String path = _under(dir, '.git');
  return Directory(path).existsSync() || File(path).existsSync();
}

String _under(String base, String relative) =>
    '$base${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}';

/// 环境变量优先，否则 `$HOME/<fallbackDir>`。
String _home(String envKey, String fallbackDir) {
  final String? fromEnv = Platform.environment[envKey]?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  return _under(resolveHomeDir(), fallbackDir);
}

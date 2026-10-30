/// checkpoint 的排除面：内置默认值、敏感文件、只读前缀与路径判定。
///
/// 排除判定是快照采集、恢复写回与 `/diff` 可见性的**单一事实来源**：三者
/// 不同源的后果实打实（采集漏了恢复就按 rsync 删，采集多了只读目录会被写回）。
/// 产品侧策略（只读目录等）经 [CheckpointPolicy] 注入，包内不含产品目录。
library;

import 'dart:io';

import 'checkpoint_policy.dart';

/// 内置排除的相对路径前缀（**顶层匹配**）：可再生构建产物 / 依赖目录。
/// 与 [CheckpointPolicy.ignore] 取并集——无论配置如何这些都不进快照。
const List<String> kCheckpointDefaultIgnores = <String>[
  'build',
  '.dart_tool',
  'node_modules',
];

/// 版本库元数据目录名。**任意层级都排除**（不是顶层匹配）。
const String kCheckpointVcsDir = '.git';

/// 敏感文件名（**任意层级**，按 basename 匹配）：凭据 / 私钥。
///
/// 为什么必须挡：快照是**明文落盘**（gzip 不是加密），影子实现还会把它写进
/// git 对象库——即便之后删掉检查点，blob 仍留在库里直到 gc 回收。凭据不该
/// 因为「开了检查点」而多出一份副本。
const List<String> kCheckpointSecretNames = <String>[
  '.netrc',
  '.npmrc',
  '.pypirc',
  'credentials.json',
  'id_dsa',
  'id_ecdsa',
  'id_ed25519',
  'id_rsa',
  'secrets.json',
  'secrets.yaml',
  'secrets.yml',
];

/// 敏感文件后缀（任意层级）：证书 / 私钥 / 签名容器。
const List<String> kCheckpointSecretExtensions = <String>[
  '.asc',
  '.jks',
  '.key',
  '.keystore',
  '.p12',
  '.pem',
  '.pfx',
];

/// `.env` 的**安全变体**：模板 / 示例，不含真实凭据，应当照常进快照。
const List<String> kCheckpointEnvSafeSuffixes = <String>[
  '.defaults',
  '.example',
  '.sample',
  '.template',
];

/// 相对路径是否命中排除：敏感文件（任意层级）、[kCheckpointDefaultIgnores]
/// （顶层）、`projectDir` 整树、任意层级的 [kCheckpointVcsDir]、只读前缀、
/// [CheckpointPolicy.excludedPrefixes] 与 [CheckpointPolicy.ignore] 前缀。
///
/// [projectDir] 必须是相对 `root` 的路径（调用方算好再传，见 store 的
/// `projectRel`）；绝对路径会永远匹配不上相对路径。
///
/// 嵌套版本库必须整树排除，两个原因：
///
/// 1. **恢复会删它**。rsync 语义下「不在目标态」的文件会被删；快照若漏掉
///    嵌套仓库，恢复就会把整个子树删掉。
/// 2. **git 收不了它**。`git add` 显式指定嵌套仓库内的路径会**静默跳过**
///    （退出码 0、无告警），实测 `git worktree` / vendor 目录必中。因此
///    归档实现收了它而影子实现收不到，两者语义不一致，恢复时按残缺清单删。
///
/// 故嵌套版本库一律不进快照、也不被恢复删除——代价是该子树的改动不可回滚
/// （它有自己的历史，用户可在其中自行处理）。
///
/// 敏感文件同理：既不收，也不会在恢复时被当成「多余文件」删掉（那会毁掉用户
/// 的凭据文件）。取舍是宁可漏收——漏收的后果是「该文件的改动不可回滚」，
/// 多收的后果是「凭据明文外泄」。
///
/// [extra] 是额外排除集（全局 gitignore 的解析结果，见
/// `global_git_ignore.dart`）。它必须走这里，不能只作用于采集：
/// **采集与删除判定不同源，就是 swiftus 那次删 9119 个文件的根因**。
bool checkpointExcluded(
  String rel,
  String projectRel,
  CheckpointPolicy policy, {
  Set<String> extra = const <String>{},
}) {
  if (extra.contains(rel)) return true;
  if (_hasSegment(rel, kCheckpointVcsDir)) return true;
  if (checkpointReadOnlyPath(rel, policy.readOnlyPrefixes)) return true;
  if (checkpointSensitive(rel)) return true;
  for (final String prefix in kCheckpointDefaultIgnores) {
    if (_under(rel, prefix)) return true;
  }
  for (final String prefix in policy.excludedPrefixes) {
    if (_under(rel, prefix)) return true;
  }
  if (_under(rel, projectRel)) return true;
  for (final String prefix in policy.ignore) {
    if (_under(rel, prefix)) return true;
  }
  return false;
}

/// 敏感文件判定：既不收进快照，也不会在恢复时被当成「多余文件」删掉
/// （那会毁掉用户的凭据文件）。
///
/// 取舍是宁可漏收——漏收的后果是「该文件的改动不可回滚」，多收的后果是
/// 「凭据明文外泄 + 恢复时把旧凭据写回去」。模板类文件（`.env.example` 等）
/// 不含真实凭据，照常进快照。
bool checkpointSensitive(String rel) {
  final int slash = rel.lastIndexOf(Platform.pathSeparator);
  final String name = slash < 0 ? rel : rel.substring(slash + 1);
  if (kCheckpointSecretNames.contains(name)) return true;
  final int dot = name.lastIndexOf('.');
  if (dot > 0 && kCheckpointSecretExtensions.contains(name.substring(dot))) {
    return true;
  }
  // `.env` 及其变体（`.env.local` / `.env.production` …）都是凭据；模板变体
  // 除外。`.envrc` 是 direnv 配置、非凭据，故只匹配 `.env` 与 `.env.` 前缀。
  if (name == '.env' || name.startsWith('.env.')) {
    return !kCheckpointEnvSafeSuffixes.any(name.endsWith);
  }
  return false;
}

/// 相对路径是否落在某个只读前缀下（**顶层、大小写不敏感**）。
///
/// 大小写不敏感：macOS / Windows 的文件系统如此；大小写敏感卷上略微多拒，
/// 与 `underReadOnlyRoot` 的取舍一致。git 树里的路径恒用 `/`。
bool checkpointReadOnlyPath(String rel, List<String> readOnlyPrefixes) {
  final String normalized = rel.replaceAll('\\', '/').toLowerCase();
  for (final String prefix in readOnlyPrefixes) {
    final String p = prefix
        .replaceAll(RegExp(r'[/\\]+$'), '')
        .replaceAll('\\', '/')
        .toLowerCase();
    if (p.isEmpty) continue;
    if (normalized == p || normalized.startsWith('$p/')) return true;
  }
  return false;
}

/// 路径能否作为「按文件读取」的目标：必须是工作区内的相对路径（非绝对、
/// 无 `..`），且不在排除面里（只读前缀 / 凭据 / `build` / `projectDir` …）。
///
/// 读取本身不写盘，但把只读与凭据内容经 `/diff` 摊到屏上同样是泄漏面；
/// 判定与采集 / 恢复同源（[checkpointExcluded]）。
bool checkpointReadablePath(
  String rel,
  String projectRel,
  CheckpointPolicy policy,
) {
  if (rel.isEmpty || _absolutePath(rel)) return false;
  if (rel.split(RegExp(r'[/\\]')).contains('..')) return false;
  return !checkpointExcluded(rel, projectRel, policy);
}

/// 是否绝对路径（POSIX `/`、Windows 盘符、UNC 的 `\\`）。
bool _absolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\') ||
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

/// 路径的任一段是否等于 [segment]。
bool _hasSegment(String rel, String segment) {
  for (final String part in rel.split(Platform.pathSeparator)) {
    if (part == segment) return true;
  }
  return false;
}

/// [rel] 是否等于 [prefix] 或落在其下（顶层匹配）。
bool _under(String rel, String prefix) {
  final String p = prefix.replaceAll(RegExp(r'[/\\]+$'), '');
  if (p.isEmpty) return false;
  return rel == p || rel.startsWith('$p${Platform.pathSeparator}');
}

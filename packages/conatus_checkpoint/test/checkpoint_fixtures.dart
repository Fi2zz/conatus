/// 测试夹具：临时工作区 + 项目数据目录 + 归档 store。
///
/// 产品只读策略（`.opencode` / `.config/opencode`）必须由测试显式注入——
/// 包内默认排除面只含 `build` / `.dart_tool` / `node_modules`。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

/// nava 注入的只读策略：既不进快照，也不被恢复写回 / 删除。
const CheckpointPolicy kProductPolicy = CheckpointPolicy(
  readOnlyPrefixes: <String>['.opencode', '.config/opencode'],
);

/// 平台路径分隔符。
String get pathSep => Platform.pathSeparator;

/// 建临时「工作区 + projectDir」，返回 (store, root, projectDir)。
///
/// [workspace] 非空时工作区落在临时目录的子目录下（恢复越界场景用）。
(ArchiveCheckpointStore, String, String) createArchiveStore({
  int keep = 5,
  List<String> ignore = const <String>[],
  CheckpointPolicy policy = kProductPolicy,
  String workspace = '',
}) {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-cp');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root =
      workspace.isEmpty ? dir.path : '${dir.path}$pathSep$workspace';
  final String projectDir = '$root$pathSep.conatus';
  Directory(projectDir).createSync(recursive: true);
  return (
    ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
      policy: _withIgnore(policy, ignore),
    ),
    root,
    projectDir,
  );
}

/// 在 [policy] 上叠加额外 ignore 前缀（保留只读 / 排除声明）。
CheckpointPolicy _withIgnore(CheckpointPolicy policy, List<String> ignore) {
  if (ignore.isEmpty) return policy;
  return CheckpointPolicy(
    ignore: ignore,
    excludedPrefixes: policy.excludedPrefixes,
    readOnlyPrefixes: policy.readOnlyPrefixes,
  );
}

/// 写工作区文件（自动建父目录）。
void writeWorkspace(String root, String rel, String content) {
  final File file = File('$root$pathSep$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

/// 读工作区文本。
String readWorkspace(String root, String rel) =>
    File('$root$pathSep$rel').readAsStringSync();

/// 工作区文件是否存在。
bool workspaceHas(String root, String rel) =>
    File('$root$pathSep$rel').existsSync();

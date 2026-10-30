/// checkpoint 的文件 IO：相对路径、gzip 存取、写回与符号链接越界校验。
///
/// 快照/恢复都走 `dart:io` 直连（应用级信任域，不经 `'fs'` 接缝）。**存储
/// 一律 gzip 压缩**（`dart:io` 内置 `GZipCodec`，零额外依赖）：内容不以明文
/// 落盘，读时自动回退旧的明文文件（兼容升级前的检查点）。
library;

import 'dart:io';

import 'checkpoint_types.dart';

/// 实体相对 [root] 的相对路径（分隔符规范化）。
String checkpointRelativeTo(FileSystemEntity entity, String root) {
  final List<String> rootSegs = checkpointPathSegments(root);
  final List<String> entitySegs = entity.uri.pathSegments;
  return entitySegs.sublist(rootSegs.length).join(Platform.pathSeparator);
}

/// 把路径拆成非空段（绝对/相对都行；去尾部斜杠）。
List<String> checkpointPathSegments(String path) {
  final String normalized = path.replaceAll(RegExp(r'[/\\]+$'), '');
  return normalized
      .split(Platform.pathSeparator)
      .where((String segment) => segment.isNotEmpty)
      .toList();
}

/// 把 [bytes] 以 gzip 写入 `dir/rel.gz`（父目录自动建，flush 落盘）。
Future<void> checkpointWriteGz(List<int> bytes, String dir, String rel) async {
  final File target = File('$dir${Platform.pathSeparator}$rel.gz');
  target.parent.createSync(recursive: true);
  await target.writeAsBytes(gzip.encode(bytes), flush: true);
}

/// 读 `dir/rel.gz` 解压；`.gz` 不存在时回退明文 `dir/rel`（旧检查点）。
Future<List<int>> checkpointReadGz(String dir, String rel) async {
  final File gz = File('$dir${Platform.pathSeparator}$rel.gz');
  if (gz.existsSync()) return gzip.decode(await gz.readAsBytes());
  return File('$dir${Platform.pathSeparator}$rel').readAsBytes();
}

/// 从检查点目录恢复一个文件到 `root/rel`：读 gz（或明文回退）解压后写回，
/// 父目录自动建。返回目标文件。
Future<File> checkpointRestoreFromGz(
  String srcDir,
  String root,
  String rel,
) async {
  final List<int> bytes = await checkpointReadGz(srcDir, rel);
  await checkpointWriteBytes(root, rel, bytes);
  return File('$root${Platform.pathSeparator}$rel');
}

/// 把 [bytes] 写入 `root/rel`（父目录自动建，flush 落盘）。
///
/// 写入目标是符号链接时先删链接本体（不穿透）再写——恢复两遍式校验与执行
/// 之间的 TOCTOU 窗口兜底。
Future<void> checkpointWriteBytes(
  String root,
  String rel,
  List<int> bytes,
) async {
  final File dst = File('$root${Platform.pathSeparator}$rel');
  if (FileSystemEntity.typeSync(dst.path, followLinks: false) ==
      FileSystemEntityType.link) {
    await dst.delete();
  }
  dst.parent.createSync(recursive: true);
  await dst.writeAsBytes(bytes, flush: true);
}

/// 校验 [rel] 在 [root] 内的恢复目标不会穿透符号链接越出工作区。
///
/// 快照侧 followLinks:false 跳过 symlink，恢复侧必须对等：快照后被跟踪
/// 路径（或其父目录）可能被替换成指向工作区外的 symlink，直接写/删会穿透。
/// 越界抛 CheckpointException（fail-closed），调用方在任何变更发生前调用。
void ensureRestorable(String root, String rel) {
  final String canonicalRoot = Directory(root).resolveSymbolicLinksSync();
  final String target = '$root${Platform.pathSeparator}$rel';
  final Directory parent = File(target).parent;
  if (!parent.existsSync()) return; // 父目录将由 createSync 新建，无链接可穿
  final String canonicalParent = parent.resolveSymbolicLinksSync();
  final bool inside = canonicalParent == canonicalRoot ||
      canonicalParent.startsWith('$canonicalRoot${Platform.pathSeparator}');
  if (!inside) {
    throw CheckpointException('restore-escape', '恢复路径越出工作区：$rel');
  }
}

/// 批量校验（两遍式的第一遍）：任一越界抛异常，此时一个文件都未动。
void ensurePathsRestorable(String root, Iterable<String> rels) {
  for (final String rel in rels) {
    ensureRestorable(root, rel);
  }
}

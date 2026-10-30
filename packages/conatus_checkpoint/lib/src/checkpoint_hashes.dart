/// 基线内容哈希的旁挂文件：`<归档名>.hashes`（gzip 的 `路径 → sha256` 映射）。
///
/// 为什么不放进归档头：容器格式要求清单先于内容写出（gzip 不可随机访问，
/// 事后回填头部不可行），而清单里的 sha256 又必须先读完每个文件的内容才算
/// 出来。于是旧的两遍式实现把**整个工作区读了两遍**——第一遍只为算哈希，
/// 第二遍为写内容。882MB 的工作区就是 1.76GB 的读。
///
/// 解法：清单头只留 `path`/`mtime`/`size`（`stat` 即可得，无需读内容），
/// 内容哈希在第二遍**流式写内容的同时**顺带算出，落到本旁挂文件。
/// 工作区内容因此只读一遍，哈希精度不降。
///
/// 差量快照用 [readCheckpointHashes] 取基线哈希做兜底（mtime+size 未变但
/// 内容变）；文件不存在（旧检查点 / 手删）时返回 `null`，调用方退化为
/// 纯 stat 比较。
library;

import 'dart:convert';
import 'dart:io';

/// 哈希旁挂文件的后缀（紧跟归档名）。
const String kCheckpointHashesSuffix = '.hashes';

/// 某轮检查点的哈希旁挂文件（[archive] 旁边）。
File checkpointHashesFile(File archive) =>
    File('${archive.path}$kCheckpointHashesSuffix');

/// 写哈希旁挂文件（gzip JSON；[hashes] 为空则不写文件）。
void writeCheckpointHashes(File archive, Map<String, String> hashes) {
  if (hashes.isEmpty) return;
  final File target = checkpointHashesFile(archive);
  target.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(hashes))));
}

/// 读哈希旁挂文件；不存在或损坏返回 `null`（调用方退化为纯 stat 比较）。
Map<String, String>? readCheckpointHashes(File archive) {
  final File sidecar = checkpointHashesFile(archive);
  if (!sidecar.existsSync()) return null;
  try {
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(gzip.decode(sidecar.readAsBytesSync())))
            as Map<String, Object?>;
    return <String, String>{
      for (final MapEntry<String, Object?> entry in json.entries)
        if (entry.value is String) entry.key: entry.value! as String,
    };
  } catch (_) {
    return null;
  }
}

/// 删除哈希旁挂文件（幂等）。
void deleteCheckpointHashes(File archive) {
  final File sidecar = checkpointHashesFile(archive);
  if (sidecar.existsSync()) sidecar.deleteSync();
}

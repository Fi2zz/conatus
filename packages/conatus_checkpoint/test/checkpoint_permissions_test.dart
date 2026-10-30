/// E-12：检查点落盘权限收紧——归档 / index 0600、会话目录与影子仓库目录 0700。
///
/// 检查点是工作区内容的**第二落盘面**（含用户可能误留的密钥），此前权限随
/// umask（目录 0755 / 文件 0644），同机其他用户可读。此处对齐 config.toml 与
/// 会话 JSONL 的 600 策略。Windows 无 POSIX 权限位，跳过。
///
/// 影子仓库（`GitShadowStore`）与打开时迁移（`openCheckpointStore`）的权限
/// 用例随后端与工厂在 Task 3 迁入。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

/// 路径权限位（低 12 位）；目录与文件同语义。
int _bits(String path) {
  final FileStat stat = FileStat.statSync(path);
  return stat.mode & 0xFFF;
}

void main() {
  test('归档快照后：归档与 index 为 0600、会话目录 0700', () async {
    if (Platform.isWindows) return;
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    File('$root${pathSep}a.txt').writeAsStringSync('v0');

    await store.snapshot('s1', 0);

    expect(_bits(store.archiveFile('s1', 0).path), 0x180); // 0o600
    expect(_bits(store.indexFile('s1').path), 0x180); // 0o600
    expect(_bits(store.sessionDir('s1').path), 0x1C0); // 0o700
  });
}

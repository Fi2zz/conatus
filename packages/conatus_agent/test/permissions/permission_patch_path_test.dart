/// Important 11：apply_patch 的路径清洗（引号 / 空格 / 八进制 UTF-8）。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

void main() {
  test('带空格的引号路径去掉引号与 a/ 前缀', () {
    final List<String> paths = permissionPatchPaths(
      '--- "a/dir with space/x.txt"\n'
      '+++ "b/dir with space/x.txt"\n'
      '@@ -1 +1 @@\n-a\n+b\n',
    );

    expect(paths, <String>['dir with space/x.txt']);
  });

  test('git 的八进制 UTF-8 路径还原成真实文件名', () {
    final List<String> paths = permissionPatchPaths(
      '--- "a/caf\\303\\251.txt"\n'
      '+++ "b/caf\\303\\251.txt"\n'
      '@@ -1 +1 @@\n-a\n+b\n',
    );

    expect(paths, <String>['café.txt']);
  });

  test('时间戳后缀不进入路径', () {
    final List<String> paths = permissionPatchPaths(
      '--- a/old.txt\t2026-10-22 10:00:00\n'
      '+++ b/new.txt\t2026-10-22 10:00:01\n'
      '@@ -1 +1 @@\n-a\n+b\n',
    );

    expect(paths, <String>['new.txt', 'old.txt']);
  });
}

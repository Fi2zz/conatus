/// diff 应用的纯函数面：上下文失配、尾随换行、字面替换。
library;

import 'package:conatus_diff/conatus_diff.dart';
import 'package:test/test.dart';

void main() {
  test('applyEditText：唯一匹配替换', () {
    expect(applyEditText('a\nb\n', 'b', 'c', false), 'a\nc\n');
  });

  test('applyEditText：多处匹配且 replaceAll=false 返回 null', () {
    expect(applyEditText('a\na\n', 'a', 'b', false), isNull);
  });

  test('applyDiffFile：上下文失配抛 PatchContextException', () {
    final List<DiffFile> files = parseUnifiedDiff(
      '--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-old\n+new\n',
    );
    expect(
      () => applyDiffFile('other\n', files.single),
      throwsA(isA<PatchContextException>()),
    );
  });

  test('applyDiffFile：替换保留尾随换行', () {
    final List<DiffFile> files = parseUnifiedDiff(
      '--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-old\n+new\n',
    );
    expect(applyDiffFile('old\n', files.single), 'new\n');
  });

  test('applyDiffFile：CRLF 内容与 hunk 行逐字匹配', () {
    final List<DiffFile> files = parseUnifiedDiff(
      '--- a/x.txt\r\n+++ b/x.txt\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n',
    );
    expect(applyDiffFile('a\r\n', files.single), 'b\r\n');
  });
}

import 'package:conatus_diff/conatus_diff.dart';
import 'package:test/test.dart';

void main() {
  group('buildUnifiedDiff', () {
    test('相同内容返回空串', () {
      expect(buildUnifiedDiff(oldText: 'a\nb\n', newText: 'a\nb\n', path: 'x'),
          isEmpty);
    });

    test('插入一行：hunk 头与行号正确', () {
      final String diff = buildUnifiedDiff(
        oldText: 'a\nb\nc\n',
        newText: 'a\nb\nX\nc\n',
        path: 'lib/a.dart',
      );
      expect(diff, contains('--- a/lib/a.dart'));
      expect(diff, contains('+++ b/lib/a.dart'));
      expect(diff, contains('@@ -1,3 +1,4 @@'));
      expect(diff, contains(' a\n b\n+X\n c'));
    });

    test('删除 + 修改组合，上下文行带空格前缀', () {
      final String diff = buildUnifiedDiff(
        oldText: '1\n2\n3\n4\n5\n',
        newText: '1\n3\n4\n6\n',
        path: 'x',
      );
      expect(diff, contains('-2'));
      expect(diff, contains('+6'));
    });

    test('旧文本无尾换行也能处理', () {
      final String diff =
          buildUnifiedDiff(oldText: 'a\nb', newText: 'a\nb\nc', path: 'x');
      expect(diff, contains('@@ -1,2 +1,3 @@'));
      expect(diff, contains(' a\n b\n+c'));
    });
  });

  group('diffLines + parseUnifiedDiff 往返', () {
    test('生成 → 解析 → 逐行应用等于新内容', () {
      const String oldText = 'line1\nline2\nline3\nline4\nline5\nline6\n';
      const String newText = 'line1\nline2X\nline3\nline4\nline5\nline7\n';
      final String diff = buildUnifiedDiff(
          oldText: oldText, newText: newText, path: 'lib/a.dart', context: 1);

      final List<DiffFile> files = parseUnifiedDiff(diff);
      expect(files, hasLength(1));
      expect(files.first.path, 'lib/a.dart');
      expect(files.first.hunks, isNotEmpty);

      final List<String> lines = oldText.split('\n')..removeLast();
      for (final DiffHunk hunk in files.first.hunks.reversed) {
        final int start = hunk.oldStart - 1;
        final List<String> expected = <String>[
          for (final String line in hunk.lines)
            if (line.startsWith(' ') || line.startsWith('-')) line.substring(1),
        ];
        expect(lines.sublist(start, start + expected.length), expected);
        final List<String> replacement = <String>[
          for (final String line in hunk.lines)
            if (line.startsWith(' ') || line.startsWith('+')) line.substring(1),
        ];
        lines.replaceRange(start, start + expected.length, replacement);
      }
      expect('${lines.join('\n')}\n', newText);
    });

    test('解析 `--- /dev/null` 新文件用 +++ 路径', () {
      const String patch = '--- /dev/null\n+++ b/new.dart\n'
          '@@ -0,0 +1,2 @@\n+hello\n+world\n';
      final List<DiffFile> files = parseUnifiedDiff(patch);
      expect(files, hasLength(1));
      expect(files.first.path, 'new.dart');
      expect(files.first.hunks.single.newStart, 1);
      expect(files.first.hunks.single.lines, <String>['+hello', '+world']);
    });

    test('无法解析时返回空列表', () {
      expect(parseUnifiedDiff('随便什么\n没有 hunk\n'), isEmpty);
    });
  });
}

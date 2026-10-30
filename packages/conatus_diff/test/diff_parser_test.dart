/// `/diff` 数据层：统一 diff 解析与内存行差异。
library;

import 'package:conatus_diff/conatus_diff.dart';
import 'package:test/test.dart';

void main() {
  group('parseUnifiedDiff', () {
    test('parses hunks, paths and counts', () {
      final List<FileDiff> diffs = parseUnifiedDiff('''
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
-old
+new
 same
''');
      final FileDiff diff = diffs.single;
      expect(diff.path, 'a.txt');
      expect(diff.status, 'modified');
      expect(diff.additions, 1);
      expect(diff.deletions, 1);
      expect(diff.hunks.single.lines.length, 3);
      expect(diff.truncated, isFalse);
    });

    test('supports multiple files and hunks', () {
      final List<FileDiff> diffs = parseUnifiedDiff('''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-a
+A
@@ -10,1 +10,1 @@
-b
+B
--- a/b.txt
+++ b/b.txt
@@ -1,1 +1,2 @@
 keep
+added
''');
      expect(diffs, hasLength(2));
      expect(diffs.first.hunks, hasLength(2));
      expect(diffs.first.additions, 2);
      expect(diffs.first.deletions, 2);
      expect(diffs.last.path, 'b.txt');
      expect(diffs.last.additions, 1);
      expect(diffs.last.deletions, 0);
    });

    test('added and deleted files get their status from /dev/null', () {
      final List<FileDiff> diffs = parseUnifiedDiff('''
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+a
+b
--- a/old.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-a
-b
''');
      expect(diffs.map((FileDiff d) => d.path), <String>['new.txt', 'old.txt']);
      expect(diffs.map((FileDiff d) => d.status), <String>['added', 'deleted']);
      expect(diffs.first.additions, 2);
      expect(diffs.last.deletions, 2);
    });

    test('ignores the no-newline marker', () {
      final FileDiff diff = parseUnifiedDiff('''
--- a/x.txt
+++ b/x.txt
@@ -1,1 +1,1 @@
-old
+new
\\ No newline at end of file
''').single;
      expect(diff.additions, 1);
      expect(diff.deletions, 1);
      expect(diff.hunks.single.lines, <String>['-old', '+new']);
    });

    test('content lines that look like headers stay inside the hunk', () {
      final List<FileDiff> diffs = parseUnifiedDiff(
        '--- a/q.sql\n+++ b/q.sql\n@@ -1,2 +1,2 @@\n'
        '--- old note\n+++ new note\n x\n',
      );
      expect(diffs, hasLength(1));
      expect(diffs.single.path, 'q.sql');
      expect(diffs.single.additions, 1);
      expect(diffs.single.deletions, 1);
      expect(diffs.single.hunks.single.lines, <String>[
        '--- old note',
        '+++ new note',
        ' x',
      ]);
    });

    test('binary markers degrade to a file-level entry', () {
      final FileDiff diff = parseUnifiedDiff(
        'diff --git a/img.png b/img.png\n'
        'Binary files a/img.png and b/img.png differ\n',
      ).single;
      expect(diff.path, 'img.png');
      expect(diff.status, 'binary');
      expect(diff.hunks, isEmpty);
    });

    test('pathless binary entries are skipped', () {
      expect(parseUnifiedDiff('Binary files a/x and b/x differ\n'), isEmpty);
    });

    test('recognises renames from git extended headers', () {
      final FileDiff diff = parseUnifiedDiff(
        'diff --git a/old.txt b/new.txt\n'
        'similarity index 100%\n'
        'rename from old.txt\n'
        'rename to new.txt\n',
      ).single;
      expect(diff.path, 'new.txt');
      expect(diff.status, 'renamed');
      expect(diff.hunks, isEmpty);
    });

    test('new file mode without /dev/null is still added', () {
      final FileDiff diff = parseUnifiedDiff(
        'diff --git a/new.txt b/new.txt\n'
        'new file mode 100644\n'
        '--- a/new.txt\n'
        '+++ b/new.txt\n'
        '@@ -0,0 +1,1 @@\n'
        '+hello\n',
      ).single;
      expect(diff.path, 'new.txt');
      expect(diff.status, 'added');
      expect(diff.additions, 1);
    });

    test('GIT binary patch is a binary entry', () {
      final FileDiff diff = parseUnifiedDiff(
        'diff --git a/x.png b/x.png\n'
        'GIT binary patch\n'
        'literal 0\n'
        'HcmV?d00001\n',
      ).single;
      expect(diff.path, 'x.png');
      expect(diff.status, 'binary');
      expect(diff.hunks, isEmpty);
    });

    test('CRLF patches keep content CR and normalise structural lines', () {
      final FileDiff diff = parseUnifiedDiff(
        '--- a/x.txt\r\n+++ b/x.txt\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n',
      ).single;
      expect(diff.path, 'x.txt');
      expect(diff.hunks.single.lines, <String>['-a\r', '+b\r']);
    });

    test('quoted paths with spaces are unquoted', () {
      final FileDiff diff = parseUnifiedDiff(
        'diff --git "a/sp ace.txt" "b/sp ace.txt"\n'
        '--- "a/sp ace.txt"\n'
        '+++ "b/sp ace.txt"\n'
        '@@ -1 +1 @@\n'
        '-a\n'
        '+b\n',
      ).single;
      expect(diff.path, 'sp ace.txt');
      expect(diff.additions, 1);
    });

    test('quoted octal paths decode as UTF-8', () {
      const String quoted = r'"a/\346\226\207.txt"';
      const String target = r'"b/\346\226\207.txt"';
      final FileDiff diff = parseUnifiedDiff(
        'diff --git $quoted $target\n'
        '--- $quoted\n'
        '+++ $target\n'
        '@@ -1 +1 @@\n'
        '-a\n'
        '+b\n',
      ).single;
      expect(diff.path, '文.txt');
    });

    test('hunk headers with omitted counts mean one line', () {
      final DiffHunk hunk = parseUnifiedDiff(
        '--- a/x\n+++ b/x\n@@ -3 +7 @@\n-a\n+b\n',
      ).single.hunks.single;
      expect(hunk.oldStart, 3);
      expect(hunk.oldLines, 1);
      expect(hunk.newStart, 7);
      expect(hunk.newLines, 1);
    });

    test('NUL content marks the file binary and drops hunks', () {
      final FileDiff diff = parseUnifiedDiff(
        '--- a/a.bin\n+++ b/a.bin\n@@ -1,1 +1,1 @@\n-\u0000\u0001\n+\u0000\u0002\n',
      ).single;
      expect(diff.status, 'binary');
      expect(diff.hunks, isEmpty);
    });

    test('empty or unrecognised text yields no files', () {
      expect(parseUnifiedDiff(''), isEmpty);
      expect(parseUnifiedDiff('随便什么\n没有 hunk\n'), isEmpty);
    });
  });

  group('diffLines', () {
    test('handles added and deleted files', () {
      final FileDiff added = diffLines('new.txt', null, 'a\nb').single;
      expect(added.status, 'added');
      expect(added.path, 'new.txt');
      expect(added.additions, 2);
      expect(added.hunks, isNotEmpty);

      final FileDiff deleted = diffLines('old.txt', 'a\nb', null).single;
      expect(deleted.status, 'deleted');
      expect(deleted.deletions, 2);
      expect(deleted.hunks, isNotEmpty);
    });

    test('handles modified content with additions and deletions', () {
      final FileDiff diff = diffLines('m.txt', 'a\nb\nc', 'a\nB\nc').single;
      expect(diff.status, 'modified');
      expect(diff.additions, 1);
      expect(diff.deletions, 1);
      expect(diff.hunks.single.lines, containsAll(<String>['-b', '+B']));
    });

    test('unchanged content yields no diff', () {
      expect(diffLines('same.txt', 'a\nb', 'a\nb'), isEmpty);
      expect(diffLines('nil.txt', null, null), isEmpty);
    });

    test('binary NUL content degrades to file-level', () {
      final FileDiff diff = diffLines(
        'a.bin',
        '\u0000\u0001',
        '\u0000\u0002',
      ).single;
      expect(diff.status, 'binary');
      expect(diff.hunks, isEmpty);
    });

    test('oversized sides are truncated without hunks', () {
      final String huge = List<String>.generate(
        6000,
        (int i) => 'line $i',
      ).join('\n');
      final FileDiff diff = diffLines('huge.txt', '', huge).single;
      expect(diff.truncated, isTrue);
      expect(diff.status, 'modified');
      expect(diff.hunks, isEmpty);
      expect(diff.additions, 0);
      expect(diff.deletions, 0);
    });

    test('one-line edits at 2001 and 5000 lines stay minimal', () {
      for (final int count in <int>[2001, 5000]) {
        final List<String> lines = <String>[
          for (int i = 0; i < count; i++) 'line $i',
        ];
        final String before = lines.join('\n');
        lines[count ~/ 2] = 'changed';
        final FileDiff diff = diffLines(
          'big.txt',
          before,
          lines.join('\n'),
        ).single;
        expect(diff.truncated, isFalse, reason: '$count 行不该被截断');
        expect(diff.additions, 1, reason: '$count 行仍是单行修改');
        expect(diff.deletions, 1, reason: '$count 行仍是单行修改');
        expect(diff.hunks, hasLength(1));
      }
    });

    test('a 5001-line side is file-level truncated', () {
      final List<String> lines = <String>[
        for (int i = 0; i < 5001; i++) 'line $i',
      ];
      final FileDiff diff = diffLines(
        'big.txt',
        lines.join('\n'),
        '${lines.join('\n')}\nextra',
      ).single;
      expect(diff.truncated, isTrue);
      expect(diff.additions, 0);
      expect(diff.deletions, 0);
      expect(diff.hunks, isEmpty);
    });

    test('trailing-newline-only changes are reported', () {
      final FileDiff diff = diffLines('x.txt', 'a\n', 'a').single;
      expect(diff.status, 'modified');
      expect(diff.hunks, isEmpty);
      expect(diff.truncated, isFalse);
    });

    test('LCS budget fallback is marked coarse', () {
      final List<String> lines = <String>[
        for (int i = 0; i < 2001; i++) 'line $i',
      ];
      final String before = lines.join('\n');
      lines[0] = 'changed first';
      lines[2000] = 'changed last';
      final FileDiff diff = diffLines(
        'sparse.txt',
        before,
        lines.join('\n'),
      ).single;
      expect(diff.coarse, isTrue);
      expect(diff.truncated, isFalse);
      expect(diff.additions, 2001, reason: '整段替换的退化计数');
      expect(diff.deletions, 2001);
    });
  });
}

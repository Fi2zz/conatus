import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'apply_patch', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late ApplyPatchTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-apply-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = ApplyPatchTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ApplyPatchTool', () {
    test('简单修改 patch 应用成功', () async {
      File('${dir.path}/a.txt').writeAsStringSync('line1\nline2\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,3 @@
 line1
-line2
+line2 changed
+line3
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(
        File('${dir.path}/a.txt').readAsStringSync(),
        'line1\nline2 changed\nline3\n',
      );
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['files'], <String>['a.txt']);
      expect(value['diff'], patch);
    });

    test('多 hunk / 多文件 patch 应用成功', () async {
      File('${dir.path}/a.txt').writeAsStringSync('l1\nl2\nl3\nl4\nl5\n');
      File('${dir.path}/b.txt').writeAsStringSync('b1\nb2\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-l1
+x1
@@ -5,1 +5,1 @@
-l5
+x5
--- a/b.txt
+++ b/b.txt
@@ -1,1 +1,2 @@
 b1
+b1.5
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(
        File('${dir.path}/a.txt').readAsStringSync(),
        'x1\nl2\nl3\nl4\nx5\n',
      );
      expect(File('${dir.path}/b.txt').readAsStringSync(), 'b1\nb1.5\nb2\n');
      expect((result.value! as Map<String, Object?>)['files'], <String>[
        'a.txt',
        'b.txt',
      ]);
    });

    test('上下文不匹配 → PATCH_CONTEXT', () async {
      File('${dir.path}/a.txt').writeAsStringSync('aaa\nbbb\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1,1 +1,1 @@
-wrong
+zzz
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_CONTEXT');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'aaa\nbbb\n');
    });

    test('无法解析 → PATCH_INVALID', () async {
      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': '这不是 diff 文本'}),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_INVALID');
    });

    test('新文件 patch（--- /dev/null）创建文件', () async {
      const String patch = '''
--- /dev/null
+++ b/new.dart
@@ -0,0 +1,2 @@
+void main() {}
+
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(
        File('${dir.path}/new.dart').readAsStringSync(),
        'void main() {}\n',
      );
    });

    test('空文件新增（无 hunk）仍创建文件', () async {
      const String patch = '--- /dev/null\n+++ b/empty.txt\n';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/empty.txt').existsSync(), isTrue);
      expect(File('${dir.path}/empty.txt').readAsStringSync(), '');
    });

    test('CRLF 内容 patch 可应用（保留 \\r）', () async {
      File('${dir.path}/x.txt').writeAsStringSync('a\r\n');
      const String patch =
          '--- a/x.txt\r\n+++ b/x.txt\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/x.txt').readAsStringSync(), 'b\r\n');
    });

    test('仅二进制 patch 返回 PATCH_UNSUPPORTED', () async {
      const String patch = 'diff --git a/x.png b/x.png\n'
          'Binary files a/x.png and b/x.png differ\n';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_UNSUPPORTED');
    });

    test('OpenCode *** 格式：新增文件', () async {
      const String patch = '''
*** Begin Patch
*** Add File: new.txt
+hello
+world
*** End Patch
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/new.txt').readAsStringSync(), 'hello\nworld\n');
      expect((result.value! as Map<String, Object?>)['files'], <String>[
        'new.txt',
      ]);
    });

    test('OpenCode *** 格式：上下文更新与多 hunk', () async {
      File('${dir.path}/a.txt').writeAsStringSync('l1\nl2\nl3\nl4\n');
      const String patch = '''
*** Begin Patch
*** Update File: a.txt
@@
-l1
+x1
@@
 l3
-l4
+x4
*** End Patch
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'x1\nl2\nl3\nx4\n');
    });

    test('OpenCode *** 格式：Delete 与 Move to', () async {
      File('${dir.path}/old.txt').writeAsStringSync('a\nb\n');
      File('${dir.path}/gone.txt').writeAsStringSync('x\n');
      const String patch = '''
*** Begin Patch
*** Update File: old.txt
@@
-b
+c
*** Move to: new.txt
*** Delete File: gone.txt
*** End Patch
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/old.txt').existsSync(), isFalse);
      expect(File('${dir.path}/new.txt').readAsStringSync(), 'a\nc\n');
      expect(File('${dir.path}/gone.txt').existsSync(), isFalse);
    });

    test('OpenCode *** 格式：Add 已存在 / Update 不存在 / 上下文不匹配', () async {
      File('${dir.path}/exists.txt').writeAsStringSync('x\n');
      File('${dir.path}/a.txt').writeAsStringSync('aaa\n');

      final ToolResult add = await tool.call(
        _context(<String, Object?>{
          'patch': '*** Add File: exists.txt\n+y\n',
        }),
      );
      final ToolResult missing = await tool.call(
        _context(<String, Object?>{
          'patch': '*** Update File: nope.txt\n@@\n-a\n+b\n',
        }),
      );
      final ToolResult mismatch = await tool.call(
        _context(<String, Object?>{
          'patch': '*** Update File: a.txt\n@@\n-wrong\n+right\n',
        }),
      );

      expect(add.error!.code, 'PATCH_EXISTS');
      expect(missing.error!.code, 'PATCH_NOT_FOUND');
      expect(mismatch.error!.code, 'PATCH_CONTEXT');
    });

    test('OpenCode *** 格式：@@ 锚点帮助定位', () async {
      File('${dir.path}/a.txt').writeAsStringSync('head\nfind me\ntail\n');
      const String patch = '''
*** Update File: a.txt
@@ find me
-find me
+found me
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(),
          'head\nfound me\ntail\n');
    });

    test('OpenCode *** 格式：未知头 → PATCH_INVALID', () async {
      final ToolResult result = await tool.call(
        _context(<String, Object?>{
          'patch': '*** Nope File: x\n+y\n',
        }),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'PATCH_INVALID');
    });

    test('多文件 patch 第二个失败：返回失败，已应用文件保持已应用', () async {
      File('${dir.path}/a.txt').writeAsStringSync('a\n');
      File('${dir.path}/b.txt').writeAsStringSync('b\n');
      const String patch = '''
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-a
+A
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-nope
+B
''';

      final ToolResult result = await tool.call(
        _context(<String, Object?>{'patch': patch}),
      );

      expect(result.isError, isTrue);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'A\n');
      expect(File('${dir.path}/b.txt').readAsStringSync(), 'b\n');
    });

    test('注册后的 schema 暴露必填 patch 参数', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
      final ToolRegistry tools = provideTools(ctx);
      provideFsTools(ctx, options: const FsToolOptions(enablePatch: true));
      final Map<String, Object?> schema = tools.get('apply_patch')!.toSchema();
      final Map<String, Object?> parameters =
          schema['parameters']! as Map<String, Object?>;
      expect(parameters['required'], contains('patch'));
      ctx.dispose();
    });
  });
}

import 'dart:io';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'glob', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late GlobTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-glob-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = GlobTool(fs: fs);
    File('${dir.path}/a.dart').writeAsStringSync('');
    Directory('${dir.path}/lib').createSync();
    File('${dir.path}/lib/b.dart').writeAsStringSync('');
    Directory('${dir.path}/lib/sub').createSync();
    File('${dir.path}/lib/sub/c.dart').writeAsStringSync('');
    Directory('${dir.path}/.git').createSync();
    File('${dir.path}/.git/keep.txt').writeAsStringSync('');
    Directory('${dir.path}/node_modules').createSync();
    File('${dir.path}/node_modules/x.js').writeAsStringSync('');
    Directory('${dir.path}/build').createSync();
    File('${dir.path}/build/y.js').writeAsStringSync('');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('GlobTool', () {
    test('**/*.dart 递归匹配，跳过 .git / node_modules / build', () async {
      final ToolResult result = await tool
          .call(_context(<String, Object?>{'pattern': '**/*.dart'}));

      expect(result.isError, isFalse);
      final List<Object?> matches =
          (result.value! as Map<String, Object?>)['matches']! as List<Object?>;
      expect(matches, hasLength(3));
      expect(matches, contains('${dir.path}/a.dart'));
      expect(matches, contains('${dir.path}/lib/b.dart'));
      expect(matches, contains('${dir.path}/lib/sub/c.dart'));
    });

    test('*.dart 只匹配根目录', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'pattern': '*.dart'}));

      final List<Object?> matches =
          (result.value! as Map<String, Object?>)['matches']! as List<Object?>;
      expect(matches, hasLength(1));
      expect(matches, <Object?>['${dir.path}/a.dart']);
    });

    test('被跳过目录里的文件不匹配任何模式', () async {
      final ToolResult txt = await tool
          .call(_context(<String, Object?>{'pattern': '**/*.txt'}));
      expect((txt.value! as Map<String, Object?>)['matches'], isEmpty);

      final ToolResult js =
          await tool.call(_context(<String, Object?>{'pattern': '**/*.js'}));
      expect((js.value! as Map<String, Object?>)['matches'], isEmpty);
    });

    test('limit 截断并标记', () async {
      final ToolResult result = await tool.call(_context(
          <String, Object?>{'pattern': '**/*.dart', 'limit': 2}));

      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect((value['matches']! as List<Object?>), hasLength(2));
      expect(value['truncated'], isTrue);
    });

    test('path 指定搜索根', () async {
      final ToolResult result = await tool.call(
          _context(<String, Object?>{'pattern': '*.dart', 'path': 'lib'}));

      final List<Object?> matches =
          (result.value! as Map<String, Object?>)['matches']! as List<Object?>;
      expect(matches, <Object?>['${dir.path}/lib/b.dart']);
    });

    test('无效模式 → GLOB_INVALID_PATTERN', () async {
      final ToolResult result = await tool
          .call(_context(<String, Object?>{'pattern': '['}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'GLOB_INVALID_PATTERN');
    });
  });
}

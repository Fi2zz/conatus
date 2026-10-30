import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'list', arguments: args));

void main() {
  late Directory dir;
  late ListFilesTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-list-');
    tool = ListFilesTool(fs: LocalFileSystem(cwd: dir.path));
    File('${dir.path}/a.dart').writeAsStringSync('');
    Directory('${dir.path}/lib').createSync();
    File('${dir.path}/lib/b.dart').writeAsStringSync('');
    Directory('${dir.path}/lib/sub').createSync();
    File('${dir.path}/lib/sub/c.dart').writeAsStringSync('');
    Directory('${dir.path}/.git').createSync();
    File('${dir.path}/.git/keep.txt').writeAsStringSync('');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ListFilesTool', () {
    test('工具名为 list', () {
      expect(tool.name, 'list');
    });

    test('默认只列一层，目录以 / 结尾，跳过 .git', () async {
      final ToolResult result = await tool.call(_context(<String, Object?>{}));

      expect(result.isError, isFalse);
      final List<Object?> entries =
          (result.value! as Map<String, Object?>)['entries']! as List<Object?>;
      expect(entries, containsAll(<String>['a.dart', 'lib/']));
      expect(entries, isNot(contains('.git/')));
      expect(entries, isNot(contains('lib/b.dart')));
    });

    test('depth=3 展开到子目录，路径带前缀', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'depth': 3}));

      expect(result.isError, isFalse);
      final List<Object?> entries =
          (result.value! as Map<String, Object?>)['entries']! as List<Object?>;
      expect(
          entries,
          containsAll(
              <String>['lib/', 'lib/b.dart', 'lib/sub/', 'lib/sub/c.dart']));
    });

    test('limit 截断并标记 truncated', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'depth': 3, 'limit': 2}));

      expect(result.isError, isFalse);
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect((value['entries']! as List<Object?>).length, 2);
      expect(value['truncated'], isTrue);
    });

    test('不存在的路径返回失败结果', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'nope'}));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'FS_NOT_FOUND');
    });
  });
}

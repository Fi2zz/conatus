import 'dart:io';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'edit_file', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late EditFileTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-edit-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = EditFileTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('EditFileTool', () {
    test('唯一匹配替换', () async {
      File('${dir.path}/a.txt').writeAsStringSync('hello world');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'world',
        'new_string': 'dart',
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'hello dart');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['replacements'], 1);
      expect(value['version'], isA<String>());
    });

    test('多处匹配且非 replace_all → FS_AMBIGUOUS_EDIT', () async {
      File('${dir.path}/a.txt').writeAsStringSync('x x x');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'x',
        'new_string': 'y',
      }));

      expect(result.error!.code, 'FS_AMBIGUOUS_EDIT');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'x x x');
    });

    test('replace_all 替换所有匹配', () async {
      File('${dir.path}/a.txt').writeAsStringSync('x x x');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'x',
        'new_string': 'y',
        'replace_all': true,
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'y y y');
      expect((result.value! as Map<String, Object?>)['replacements'], 3);
    });

    test('old_string 与 new_string 相同 → FS_NO_CHANGE', () async {
      File('${dir.path}/a.txt').writeAsStringSync('abc');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'abc',
        'new_string': 'abc',
      }));

      expect(result.error!.code, 'FS_NO_CHANGE');
    });

    test('未找到 old_string → FS_NOT_FOUND', () async {
      File('${dir.path}/a.txt').writeAsStringSync('abc');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'zzz',
        'new_string': 'y',
      }));

      expect(result.error!.code, 'FS_NOT_FOUND');
    });

    test('expected_version 不匹配 → FS_STALE_VERSION', () async {
      File('${dir.path}/a.txt').writeAsStringSync('hello world');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'old_string': 'world',
        'new_string': 'dart',
        'expected_version': 'nope',
      }));

      expect(result.error!.code, 'FS_STALE_VERSION');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'hello world');
    });
  });
}

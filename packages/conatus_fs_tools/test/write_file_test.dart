import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'write', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late WriteFileTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-write-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = WriteFileTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('WriteFileTool', () {
    test('工具名为 write', () {
      expect(tool.name, 'write');
    });

    test('create 写入新文件', () async {
      final ToolResult result = await tool
          .call(_context(<String, Object?>{'path': 'a.txt', 'content': 'hi'}));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'hi');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['mode'], 'create');
      expect(value['bytes'], 2);
      expect(value['version'], isA<String>());
    });

    test('create 与已存在文件冲突 → FS_NOT_OBSERVED', () async {
      File('${dir.path}/a.txt').writeAsStringSync('old');

      final ToolResult result = await tool
          .call(_context(<String, Object?>{'path': 'a.txt', 'content': 'new'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'FS_NOT_OBSERVED');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'old');
    });

    test('overwrite 覆盖已有文件', () async {
      File('${dir.path}/a.txt').writeAsStringSync('old');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'new',
        'mode': 'overwrite',
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'new');
    });

    test('overwrite 创建不存在的文件', () async {
      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'new',
        'mode': 'overwrite',
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'new');
    });

    test('expected_version 守卫：不匹配 → FS_STALE_VERSION', () async {
      File('${dir.path}/a.txt').writeAsStringSync('old');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'new',
        'mode': 'overwrite',
        'expected_version': 'nope',
      }));

      expect(result.error!.code, 'FS_STALE_VERSION');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'old');
    });

    test('expected_version 守卫：匹配则写入', () async {
      File('${dir.path}/a.txt').writeAsStringSync('old');
      final FsInfo? info = await fs.stat(await fs.resolve('a.txt'));

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'new',
        'mode': 'overwrite',
        'expected_version': info!.version,
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'new');
    });

    test('append 追加已有文件', () async {
      File('${dir.path}/a.txt').writeAsStringSync('a\n');

      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'b',
        'mode': 'append',
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'a\nb');
    });

    test('append 到不存在的文件等价于创建', () async {
      final ToolResult result = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'b',
        'mode': 'append',
      }));

      expect(result.isError, isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'b');
    });

    test('结果携带 diff：overwrite 含 --- a/ 头，create 新文件非空', () async {
      File('${dir.path}/a.txt').writeAsStringSync('old\n');

      final ToolResult overwritten = await tool.call(_context(<String, Object?>{
        'path': 'a.txt',
        'content': 'new\n',
        'mode': 'overwrite',
      }));
      expect(overwritten.isError, isFalse);
      final String overwriteDiff =
          (overwritten.value! as Map<String, Object?>)['diff']! as String;
      expect(overwriteDiff, contains('--- a/a.txt'));
      expect(overwriteDiff, contains('-old'));
      expect(overwriteDiff, contains('+new'));

      final ToolResult created = await tool.call(
          _context(<String, Object?>{'path': 'b.txt', 'content': 'hi\n'}));
      expect(created.isError, isFalse);
      final String createDiff =
          (created.value! as Map<String, Object?>)['diff']! as String;
      expect(createDiff, isNotEmpty);
      expect(createDiff, contains('--- a/b.txt'));
    });
  });
}

import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'read_file', arguments: args));

void main() {
  late Directory dir;
  late LocalFileSystem fs;
  late ReadFileTool tool;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-fs-tools-');
    fs = LocalFileSystem(cwd: dir.path);
    tool = ReadFileTool(fs: fs);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('ReadFileTool', () {
    test('读取文本并带规范值', () async {
      File('${dir.path}/a.txt').writeAsStringSync('你好');

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'a.txt'}));

      expect(result.isError, isFalse);
      expect(result.content, '你好');
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['chars'], 2);
      expect(value['truncated'], isFalse);
      expect(tool.riskLevel, ToolRisk.low);
    });

    test('maxChars 截断并标记', () async {
      File('${dir.path}/a.txt').writeAsStringSync('abcdefgh');
      final ReadFileTool clipped = ReadFileTool(fs: fs, maxChars: 4);

      final ToolResult result =
          await clipped.call(_context(<String, Object?>{'path': 'a.txt'}));

      expect(result.content, 'abcd');
      expect((result.value! as Map<String, Object?>)['truncated'], isTrue);
    });

    test('文件不存在 → FS_NOT_FOUND', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'nope.txt'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'FS_NOT_FOUND');
    });

    test('目录 → FS_NOT_REGULAR_FILE', () async {
      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': '.'}));

      expect(result.error!.code, 'FS_NOT_REGULAR_FILE');
    });

    test('非 UTF-8 → FS_NOT_TEXT', () async {
      File('${dir.path}/bin').writeAsBytesSync(<int>[0xff, 0xfe]);

      final ToolResult result =
          await tool.call(_context(<String, Object?>{'path': 'bin'}));

      expect(result.error!.code, 'FS_NOT_TEXT');
    });

    test('通过注册表调用时参数校验生效', () async {
      final ToolRegistry tools = ToolRegistry()..register(tool);

      final ToolResult result =
          await tools.call(const ToolCall(name: 'read_file'));

      expect(result.error!.code, 'INVALID_ARGS');
    });
  });

  group('provideFsTools', () {
    test('注册 read_file 并随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideFsTools(ctx);

      expect(registered.single.name, 'read_file');
      expect(tools.names, contains('read_file'));
      ctx.dispose();
      expect(tools.names, isEmpty);
    });
  });
}

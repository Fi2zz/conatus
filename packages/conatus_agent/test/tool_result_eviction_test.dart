import 'dart:io';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Context ctx;
  late ToolRegistry tools;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-evict-');
    ctx = Context.root();
    provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
    tools = provideTools(ctx);
  });

  tearDown(() {
    ctx.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('超阈值结果落盘：正文变预览，文件含完整内容且可读回', () async {
    final String big = List<String>.filled(5000, 'A').join();
    ctx.tools
        .fn('big', handler: (ToolContext c) async => ToolResult.success(big));
    provideToolResultEviction(
      ctx,
      threshold: 1000,
      previewChars: 100,
      dir: '${dir.path}/spills',
    );

    final ToolResult result = await tools.call(const ToolCall(name: 'big'));

    expect(result.isError, isFalse);
    expect(result.content.length, lessThan(big.length));
    expect(result.content, contains('省略'));
    expect(result.content, contains('read_file'));

    final Map<String, Object?> value = result.value! as Map<String, Object?>;
    expect(value['spilled'], isTrue);
    final String path = value['path']! as String;
    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), big);

    // read_file 能读回完整内容（直接用工具，绕过注册表再次驱逐）。
    final ReadFileTool reader =
        ReadFileTool(fs: ctx.require<FileSystem>('fs'), maxChars: 10000);
    final ToolResult read = await reader.call(
      ToolContext(ToolCall(
          name: 'read_file', arguments: <String, Object?>{'path': path})),
    );
    expect(read.content, big);
  });

  test('未超阈值不改动结果', () async {
    ctx.tools.fn('small',
        handler: (ToolContext c) async => ToolResult.success('短内容'));
    provideToolResultEviction(ctx, threshold: 1000, dir: '${dir.path}/spills');

    final ToolResult result = await tools.call(const ToolCall(name: 'small'));

    expect(result.content, '短内容');
    expect(result.value, isNull);
  });

  test('失败结果不驱逐', () async {
    ctx.tools.fn(
      'bad',
      handler: (ToolContext c) async =>
          ToolResult.failure(List<String>.filled(5000, 'E').join()),
    );
    provideToolResultEviction(ctx, threshold: 1000, dir: '${dir.path}/spills');

    final ToolResult result = await tools.call(const ToolCall(name: 'bad'));

    expect(result.isError, isTrue);
    expect(result.content.length, 5000);
  });

  test('阈值可经上下文的 toolResultThreshold 提供', () async {
    final Context local = Context.root();
    provideFileSystemLocal(local, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry localTools = provideTools(local);
    local.provide('toolResultThreshold', 10);
    final ToolResultEviction eviction =
        provideToolResultEviction(local, dir: '${dir.path}/spills2');

    localTools.fn('mid',
        handler: (ToolContext c) async =>
            ToolResult.success('0123456789ABCDEF'));
    final ToolResult result =
        await localTools.call(const ToolCall(name: 'mid'));

    expect(eviction.threshold, 10);
    expect((result.value! as Map<String, Object?>)['spilled'], isTrue);
    local.dispose();
  });

  test('上下文释放清理临时文件', () async {
    final Context local = Context.root();
    provideFileSystemLocal(local, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry localTools = provideTools(local);
    localTools.fn('big',
        handler: (ToolContext c) async =>
            ToolResult.success(List<String>.filled(500, 'A').join()));
    final ToolResultEviction eviction = provideToolResultEviction(
      local,
      threshold: 100,
      previewChars: 10,
      dir: '${dir.path}/spills3',
    );

    await localTools.call(const ToolCall(name: 'big'));
    final String path = eviction.spilledPaths.single;
    expect(File(path).existsSync(), isTrue);

    local.dispose();
    // onDispose 的清理是异步的，稍等落定。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(File(path).existsSync(), isFalse);
  });
}

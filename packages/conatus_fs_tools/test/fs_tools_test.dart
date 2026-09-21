import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

void main() {
  late Directory dir;
  late LocalFileSystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-fstools-');
    fs = LocalFileSystem(cwd: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('provideFsTools', () {
    test('无 shell → 注册 4 个工具（无 rg），随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideFsTools(ctx);

      expect(registered.map((Tool t) => t.name),
          containsAll(<String>['read_file', 'write_file', 'edit_file', 'glob']));
      expect(registered.map((Tool t) => t.name), isNot(contains('rg')));
      expect(tools.names,
          containsAll(<String>['read_file', 'write_file', 'edit_file', 'glob']));
      ctx.dispose();
      expect(tools.names, isEmpty);
    });

    test('有 shell 且注入 ripgrep → 注册 rg', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);
      final FakeShellExecutor shell = FakeShellExecutor();

      final List<Tool> registered = provideFsTools(
        ctx,
        shell: shell,
        ripgrep: const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
      );

      expect(registered.map((Tool t) => t.name), contains('rg'));
      expect(tools.names, contains('rg'));
    });

    test('enableSearch=false → 不注册 glob 与 rg', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideFsTools(ctx, enableSearch: false);

      expect(registered.map((Tool t) => t.name),
          <String>['read_file', 'write_file', 'edit_file']);
      expect(tools.names, isNot(contains('glob')));
    });
  });
}

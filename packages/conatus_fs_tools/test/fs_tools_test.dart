import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

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
    test('默认注册 read / write / edit / list / glob，随上下文释放撤销', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideFsTools(ctx);

      expect(registered.map((Tool t) => t.name),
          containsAll(<String>['read', 'write', 'edit', 'list', 'glob']));
      expect(registered.map((Tool t) => t.name), isNot(contains('grep')));
      expect(
          registered.map((Tool t) => t.name), isNot(contains('apply_patch')));
      expect(tools.names, containsAll(<String>['read', 'write', 'edit']));
      expect(tools.names, containsAll(<String>['list', 'glob']));
      ctx.dispose();
      expect(tools.names, isEmpty);
    });

    test('enableSearch=false → 不注册 glob', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered = provideFsTools(ctx,
          options: const FsToolOptions(enableSearch: false));

      expect(registered.map((Tool t) => t.name),
          <String>['read', 'write', 'edit', 'list']);
      expect(tools.names, isNot(contains('glob')));
    });

    test('enablePatch=true → list 之后注册 apply_patch', () {
      final Context ctx = Context.root();
      provideFileSystemLocal(ctx, fs: fs);
      final ToolRegistry tools = provideTools(ctx);

      final List<Tool> registered =
          provideFsTools(ctx, options: const FsToolOptions(enablePatch: true));

      expect(registered.map((Tool t) => t.name),
          containsAllInOrder(<String>['list', 'apply_patch']));
      expect(tools.names, contains('apply_patch'));
      ctx.dispose();
    });
  });
}

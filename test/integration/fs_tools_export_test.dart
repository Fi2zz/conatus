import 'dart:io';

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

void main() {
  test('伞包导出文件工具，产品无需直接依赖模块包', () {
    final Directory dir = Directory.systemTemp.createTempSync(
      'conatus-umbrella-',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final Context ctx = Context.root();
    provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry tools = provideTools(ctx);

    final List<Tool> registered = provideFsTools(
      ctx,
      options: const FsToolOptions(enablePatch: true),
    );

    expect(
      registered.map((Tool tool) => tool.name),
      containsAll(<String>[
        'read',
        'write',
        'edit',
        'list',
        'glob',
        'apply_patch',
      ]),
    );
    final ReadOnlyPathGuard guard = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: const <String>[],
    );
    expect(guard, isA<ReadOnlyPathGuard>());
    expect(
      tools.names,
      containsAll(<String>[
        'read',
        'write',
        'edit',
        'list',
        'glob',
        'apply_patch',
      ]),
    );
    ctx.dispose();
    expect(tools.names, isEmpty);
  });
}

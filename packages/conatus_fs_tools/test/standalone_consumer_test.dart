import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

void main() {
  test('不依赖 conatus_agent 也能装配文件工具，释放后撤销注册', () {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-fs-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final Context ctx = Context.root();
    provideFileSystemLocal(ctx, fs: LocalFileSystem(cwd: dir.path));
    final ToolRegistry tools = provideTools(ctx);

    final List<Tool> registered = provideFsTools(ctx);

    expect(registered.map((Tool t) => t.name),
        containsAll(<String>['read', 'write', 'edit', 'list', 'glob']));
    ctx.dispose();
    expect(tools.names, isEmpty);
  });
}

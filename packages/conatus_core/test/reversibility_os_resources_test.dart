/// 真实 OS 资源（文件描述符）的可逆性检查。
///
/// 合成代理（Timer / Stream / 句柄）只能证明「机制正确」；这里打开的是**真实的
/// 文件句柄**，并用 `lsof` 在 OS 层面数它——这是「效果真落地」与「逆真释放」的
/// 硬证据，不是代理。
///
/// 口径：只数 **FD 名里含本测试临时目录** 的记录，因此与本测试无关的 FD（测试
/// 框架、网络等）完全不干扰计数。
library;

import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

/// 当前进程打开的、FD 名含 [prefix] 的记录数；`lsof` 不存在时返回 `null`。
Future<int?> openFdsUnder(String prefix) async {
  final ProcessResult result = await Process.run('lsof', <String>['-p', '$pid']);
  if (result.exitCode != 0) return null;
  return (result.stdout as String)
      .split('\n')
      .where((String line) => line.contains(prefix))
      .length;
}

/// 一个真实资源效果：打开一个文件句柄；逆是关闭它。
Disposer openRealFile(File file) {
  final RandomAccessFile handle = file.openSync();
  return handle.closeSync;
}

void main() {
  test('真实 FD：3 个文件句柄打开后计数 +3，卸载后回到基线', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-fd-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    if (await openFdsUnder(dir.path) == null) {
      markTestSkipped('本机没有 lsof，无法做 OS 级 FD 计数');
      return;
    }

    final Context root = Context.root();
    addTearDown(root.dispose);

    final List<File> files = <File>[
      for (int i = 0; i < 3; i++)
        File('${dir.path}/f$i')..writeAsStringSync('x'),
    ];

    final Context plugin = root.plugin('io', (Context c) {
      for (final File file in files) {
        c.track(openRealFile(file));
      }
    });

    expect(await openFdsUnder(dir.path), 3, reason: '打开 3 个文件句柄');

    plugin.dispose();

    expect(await openFdsUnder(dir.path), 0, reason: '卸载后 3 个句柄全部释放');
  });
}

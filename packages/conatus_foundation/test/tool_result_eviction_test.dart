import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('超阈值落盘、预览含路径，clear 删除文件', () async {
    final Directory dir = Directory.systemTemp.createTempSync('conatus-evict-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final ToolResultEviction eviction = ToolResultEviction(
      fs: LocalFileSystem(cwd: dir.path),
      threshold: 10,
      previewChars: 2,
      dir: '${dir.path}/spill',
    );
    const String body = 'abcdefghijklmnop';
    final String? preview = await eviction.evict(body);

    expect(preview, isNotNull);
    expect(preview, contains('省略'));
    expect(File(eviction.spilledPaths.single).readAsStringSync(), body);

    await eviction.clear();
    expect(eviction.spilledPaths, isEmpty);
  });
}

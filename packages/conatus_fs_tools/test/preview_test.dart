import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late LocalFileSystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-preview-');
    fs = LocalFileSystem(cwd: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('apply_patch 返回 patch 文本；未知工具 / 参数类型不符返回 null', () async {
    const String patch = '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n';
    expect(
      await buildApprovalPreview(
          fs, 'apply_patch', <String, Object?>{'patch': patch}),
      patch,
    );
    expect(await buildApprovalPreview(fs, 'unknown_tool', <String, Object?>{}),
        isNull);
    expect(
      await buildApprovalPreview(
          fs, 'apply_patch', <String, Object?>{'patch': 42}),
      isNull,
    );
  });

  test('write 预览：缺 fs / 新文件 / 无改动 / 已有文件', () async {
    final Map<String, Object?> args = <String, Object?>{
      'path': 'a.txt',
      'content': 'hi\n',
    };
    expect(await buildApprovalPreview(null, 'write', args), isNull);

    final String? created = await buildApprovalPreview(fs, 'write', args);
    expect(created, contains('--- a/a.txt'));
    expect(created, contains('+hi'));

    File('${dir.path}/a.txt').writeAsStringSync('hi\n');
    expect(await buildApprovalPreview(fs, 'write', args), '（无实际改动）');

    final String? changed = await buildApprovalPreview(
      fs,
      'write',
      <String, Object?>{'path': 'a.txt', 'content': 'new\n'},
    );
    expect(changed, contains('-hi'));
    expect(changed, contains('+new'));
  });

  test('edit 预览：替换后 diff；old_string 不存在返回 null；超长截断', () async {
    File('${dir.path}/b.txt').writeAsStringSync('hello world\n');
    final String? edited = await buildApprovalPreview(
      fs,
      'edit',
      <String, Object?>{
        'path': 'b.txt',
        'old_string': 'world',
        'new_string': 'dart',
      },
    );
    expect(edited, contains('-hello world'));
    expect(edited, contains('+hello dart'));

    expect(
      await buildApprovalPreview(
        fs,
        'edit',
        <String, Object?>{
          'path': 'b.txt',
          'old_string': 'zzz',
          'new_string': 'y'
        },
      ),
      isNull,
    );

    final String long = '${'a' * (kPreviewMaxChars + 10)}\n';
    final String? truncated = await buildApprovalPreview(
      fs,
      'apply_patch',
      <String, Object?>{'patch': long},
    );
    expect(truncated, endsWith('…（截断）'));
    expect(truncated, hasLength(kPreviewMaxChars + 6));
  });
}

/// @ 文件引用展开。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late LocalFileSystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('at-ref-test-');
    fs = LocalFileSystem(cwd: dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void write(String name, String content) =>
      File('${dir.path}/$name').writeAsStringSync(content);

  test('可读文件展开为 <file> 块', () async {
    write('a.dart', 'void main() {}');
    final String out = await expandAtRefs('@a.dart 看看这段', fs: fs);
    expect(out, '<file path="a.dart">\nvoid main() {}\n</file> 看看这段');
  });

  test('不存在的文件保留原文并提示', () async {
    final String out = await expandAtRefs('@missing.dart 呢？', fs: fs);
    expect(out, '@missing.dart（文件不存在，未展开） 呢？');
  });

  test('超过大小上限不展开', () async {
    write('big.dart', 'x' * (kAtRefMaxBytes + 1));
    final String out = await expandAtRefs('@big.dart', fs: fs);
    expect(out, '@big.dart（超过 ${kAtRefMaxBytes ~/ 1024}KB，未展开）');
  });

  test('目录不是可引用文件', () async {
    Directory('${dir.path}/sub').createSync();
    final String out = await expandAtRefs('@sub 目录', fs: fs);
    expect(out, '@sub（文件不存在，未展开） 目录');
  });

  test('多个引用逐个展开', () async {
    write('a.dart', 'A');
    write('b.dart', 'B');
    final String out = await expandAtRefs('@a.dart + @b.dart', fs: fs);
    expect(out, '<file path="a.dart">\nA\n</file> + <file path="b.dart">\nB\n</file>');
  });

  test('超过引用数量上限时其余原样保留', () async {
    for (int i = 0; i < kAtRefMaxCount + 2; i++) {
      write('f$i.dart', '$i');
    }
    final String input = List<String>.generate(
        kAtRefMaxCount + 2, (int i) => '@f$i.dart').join(' ');
    final String out = await expandAtRefs(input, fs: fs);
    expect(out, contains('@f$kAtRefMaxCount.dart'));
    expect(out, contains('@f${kAtRefMaxCount + 1}.dart'));
  });

  test('fs 不可用时原样返回', () async {
    expect(await expandAtRefs('@a.dart'), '@a.dart');
  });
}

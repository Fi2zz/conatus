/// E-18(3)：检查点归档原子落盘——写一半崩溃不留半截归档。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

CheckpointManifest _manifest() =>
    const CheckpointManifest(kind: 'base', turn: 0);

void main() {
  test('写入过程不触碰目标文件；close 后原子替换且无临时残留', () async {
    final Directory dir = Directory.systemTemp.createTempSync(
      'conatus-archive-atom',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final File target = File('${dir.path}${Platform.pathSeparator}archive');
    target.writeAsBytesSync(utf8.encode('OLD'));

    final CheckpointArchiveWriter writer =
        CheckpointArchiveWriter(target, _manifest());
    writer.addBytes('a.txt', utf8.encode('hello'));
    // close 前目标保持原样（尚未 rename）——旧实现直接 openWrite 目标会立刻截断。
    expect(target.readAsBytesSync(), utf8.encode('OLD'));

    await writer.close();

    expect(target.readAsBytesSync(), isNot(equals(utf8.encode('OLD'))));
    expect(
      File('${target.path}$kCheckpointArchiveTempSuffix').existsSync(),
      isFalse,
    );
  });
}

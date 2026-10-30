/// 内容哈希旁挂（工作区内容只读一遍）与索引重建跳过旁挂文件。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('checkpoint-hashes');

CheckpointManifest _manifest() =>
    const CheckpointManifest(kind: 'base', turn: 0);

void main() {
  late Directory dir;

  setUp(() {
    dir = _tempDir();
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('addFile 顺带算出的 sha256 与独立计算一致（多 chunk 文件）', () async {
    final Uint8List big = Uint8List(3 << 20); // > 64KB chunk，跨多块
    for (int i = 0; i < big.length; i++) {
      big[i] = (i * 17 + 3) & 0xff;
    }
    final File spill = await _spill(dir, 'big.bin', big);
    final List<int> small = utf8.encode('你好，nava');

    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      File('${dir.path}/h.cp'),
      _manifest(),
      collectHashes: true,
    );
    await writer.addFile('big.bin', spill);
    writer.addBytes('small.txt', small);
    await writer.close();

    expect(
      writer.hashes['big.bin'],
      sha256.convert(big).toString(),
      reason: '流式分块哈希应与整块一致',
    );
    expect(writer.hashes['small.txt'], sha256.convert(small).toString());
  });

  test('未开 collectHashes 时不收集（默认路径零额外开销）', () async {
    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      File('${dir.path}/n.cp'),
      _manifest(),
    );
    writer.addBytes('a.txt', utf8.encode('x'));
    await writer.close();
    expect(writer.hashes, isEmpty);
  });

  test('旁挂文件往返；缺失/损坏返回 null（调用方退化为保守判定）', () {
    final File archive = File('${dir.path}/r.cp')..writeAsStringSync('x');
    expect(readCheckpointHashes(archive), isNull, reason: '旁挂不存在');

    writeCheckpointHashes(archive, <String, String>{'a.txt': 'abc'});
    expect(readCheckpointHashes(archive), <String, String>{'a.txt': 'abc'});

    checkpointHashesFile(archive).writeAsStringSync('not gzip');
    expect(readCheckpointHashes(archive), isNull, reason: '损坏应降级');

    // 空哈希不写文件（先删掉上一步写入的旁挂，否则断言的是残留文件）。
    deleteCheckpointHashes(archive);
    writeCheckpointHashes(archive, <String, String>{});
    expect(
      checkpointHashesFile(archive).existsSync(),
      isFalse,
      reason: '空哈希不写文件',
    );

    // 删除幂等。
    deleteCheckpointHashes(archive);
  });

  test('索引重建跳过旁挂文件（不把 .hashes 当归档读头）', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'a.txt', 'AAAA');
    await store.snapshot('s1', 0);
    // 旁挂文件确实与归档并存于同一目录。
    expect(
      checkpointHashesFile(store.archiveFile('s1', 0)).existsSync(),
      isTrue,
    );
    // 索引丢失后重建必须只认归档（否则会把 gzip JSON 当归档读头而抛错）。
    store.indexFile('s1').deleteSync();
    expect(store.list('s1').map((CheckpointInfo i) => i.turn), <int>[0]);
  });
}

Future<File> _spill(Directory dir, String name, List<int> bytes) async {
  final File file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

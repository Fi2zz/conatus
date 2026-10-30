/// 归档层流式化：写入器 / 头部清单读取 / 条目流，与旧整包读写格式互通。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('checkpoint-streaming');

CheckpointManifest _manifest() =>
    const CheckpointManifest(kind: 'base', turn: 0);

void main() {
  group('CheckpointArchiveWriter / 读取互通', () {
    late Directory dir;

    setUp(() {
      dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('流式写入可被旧整包读取原样还原（含 4MB 多 chunk 文件）', () async {
      final File target = File('${dir.path}/a.cp');
      final Uint8List big = Uint8List(4 << 20);
      // 造可压缩度不一的内容，避免只测到全零捷径。
      for (int i = 0; i < big.length; i++) {
        big[i] = (i * 31 + 7) & 0xff;
      }
      final List<int> small = utf8.encode('你好，nava');

      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        _manifest(),
      );
      writer.addBytes('big.bin', big);
      await writer.addFile('small.txt', await _spill(dir, 'small.txt', small));
      await writer.close();

      final (CheckpointManifest _, List<CheckpointArchiveEntry> entries) =
          readCheckpointArchive(target);
      expect(entries.length, 2);
      expect(entries[0].$1, 'big.bin');
      expect(Uint8List.fromList(entries[0].$2), big);
      expect(entries[1].$1, 'small.txt');
      expect(entries[1].$2, small);
    });

    test('readCheckpointManifest 与整包读取的清单一致', () async {
      final File target = File('${dir.path}/b.cp');
      const CheckpointManifest manifest = CheckpointManifest(
        kind: 'delta',
        turn: 3,
        lastEventId: 'evt-9',
        changed: <String>['x.dart'],
        deleted: <String>['y.dart'],
      );
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        manifest,
      );
      writer.addBytes('x.dart', utf8.encode('void main() {}'));
      await writer.close();

      final CheckpointManifest headOnly = await readCheckpointManifest(target);
      expect(headOnly.kind, 'delta');
      expect(headOnly.turn, 3);
      expect(headOnly.lastEventId, 'evt-9');
      expect(headOnly.changed, <String>['x.dart']);
      expect(headOnly.deleted, <String>['y.dart']);
    });

    test('readCheckpointEntries 条目与内容字节和整包读取一致', () async {
      final File target = File('${dir.path}/c.cp');
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        _manifest(),
      );
      for (int i = 0; i < 20; i++) {
        writer.addBytes(
          'f${i.toString().padLeft(2, '0')}.txt',
          utf8.encode('content-$i-${'x' * 500}'),
        );
      }
      await writer.close();

      final List<CheckpointArchiveEntry> streamed = await readCheckpointEntries(
        target,
      ).toList();
      final (CheckpointManifest _, List<CheckpointArchiveEntry> whole) =
          readCheckpointArchive(target);

      expect(streamed.length, whole.length);
      for (int i = 0; i < whole.length; i++) {
        expect(streamed[i].$1, whole[i].$1);
        expect(streamed[i].$2, whole[i].$2);
      }
    });
  });

  group('二进制内容不影响读头', () {
    late Directory dir;

    setUp(() {
      dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('条目含非法 UTF-8 字节时 readCheckpointManifest 仍能读头', () async {
      final File target = File('${dir.path}/bin.cp');
      final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
        target,
        _manifest(),
      );
      // 0xFF 0xFE 不是合法 UTF-8：图片 / 编译产物 / 压缩包都会命中。
      writer.addBytes('logo.png', <int>[0x89, 0x50, 0x4e, 0xff, 0xfe, 0x00]);
      writer.addBytes('blob.bin', List<int>.filled(200, 0xc3)); // 截断多字节序列
      await writer.close();

      final CheckpointManifest head = await readCheckpointManifest(target);
      expect(head.kind, 'base');
      // 条目流同样不受影响（只对路径做 UTF-8 解码，内容按原字节还原）。
      final List<CheckpointArchiveEntry> entries = await readCheckpointEntries(
        target,
      ).toList();
      expect(entries.map((CheckpointArchiveEntry e) => e.$1), <String>[
        'logo.png',
        'blob.bin',
      ]);
      expect(entries[0].$2, <int>[0x89, 0x50, 0x4e, 0xff, 0xfe, 0x00]);
    });

    test('缺清单头（无换行的损坏归档）报 bad-archive', () async {
      final File broken = File('${dir.path}/broken.cp')
        ..writeAsBytesSync(gzip.encode(utf8.encode('{"kind":"base"}')));
      await expectLater(
        readCheckpointManifest(broken),
        throwsA(
          isA<CheckpointException>().having(
            (CheckpointException e) => e.code,
            'code',
            'bad-archive',
          ),
        ),
      );
    });
  });
}

Future<File> _spill(Directory dir, String name, List<int> bytes) async {
  final File file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

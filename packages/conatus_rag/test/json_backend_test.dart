import 'dart:io';

import 'package:conatus_rag/conatus_rag.dart';
import 'package:test/test.dart';

import 'helpers/fixtures.dart';

Future<Directory> _tempDir() async {
  final Directory dir = await Directory.systemTemp.createTemp('rag');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('JSON 后端跨实例往返，原子写不留临时文件', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/index.json');
    final JsonRagBackend first = JsonRagBackend(file: file);
    await first.init(const RagSnapshotMeta(
        embeddingModel: 'e', dimension: 2, indexVersion: 1));
    await first.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    await first.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));

    final JsonRagBackend second = JsonRagBackend(file: file);
    expect(await second.count(), 1);
    expect((await second.cursorOf('s0'))!.lastSeq, 0);
    expect(
        file.parent
            .listSync()
            .where((FileSystemEntity e) => e.path.endsWith('.tmp')),
        isEmpty);
  });

  test('损坏文件抛 rag_backend_broken 而不是静默清空', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/bad.json')..writeAsStringSync('{oops');
    await expectLater(
        JsonRagBackend(file: file).count(),
        throwsA(isA<RagException>()
            .having((RagException e) => e.code, 'code', 'rag_backend_broken')));
  });

  test('结构或字段类型不符同样视为损坏', () async {
    final Directory dir = await _tempDir();
    final File array = File('${dir.path}/array.json')..writeAsStringSync('[]');
    final File wrongType = File('${dir.path}/type.json')
      ..writeAsStringSync(
          '{"meta":null,"chunks":"x","vectors":[],"cursors":[]}');
    for (final File file in <File>[array, wrongType]) {
      await expectLater(
          JsonRagBackend(file: file).count(),
          throwsA(isA<RagException>().having(
              (RagException e) => e.code, 'code', 'rag_backend_broken')));
    }
  });

  test('损坏文件上 clear 可恢复，其余方法仍 fail closed', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/bad.json')..writeAsStringSync('{oops');
    final JsonRagBackend backend = JsonRagBackend(file: file);
    await expectLater(backend.count(), throwsA(isA<RagException>()));
    await expectLater(
        backend.upsert(<RagChunk>[
          chunk('a', 't1', {'tenant:t1'}, 0)
        ], <List<double>>[
          <double>[1, 0]
        ]),
        throwsA(isA<RagException>()));

    await backend.clear();
    expect(await backend.count(), 0);
    await backend.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    expect(await backend.count(), 1);
    expect(await JsonRagBackend(file: file).count(), 1);
  });

  test('文件不存在时视为空索引，读取不创建文件', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/missing.json');
    final JsonRagBackend backend = JsonRagBackend(file: file);
    expect(await backend.count(), 0);
    expect(await backend.meta(), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('删除与清空的结果跨实例持久化', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/index.json');
    final JsonRagBackend first = JsonRagBackend(file: file);
    await first.init(const RagSnapshotMeta(
        embeddingModel: 'e', dimension: 2, indexVersion: 1));
    await first.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0),
      chunk('b', 't1', {'tenant:t1'}, 1),
    ], <List<double>>[
      <double>[1, 0],
      <double>[0, 1],
    ]);
    await first.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));
    await first.delete(const RagFilter(tenantId: 't1', sourceIds: {'s0'}));

    final JsonRagBackend reopened = JsonRagBackend(file: file);
    expect(await reopened.count(), 1);
    expect(await reopened.cursorOf('s0'), isNull);

    await reopened.clear();
    final JsonRagBackend cleared = JsonRagBackend(file: file);
    expect(await cleared.count(), 0);
    expect(await cleared.meta(), isNull);
  });

  test('跨实例的 init 仍校验元信息是否一致', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/index.json');
    await JsonRagBackend(file: file).init(const RagSnapshotMeta(
        embeddingModel: 'e', dimension: 2, indexVersion: 1));
    await expectLater(
        JsonRagBackend(file: file).init(const RagSnapshotMeta(
            embeddingModel: 'other', dimension: 2, indexVersion: 1)),
        throwsA(isA<RagException>()
            .having((RagException e) => e.code, 'code', 'rag_index_stale')));
  });

  test('遗忘集合跨实例持久化，clear 清空遗忘', () async {
    final Directory dir = await _tempDir();
    final File file = File('${dir.path}/index.json');
    final JsonRagBackend first = JsonRagBackend(file: file);
    await first.init(const RagSnapshotMeta(
        embeddingModel: 'e', dimension: 2, indexVersion: 1));
    await first.upsert(<RagChunk>[
      chunk('a', 't1', {'tenant:t1'}, 0)
    ], <List<double>>[
      <double>[1, 0]
    ]);
    await first.saveCursor(
        const RagCursor(tenantId: 't1', sourceId: 's0', lastSeq: 0));
    await first.delete(const RagFilter(tenantId: 't1', sourceIds: {'s0'}));

    final JsonRagBackend reopened = JsonRagBackend(file: file);
    expect(await reopened.sourceForgotten('s0'), isTrue);
    expect(await reopened.forgottenSources(), contains('s0'));

    await reopened.clear();
    final JsonRagBackend cleared = JsonRagBackend(file: file);
    expect(await cleared.sourceForgotten('s0'), isFalse);
    expect(await cleared.forgottenSources(), isEmpty);
  });
}

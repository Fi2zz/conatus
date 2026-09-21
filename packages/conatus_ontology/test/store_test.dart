import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart' hide MemoryStore;
import 'package:conatus_ontology/src/ontology/layer.dart';
import 'package:conatus_ontology/src/ontology/node.dart';
import 'package:conatus_ontology/src/ontology/relation.dart';
import 'package:conatus_ontology/src/ontology/schema.dart';
import 'package:conatus_ontology/src/store/database_store.dart';
import 'package:conatus_ontology/src/store/memory_store.dart';
import 'package:test/test.dart';

OntologyLayer _layer(String version) => OntologyLayer(
      version: version,
      nodes: <OntologyNode>[
        Term(
            id: 't$version',
            createdAt: DateTime.utc(2026),
            name: '收入',
            definition: 'd'),
      ],
      relations: const <SemanticRelation>[],
      references: const <StructuralReference>[],
      schema: OntologySchema.defaults(),
      createdAt: DateTime.utc(2026),
    );

void main() {
  group('MemoryStore', () {
    test('save / find / remove / all', () async {
      final MemoryStore store = MemoryStore();
      await store.load();
      await store.save(_layer('v0'));
      await store.save(_layer('v1'));

      expect(store.all, hasLength(2));
      expect(store.find('v1')!.nodes, hasLength(1));
      expect(store.find('nope'), isNull);
      expect(await store.remove('v1'), isTrue);
      expect(await store.remove('v1'), isFalse);
      expect(store.all, hasLength(1));
    });
  });

  group('DatabaseStore', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ontology-store-test');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('带 Database 时持久化往返', () async {
      final Database database = Database()
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final DatabaseStore store = DatabaseStore(database: database);
      await store.load();
      await store.save(_layer('v0'));
      await store.save(_layer('v1'));

      final DatabaseStore restored = DatabaseStore(database: database);
      await restored.load();
      expect(restored.all, hasLength(2));
      expect(restored.find('v0'), isNotNull);
      expect(restored.find('v1'), isNotNull);

      expect(await restored.remove('v0'), isTrue);
      final DatabaseStore finalStore = DatabaseStore(database: database);
      await finalStore.load();
      expect(finalStore.all, hasLength(1));
    });

    test('无 Database 时纯内存', () async {
      final DatabaseStore store = DatabaseStore();
      await store.load();
      await store.save(_layer('v0'));
      expect(store.find('v0'), isNotNull);
    });

    test('损坏记录跳过', () async {
      final Database database = Database()
        ..register('json', JsonDatabaseBackend(dir: dir.path));
      final DatabaseUnit unit = await database.open('ontology');
      await unit.put('layers', <Object?>[
        <String, Object?>{'broken': true},
        _layer('ok').toJson(),
      ]);

      final DatabaseStore store = DatabaseStore(database: database);
      await store.load();
      expect(store.all, hasLength(1));
      expect(store.find('ok'), isNotNull);
    });
  });
}

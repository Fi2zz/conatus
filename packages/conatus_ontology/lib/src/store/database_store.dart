/// 基于 conatus_foundation Database 的本体层存档。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../ontology/layer.dart';
import 'store.dart';

/// 版本体层存档：无 [Database] 时纯内存，提供时每次 [save] 同步落盘。
class DatabaseStore implements OntologyStore {
  DatabaseStore({Database? database, this.unit = 'ontology'})
      : _database = database;

  final Database? _database;
  final String unit;

  /// 存档记录键。
  static const String key = 'layers';

  final List<OntologyLayer> _layers = <OntologyLayer>[];

  @override
  List<OntologyLayer> get all => List<OntologyLayer>.unmodifiable(_layers);

  @override
  Future<void> load() async {
    final Database? database = _database;
    if (database == null) return;
    final Object? raw = (await _open(database)).get(key);
    if (raw is! List) return;
    for (final Object? item in raw) {
      if (item is! Map) continue;
      try {
        _layers.add(OntologyLayer.fromJson(Map<String, Object?>.from(item)));
      } catch (_) {
        // 损坏的存档记录跳过。
      }
    }
  }

  @override
  Future<void> save(OntologyLayer layer) async {
    _layers.add(layer);
    final Database? database = _database;
    if (database == null) return;
    await (await _open(database)).put(key, <Map<String, Object?>>[
      for (final OntologyLayer l in _layers) l.toJson(),
    ]);
  }

  @override
  OntologyLayer? find(String version) {
    for (final OntologyLayer layer in _layers) {
      if (layer.version == version) return layer;
    }
    return null;
  }

  @override
  Future<bool> remove(String version) async {
    final int before = _layers.length;
    _layers.removeWhere((OntologyLayer layer) => layer.version == version);
    if (_layers.length == before) return false;
    final Database? database = _database;
    if (database != null) {
      await (await _open(database)).put(key, <Map<String, Object?>>[
        for (final OntologyLayer l in _layers) l.toJson(),
      ]);
    }
    return true;
  }

  Future<DatabaseUnit> _open(Database database) async =>
      database.get(unit) ?? await database.open(unit);
}

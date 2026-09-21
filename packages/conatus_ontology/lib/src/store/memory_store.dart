/// 内存版本体层存档。
library;

import '../ontology/layer.dart';
import 'store.dart';

/// 纯内存存档（进程退出即丢失）。
class MemoryStore implements OntologyStore {
  final List<OntologyLayer> _layers = <OntologyLayer>[];

  @override
  List<OntologyLayer> get all => List<OntologyLayer>.unmodifiable(_layers);

  @override
  Future<void> load() async {}

  @override
  Future<void> save(OntologyLayer layer) async {
    _layers.add(layer);
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
    return _layers.length < before;
  }
}

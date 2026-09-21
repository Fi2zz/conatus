/// 本体层版本存档接口。
library;

import '../ontology/layer.dart';

/// 本体层存档：保存/读取版本化层，支持按版本查询与删除。
abstract class OntologyStore {
  /// 已存档的全部层（按保存顺序）。
  List<OntologyLayer> get all;

  /// 从持久化后端载入存档。
  Future<void> load();

  /// 存档一层。
  Future<void> save(OntologyLayer layer);

  /// 按版本号查找；不存在返回 `null`。
  OntologyLayer? find(String version);

  /// 删除一个版本；不存在返回 `false`。
  Future<bool> remove(String version);
}

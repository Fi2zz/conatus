/// prompt-evolver 的版本存档：内存为权威，可选 [Database] 持久化。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'prompt_variant.dart';

/// 提示词版本存档。
///
/// 无 [Database] 时纯内存（进程退出即丢失）；提供时每次 [save] 同步落盘，
/// [load] 从存档单元恢复历史版本。损坏的记录跳过，不影响其余版本。
class PromptStore {
  PromptStore({Database? database, this.unit = 'prompt_evolver'})
      : _database = database;

  /// 持久化 hub；缺省为 `null`（纯内存存档）。
  final Database? _database;

  /// 存档单元名。
  final String unit;

  /// 存档记录键。
  static const String key = 'variants';

  final List<PromptVariant> _history = <PromptVariant>[];

  /// 已存档的全部版本（按创建时间升序）。
  List<PromptVariant> get all => List<PromptVariant>.unmodifiable(_history);

  /// 从 [Database] 载入存档；无 database 时为空列表。
  Future<void> load() async {
    final Database? database = _database;
    if (database == null) return;
    final Object? raw = (await _open(database)).get(key);
    if (raw is! List) return;
    for (final Object? item in raw) {
      if (item is! Map) continue;
      try {
        _history.add(PromptVariant.fromJson(Map<String, Object?>.from(item)));
      } catch (_) {
        // 损坏的存档记录跳过。
      }
    }
  }

  /// 存档一个版本：先更新内存，再（有 database 时）整表落盘。
  Future<void> save(PromptVariant variant) async {
    _history.add(variant);
    final Database? database = _database;
    if (database == null) return;
    await (await _open(database)).put(key, <Map<String, Object?>>[
      for (final PromptVariant v in _history) v.toJson(),
    ]);
  }

  /// 按 id 查找版本；不存在返回 `null`。
  PromptVariant? find(String id) {
    for (final PromptVariant variant in _history) {
      if (variant.id == id) return variant;
    }
    return null;
  }

  Future<DatabaseUnit> _open(Database database) async =>
      database.get(unit) ?? await database.open(unit);
}

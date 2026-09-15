/// database 插件：KV 存储 hub + 具名后端注册 + 单元句柄。
///
/// 服务键 `'database'`。hub 本身不做 IO：后端（如 `database_json.dart` 的
/// [JsonDatabaseBackend]）拥有介质，`open(unit)` 从后端载入整表并返回一个
/// [DatabaseUnit] 句柄（同步读、异步写、变更广播）。多个后端可并排注册，
/// 由每次 `open` 的路由选择。
///
/// ```dart
/// final db = provideDatabase(app, defaultBackend: 'json');
/// provideDatabaseJson(app);
/// final unit = await db.open('profile');
/// await unit.put('name', '助手');
/// print(unit.get('name'));
/// ```
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'database_types.dart';
import 'database_unit.dart';

/// 存储 hub：后端注册表与已打开单元表。
class Database {
  Database({this.defaultBackend});

  /// 缺省后端名；`open` 未指定路由时使用。
  String? defaultBackend;

  final Map<String, DatabaseBackend> _backends = <String, DatabaseBackend>{};
  final Map<String, DatabaseUnit> _units = <String, DatabaseUnit>{};

  /// 已注册的后端名（按注册顺序）。
  List<String> get backendNames => _backends.keys.toList(growable: false);

  /// 已打开的单元名（按打开顺序）。
  List<String> get units => _units.keys.toList(growable: false);

  /// 已打开的单元数。
  int get length => _units.length;

  /// 注册一个具名后端。重名或空名抛 [DatabaseException]；返回撤销函数（幂等）。
  Disposer register(String name, DatabaseBackend backend) {
    if (name.isEmpty) {
      throw const DatabaseException('invalid-backend', '后端名不能为空');
    }
    if (_backends.containsKey(name)) {
      throw DatabaseException('duplicate-backend', '后端 "$name" 已注册');
    }
    _backends[name] = backend;
    bool removed = false;
    return () {
      if (removed) return;
      removed = true;
      if (identical(_backends[name], backend)) _backends.remove(name);
    };
  }

  /// 解析一个后端；未注册抛 [DatabaseException]。
  DatabaseBackend backend(String name) {
    final DatabaseBackend? found = _backends[name];
    if (found == null) {
      throw DatabaseException('backend-not-found', '后端 "$name" 未注册');
    }
    return found;
  }

  /// 打开一个单元：从路由后端载入整表并返回句柄。
  ///
  /// 已打开、空名或无法解析后端时抛 [DatabaseException]。
  Future<DatabaseUnit> open(String unit, {String? backend}) async {
    if (unit.isEmpty) {
      throw const DatabaseException('invalid-unit', '单元名不能为空');
    }
    if (_units.containsKey(unit)) {
      throw DatabaseException('already-open', '单元 "$unit" 已打开');
    }
    final DatabaseBackend resolved = _resolveBackend(backend);
    final Map<String, Object?> state =
        Map<String, Object?>.of(await resolved.load(unit));
    final DatabaseUnit handle = DatabaseUnit(
      name: unit,
      backend: resolved,
      state: state,
      onClose: (DatabaseUnit closed) => _units.remove(closed.name),
    );
    _units[unit] = handle;
    return handle;
  }

  /// 查找已打开的单元；未打开返回 `null`。
  DatabaseUnit? get(String unit) => _units[unit];

  /// 关闭某单元。返回是否确实关闭了一个。
  bool close(String unit) {
    final DatabaseUnit? handle = _units[unit];
    if (handle == null) return false;
    handle.close();
    return true;
  }

  /// 关闭全部单元。
  Future<void> closeAll() async {
    for (final DatabaseUnit handle in List<DatabaseUnit>.of(_units.values)) {
      handle.close();
    }
    _units.clear();
  }

  DatabaseBackend _resolveBackend(String? name) {
    final String? resolved = name ?? defaultBackend;
    if (resolved != null) return backend(resolved);
    if (_backends.length == 1) return _backends.values.first;
    throw const DatabaseException('no-backend', '未指定后端且注册的后端不唯一');
  }
}

/// 将 [Database] 作为 `'database'` 服务提供到上下文。
Database provideDatabase(
  Context ctx, {
  Database? database,
  String? defaultBackend,
}) {
  final Database hub = database ?? Database(defaultBackend: defaultBackend);
  ctx.provide('database', hub);
  ctx.onDispose(() => unawaited(hub.closeAll()));
  return hub;
}

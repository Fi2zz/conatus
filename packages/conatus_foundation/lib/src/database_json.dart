/// database-json 后端：每单元一个人类可读的 JSON 文件，整表原子发布。
///
/// 写入经临时文件 + rename 原子发布；载入时把非对象内容判为 `malformed-medium`。
/// 单元名必须是安全的文件名（不含路径分隔符）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'database.dart';
import 'database_types.dart';

/// 本地 JSON 文件后端。
class JsonDatabaseBackend implements DatabaseBackend {
  JsonDatabaseBackend({String? dir}) : dir = dir ?? _defaultDir();

  /// 单元文件所在目录。
  final String dir;

  @override
  Future<Map<String, Object?>> load(String unit) async {
    final File file = _file(unit);
    if (!file.existsSync()) return <String, Object?>{};
    final Object? json = jsonDecode(await file.readAsString());
    if (json is! Map<String, Object?>) {
      throw DatabaseException('malformed-medium', '单元 "$unit" 的文件不是 JSON 对象');
    }
    return Map<String, Object?>.of(json);
  }

  @override
  Future<void> save(String unit, Map<String, Object?> records) async {
    final File file = _file(unit);
    await file.parent.create(recursive: true);
    final String encoded = jsonEncode(records);
    final File temp =
        File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsString(encoded, flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      await file.writeAsString(encoded, flush: true);
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> deleteUnit(String unit) async {
    final File file = _file(unit);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> close() async {}

  File _file(String unit) {
    if (unit.isEmpty || unit.contains(RegExp(r'[/\\]'))) {
      throw DatabaseException('invalid-unit', '非法单元名 "$unit"');
    }
    return File('$dir${Platform.pathSeparator}$unit.json');
  }

  static String _defaultDir() =>
      '${Directory.current.path}${Platform.pathSeparator}.conatus'
      '${Platform.pathSeparator}database';
}

/// 将 [JsonDatabaseBackend] 注册到 hub 的 `'database'` 服务上。
///
/// [database] 缺省取上下文里已提供的 `'database'`；[name] 是后端注册名。
JsonDatabaseBackend provideDatabaseJson(
  Context ctx, {
  Database? database,
  String name = 'json',
  String? dir,
}) {
  final Database hub = database ?? ctx.require<Database>('database');
  final JsonDatabaseBackend backend = JsonDatabaseBackend(dir: dir);
  final Disposer off = hub.register(name, backend);
  ctx.onDispose(() {
    off();
    unawaited(backend.close());
  });
  return backend;
}

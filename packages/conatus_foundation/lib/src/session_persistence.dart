/// session-persistence 插件：会话日志的持久化端口与本地 JSONL 实现。
///
/// 端口只有四个动作（列举 / 载入 / 追加 / 删除），追加是 O(1) 的行写入，
/// 载入时逐行反序列化。更换为数据库或对象存储后端时，消费方代码不变。
library;

import 'dart:convert';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'session_types.dart';

/// 会话持久化端口。
abstract class SessionPersistence {
  /// 已持久化的会话 id。
  Future<List<String>> list();

  /// 载入某会话的全部事件；不存在时返回空列表。
  Future<List<SessionEvent>> load(String id);

  /// 追加一条事件（append-only）。
  Future<void> append(String id, SessionEvent event);

  /// 删除某会话的全部持久化数据。
  Future<void> remove(String id);
}

/// 本地 JSONL 实现：一会话一文件，每行一条事件的 JSON。
class JsonlSessionPersistence implements SessionPersistence {
  JsonlSessionPersistence({String? dir}) : dir = dir ?? _defaultDir();

  /// 会话文件所在目录。
  final String dir;

  File _file(String id) => File('$dir${Platform.pathSeparator}$id.jsonl');

  @override
  Future<List<String>> list() async {
    final Directory directory = Directory(dir);
    if (!directory.existsSync()) return const <String>[];
    final List<String> ids = <String>[];
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is! File) continue;
      final String name = entity.uri.pathSegments.last;
      if (name.endsWith('.jsonl')) {
        ids.add(name.substring(0, name.length - '.jsonl'.length));
      }
    }
    ids.sort();
    return ids;
  }

  @override
  Future<List<SessionEvent>> load(String id) async {
    final File file = _file(id);
    if (!file.existsSync()) return const <SessionEvent>[];
    final List<SessionEvent> events = <SessionEvent>[];
    for (final String line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      final Object? json = jsonDecode(line);
      if (json is Map<String, Object?>) events.add(SessionEvent.fromJson(json));
    }
    return events;
  }

  @override
  Future<void> append(String id, SessionEvent event) async {
    final File file = _file(id);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<void> remove(String id) async {
    final File file = _file(id);
    if (file.existsSync()) await file.delete();
  }

  static String _defaultDir() =>
      '${Directory.current.path}${Platform.pathSeparator}.conatus'
      '${Platform.pathSeparator}sessions';
}

/// 将 [SessionPersistence] 作为 `'sessionPersistence'` 服务提供到上下文。
SessionPersistence provideSessionPersistence(
  Context ctx, {
  SessionPersistence? persistence,
}) {
  final SessionPersistence resolved = persistence ?? JsonlSessionPersistence();
  ctx.provide('sessionPersistence', resolved);
  return resolved;
}

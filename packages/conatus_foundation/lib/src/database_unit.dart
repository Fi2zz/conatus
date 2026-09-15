/// database 插件的单元句柄：权威内存状态 + 写入链 + 变更广播。
///
/// 每次写入先经后端落盘，成功后才更新内存并广播 [DatabaseChange]，因此读到的
/// 内存状态永不领先于介质；后端写失败时内存保持不变，异常原样上抛。
library;

import 'package:conatus_core/conatus_core.dart';
import 'database_types.dart';

/// 一个已打开的存储单元。
class DatabaseUnit {
  DatabaseUnit({
    required this.name,
    required DatabaseBackend backend,
    required Map<String, Object?> state,
    required void Function(DatabaseUnit unit) onClose,
  })  : _backend = backend,
        _state = state,
        _onClose = onClose;

  /// 单元名。
  final String name;

  final DatabaseBackend _backend;
  final Map<String, Object?> _state;
  final void Function(DatabaseUnit unit) _onClose;
  final List<void Function(DatabaseChange)> _listeners =
      <void Function(DatabaseChange)>[];
  bool _closed = false;

  /// 是否已关闭。
  bool get closed => _closed;

  /// 记录条数。
  int get length => _state.length;

  /// 全部键（快照）。
  List<String> get keys => _state.keys.toList(growable: false);

  /// 某键是否存在（值可为 null）。
  bool has(String key) => _state.containsKey(key);

  /// 读取某键的值；不存在返回 `null`。
  Object? get(String key) => _state[key];

  /// 全部记录的只读快照。
  Map<String, Object?> entries() => Map<String, Object?>.unmodifiable(_state);

  /// 写入一条记录（新增或覆盖）。落盘成功后才更新内存并广播。
  Future<void> put(String key, Object? value) async {
    _ensureOpen();
    final Map<String, Object?> next = Map<String, Object?>.of(_state)
      ..[key] = value;
    await _backend.save(name, next);
    _state[key] = value;
    _emit(DatabaseChangeKind.put, key, value);
  }

  /// 删除一条记录。返回是否确实删除了（不存在则为 false，不落盘、不广播）。
  Future<bool> delete(String key) async {
    _ensureOpen();
    if (!_state.containsKey(key)) return false;
    final Map<String, Object?> next = Map<String, Object?>.of(_state)
      ..remove(key);
    await _backend.save(name, next);
    _state.remove(key);
    _emit(DatabaseChangeKind.deleted, key, null);
    return true;
  }

  /// 监听本单元后续变更。返回撤销函数（幂等）。
  Disposer onChange(void Function(DatabaseChange change) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// 关闭单元：拒绝后续写入并清空监听器。幂等。
  void close() {
    if (_closed) return;
    _closed = true;
    _listeners.clear();
    _onClose(this);
  }

  void _ensureOpen() {
    if (_closed) {
      throw DatabaseException('unit-closed', '单元 "$name" 已关闭');
    }
  }

  void _emit(DatabaseChangeKind kind, String key, Object? value) {
    final DatabaseChange change =
        DatabaseChange(unit: name, key: key, kind: kind, value: value);
    for (final void Function(DatabaseChange) listener
        in List<void Function(DatabaseChange)>.of(_listeners)) {
      listener(change);
    }
  }

  @override
  String toString() => 'DatabaseUnit($name, $length records)';
}

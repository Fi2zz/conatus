/// database 插件的端口与词汇：后端契约、变更事件与错误。
library;

/// 带稳定错误码的数据库异常。
class DatabaseException implements Exception {
  const DatabaseException(this.code, this.message);

  /// 机器可路由的错误码（如 `backend-not-found` / `already-open`）。
  final String code;

  /// 人可读的消息。
  final String message;

  @override
  String toString() => 'DatabaseException($code): $message';
}

/// 具名存储后端：拥有一个介质（如一棵文件树），按单元整表读写。
///
/// 一个后端服务多个单元；[load] / [save] / [deleteUnit] 的每次调用都是原子的，
/// 返回即已落盘。后端不负责并发排序，由调用方（DatabaseUnit 的写入链）保证。
abstract class DatabaseBackend {
  /// 载入某单元的整表；单元不存在时返回空表。
  Future<Map<String, Object?>> load(String unit);

  /// 覆盖保存某单元的整表。
  Future<void> save(String unit, Map<String, Object?> records);

  /// 删除某单元的全部数据。
  Future<void> deleteUnit(String unit);

  /// 关闭后端，释放介质。幂等。
  Future<void> close();
}

/// 一次单元变更的类型。
enum DatabaseChangeKind { put, deleted }

/// 一次已落盘的单元变更：在持久化成功且内存更新之后广播。
class DatabaseChange {
  const DatabaseChange({
    required this.unit,
    required this.key,
    required this.kind,
    this.value,
  });

  /// 所属单元名。
  final String unit;

  /// 记录键。
  final String key;

  /// 变更类型。
  final DatabaseChangeKind kind;

  /// `put` 时的新值；`deleted` 时为 null。
  final Object? value;

  @override
  String toString() => 'DatabaseChange(${kind.name}, $unit/$key)';
}

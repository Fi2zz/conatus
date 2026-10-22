/// CCR（Compress-Cache-Retrieve）存储契约。
library;

/// 一条 CCR 条目的元数据。
class CcrEntry {
  const CcrEntry({
    required this.id,
    required this.chars,
    required this.createdAt,
    required this.lastAccess,
    required this.hits,
  });

  /// 身份。
  final String id;

  /// 原文字符数。
  final int chars;

  /// 首次写入时间。
  final DateTime createdAt;

  /// 最近访问时间。
  final DateTime lastAccess;

  /// 命中次数。
  final int hits;
}

/// 原文存储。
abstract class CcrStore {
  /// 存入原文，返回身份。
  Future<String> put(String content);

  /// 按身份取回原文；未命中或已过期返回 null。
  Future<String?> get(String id);

  /// 查询元数据，不刷新访问时间。
  Future<CcrEntry?> stat(String id);

  /// 删除一条；幂等。
  Future<void> remove(String id);

  /// 清空；幂等。
  Future<void> clear();

  /// 累计命中次数。
  int get hits;

  /// 当前条目数。
  int get length;
}

/// cron 持久化能力缝：任务快照与运行历史的读写端口。
///
/// 与 [FileSystem] / [ShellExecutor] 同构：本包只依赖这个抽象，本地 JSON 文件
/// 实现见 `JsonCronStorage`，宿主可以用任意后端（数据库、远程 KV、内存）接入。
/// 读取约定宽容降级（缺失视为空、损坏告警后视为空），写入失败不得抛出。
library;

/// 启动时从存储恢复的运行戳。
class CronRunStamp {
  /// 构造一组运行戳。
  const CronRunStamp({this.lastRunAt, this.firedAt});

  /// 最近一次成功交付的时刻。
  final DateTime? lastRunAt;

  /// at 任务已消费的时刻。
  final DateTime? firedAt;
}

/// 任务存储的快照：动态任务原文 + 运行戳 + 启停覆盖。
class CronStorageSnapshot {
  /// 构造一份快照。
  const CronStorageSnapshot({
    this.dynamicTasks = const <Map<String, Object?>>[],
    this.runStamps = const <String, CronRunStamp>{},
    this.overrides = const <String, bool>{},
  });

  /// 持久化的动态任务原文（未校验，交给服务入口校验）。
  final List<Map<String, Object?>> dynamicTasks;

  /// 任务 id → 运行戳。
  final Map<String, CronRunStamp> runStamps;

  /// 任务 id → 启停覆盖。
  final Map<String, bool> overrides;
}

/// cron 任务与运行历史的存储端口。
abstract class CronStorage {
  /// 加载任务快照；缺失或损坏实现应降级为空快照并告警。
  CronStorageSnapshot loadTasks();

  /// 保存任务快照；[tasks] 是显式字段表（内部缓存永不落盘）。
  void saveTasks({
    required List<Map<String, Object?>> tasks,
    required Map<String, CronRunStamp> runStamps,
    required Map<String, bool> overrides,
  });

  /// 加载运行历史（旧记录在前，原始 JSON 对象）；撕裂行由实现跳过。
  List<Map<String, Object?>> loadHistory();

  /// 完整重写运行历史。
  void saveHistory(List<Map<String, Object?>> records);
}

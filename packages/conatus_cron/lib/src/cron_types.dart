/// cron 插件的数据模型：常量、任务内部态与模型可见视图。
///
/// [CronTask] 是可变的内部记录（运行戳、启停覆盖、cron 缓存），只有显式字段
/// 进入持久文件；[CronTaskView] 是稳定的对外形状（工具结果），日期一律以
/// UTC ISO 串表示。运行记录 [CronRunRecord] 见 `cron_history.dart`。
library;

import 'cron_parse.dart';

/// 固定间隔任务的最小间隔（秒）。
const int kCronMinEverySeconds = 10;

/// 内存与文件两侧的执行历史上限。
const int kCronMaxHistory = 500;

/// 运行记录摘要的最大长度（字符）。
const int kCronExcerptLength = 300;

/// 任务存储文件的协议版本。
const int kCronStorageVersion = 1;

/// 任务 id 形状：字母或数字开头，随后是字母、数字、`-`、`_`，最长 64 字符。
final RegExp kCronTaskIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');

/// daily 规则形状：本地 24 小时制的 `HH:MM`。
final RegExp kCronDailyPattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// 把瞬时格式化为 UTC ISO 串；null 原样返回。
String? formatCronInstant(DateTime? instant) =>
    instant?.toUtc().toIso8601String();

/// 任务规则种类（每个任务四选一）。
enum CronRuleKind {
  /// 一次性 ISO 8601 时刻。
  at('at'),

  /// 固定间隔秒数。
  every('every'),

  /// 每天本地 `HH:MM`。
  daily('daily'),

  /// 标准 5 段 cron 表达式。
  cron('cron');

  const CronRuleKind(this.wire);

  /// 持久与视图 JSON 中的判别值。
  final String wire;
}

/// 任务来源：静态配置或运行时添加。
enum CronTaskOrigin {
  /// 宿主配置里声明的静态任务，运行时不可增删改。
  config('config'),

  /// 运行时添加并持久化的任务。
  dynamic('dynamic');

  const CronTaskOrigin(this.wire);

  /// 视图 JSON 中的判别值。
  final String wire;
}

/// 一条任务运行记录的稳定状态值（历史 JSONL 的 `status` 字段）。
abstract final class CronRunStatus {
  /// 已交付宿主（等待执行结果）。
  static const String delivered = 'delivered';

  /// 执行中（dsh-cron 事件流语义保留，本端口不主动置位）。
  static const String running = 'running';

  /// 执行完成。
  static const String completed = 'completed';

  /// 执行失败。
  static const String failed = 'failed';
}

/// 一个任务的内部可变记录。
///
/// 运行戳（[lastRunAt] / [firedAt]）、启停覆盖与 cron 缓存（[cronParsed] /
/// [cronNext]）只活在内存，持久化由服务按显式字段表完成。
class CronTask {
  /// 构造一条内部记录；字段取值已在入口校验。
  CronTask({
    required this.id,
    required this.prompt,
    this.at,
    this.every,
    this.daily,
    this.cron,
    this.sessionId,
    this.enabled = true,
    required this.origin,
  });

  /// 任务 id，配置与动态任务间全局唯一。
  final String id;

  /// 触发时交给模型执行的任务内容。
  String prompt;

  /// 一次性 ISO 8601 时刻原文。
  String? at;

  /// 固定间隔秒数（与 dsh-cron 一致，允许小数）。
  num? every;

  /// 每天本地时间 `HH:MM`。
  String? daily;

  /// 标准 5 段 cron 表达式原文。
  String? cron;

  /// 绑定的会话 id；null 表示交给宿主注入的投递端口决定目标。
  final String? sessionId;

  /// 声明的启停值（创建时归一为布尔）。
  bool enabled;

  /// 任务来源。
  final CronTaskOrigin origin;

  /// 运行时启停覆盖；与声明值一致时归 null。
  bool? enabledOverride;

  /// 最近一次成功交付的时刻。
  DateTime? lastRunAt;

  /// at 任务已消费的时刻（触发后不再触发）。
  DateTime? firedAt;

  /// [cron] 的解析缓存；不持久化，加载或编辑时重建。
  CronExpression? cronParsed;

  /// 缓存的下一个 cron 触发分钟；触发或编辑后失效重算。
  DateTime? cronNext;
}

/// 一条任务的模型可见视图。
class CronTaskView {
  /// 构造一条视图。
  const CronTaskView({
    required this.id,
    required this.prompt,
    required this.schedule,
    required this.enabled,
    required this.origin,
    this.sessionId,
    this.lastRunAt,
    this.firedAt,
    this.nextRunAt,
  });

  /// 任务 id。
  final String id;

  /// 任务内容。
  final String prompt;

  /// 排期规则（`at` / `everySeconds` / `daily` / `cron` 四选一）。
  final Map<String, Object?> schedule;

  /// 生效的启停值（覆盖优先于声明值）。
  final bool enabled;

  /// 任务来源。
  final CronTaskOrigin origin;

  /// 绑定的会话 id。
  final String? sessionId;

  /// 最近一次成功交付的时刻。
  final DateTime? lastRunAt;

  /// at 任务已消费的时刻。
  final DateTime? firedAt;

  /// 下一次触发时刻；无待触发返回 null。
  final DateTime? nextRunAt;

  /// 序列化为工具结果；键形状与 dsh-cron 的 taskView 一致。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'prompt': prompt,
        'schedule': schedule,
        'enabled': enabled,
        'origin': origin.wire,
        'sessionId': sessionId,
        'lastRunAt': formatCronInstant(lastRunAt),
        'firedAt': formatCronInstant(firedAt),
        'nextRunAt': formatCronInstant(nextRunAt),
      };
}

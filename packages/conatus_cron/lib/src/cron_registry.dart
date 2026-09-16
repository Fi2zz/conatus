/// cron 任务注册表：id 索引的任务表、启动装配与持久化编解码。
///
/// 启动顺序与 dsh-cron 一致：持久化动态任务 → 配置静态任务 → 运行戳 →
/// 启停覆盖。config 任务登记后不可增删改；保存只写显式字段表，内部缓存
/// （cronParsed / cronNext）永不落盘。
library;

import 'dart:math';

import 'cron_errors.dart';
import 'cron_parse.dart';
import 'cron_rules.dart';
import 'cron_storage.dart';
import 'cron_types.dart';

/// id 索引的 cron 任务表（配置 + 动态）。
class CronTaskRegistry {
  /// 构造一个空注册表；[boot] 负责装配。
  CronTaskRegistry({
    required CronStorage storage,
    required DateTime Function() clock,
    void Function(String message)? onWarning,
  })  : _storage = storage,
        _clock = clock,
        _onWarning = onWarning;

  final CronStorage _storage;
  final DateTime Function() _clock;
  final void Function(String message)? _onWarning;
  final Map<String, CronTask> _tasks = <String, CronTask>{};
  final Random _random = Random();

  /// 全部任务内部记录。
  List<CronTask> get tasks => List<CronTask>.unmodifiable(_tasks.values);

  /// 按 id 找任务；不存在返回 null。
  CronTask? findTask(String id) => _tasks[id];

  /// 装配：加载持久化动态任务，叠加配置任务，再恢复运行戳与启停覆盖。
  void boot(List<Map<String, Object?>> configTasks) {
    final CronStorageSnapshot stored = _storage.loadTasks();
    for (final Map<String, Object?> raw in stored.dynamicTasks) {
      _tryAddRaw(raw, CronTaskOrigin.dynamic, 'stored task');
    }
    for (final Map<String, Object?> raw in configTasks) {
      _tryAddRaw(raw, CronTaskOrigin.config, 'config task');
    }
    for (final MapEntry<String, CronRunStamp> entry in stored.runStamps.entries) {
      _tasks[entry.key]
        ?..lastRunAt = entry.value.lastRunAt
        ..firedAt = entry.value.firedAt;
    }
    for (final MapEntry<String, bool> entry in stored.overrides.entries) {
      _tasks[entry.key]?.enabledOverride = entry.value;
    }
  }

  /// 登记一个动态任务（已归一化 id / 会话绑定），随后落盘。
  CronTask addDynamic(Map<String, Object?> input, {String? callerSessionId}) {
    final Map<String, Object?> normalized = Map<String, Object?>.of(input);
    if (_isBlank(normalized['id'])) normalized['id'] = allocateTaskId();
    if (_isBlank(normalized['sessionId'])) normalized['sessionId'] = callerSessionId;
    final CronTask task = addFromRaw(normalized, CronTaskOrigin.dynamic);
    save();
    return task;
  }

  /// 校验并登记一条任务原文；非法输入抛 [CronException]。
  CronTask addFromRaw(Map<String, Object?> raw, CronTaskOrigin origin) {
    final String? invalid = validateTaskInput((
      id: raw['id'],
      prompt: raw['prompt'],
      at: raw['at'],
      every: raw['every'],
      daily: raw['daily'],
      cron: raw['cron'],
    ));
    if (invalid != null) throw CronException(CronErrorCode.invalidTask, invalid);
    final String id = raw['id']! as String;
    if (_tasks.containsKey(id)) {
      throw CronException(CronErrorCode.duplicateId, 'task "$id" already exists');
    }
    final Object? sessionId = raw['sessionId'];
    final CronTask task = CronTask(
      id: id,
      prompt: raw['prompt']! as String,
      at: raw['at'] as String?,
      every: raw['every'] as num?,
      daily: raw['daily'] as String?,
      cron: raw['cron'] as String?,
      sessionId: sessionId is String && sessionId.isNotEmpty ? sessionId : null,
      enabled: raw['enabled'] != false,
      origin: origin,
    );
    task.cronParsed =
        task.cron == null ? null : parseCronExpression(task.cron!);
    _tasks[id] = task;
    return task;
  }

  /// 生成并占用一个唯一任务 id。
  String allocateTaskId() {
    final DateTime now = _clock();
    for (int attempt = 0; attempt < 100; attempt++) {
      final String id = generateTaskId(now, _random.nextInt(_kIdSuffixSpace));
      if (!_tasks.containsKey(id)) return id;
    }
    throw const CronException(
        CronErrorCode.invalidTask, 'could not allocate a task id');
  }

  /// 按 id 取任务；不存在抛 [CronErrorCode.notFound]。
  CronTask requireTask(String id) =>
      _tasks[id] ??
      (throw CronException(
          CronErrorCode.notFound, 'no task with id "$id"'));

  /// 按 id 取动态任务；配置任务抛 [CronErrorCode.configTask]。
  CronTask requireDynamicTask(String id, String verb) {
    final CronTask task = requireTask(id);
    if (task.origin != CronTaskOrigin.dynamic) {
      throw CronException(
          CronErrorCode.configTask, 'task "$id" comes from config; $verb it there');
    }
    return task;
  }

  /// 删除任务并落盘。
  void removeTask(String id) {
    _tasks.remove(id);
    save();
  }

  /// 按显式字段表落盘（动态任务 + 运行戳 + 启停覆盖）。
  void save() {
    _storage.saveTasks(
      tasks: <Map<String, Object?>>[
        for (final CronTask task in _tasks.values)
          if (task.origin == CronTaskOrigin.dynamic) _encodeTask(task),
      ],
      runStamps: <String, CronRunStamp>{
        for (final CronTask task in _tasks.values)
          if (task.lastRunAt != null || task.firedAt != null)
            task.id: CronRunStamp(lastRunAt: task.lastRunAt, firedAt: task.firedAt),
      },
      overrides: <String, bool>{
        for (final CronTask task in _tasks.values)
          if (task.enabledOverride != null) task.id: task.enabledOverride!,
      },
    );
  }

  void _tryAddRaw(
      Map<String, Object?> raw, CronTaskOrigin origin, String source) {
    try {
      addFromRaw(raw, origin);
    } on CronException catch (error) {
      _warn('cron: skipping $source: ${error.message}');
    }
  }

  void _warn(String message) {
    final void Function(String message)? handler = _onWarning;
    if (handler != null) handler(message);
  }
}

const int _kIdSuffixSpace = 36 * 36 * 36 * 36;

bool _isBlank(Object? value) =>
    value == null || (value is String && value.isEmpty);

Map<String, Object?> _encodeTask(CronTask task) => <String, Object?>{
      'id': task.id,
      'prompt': task.prompt,
      if (task.at != null) 'at': task.at,
      if (task.every != null) 'every': task.every,
      if (task.daily != null) 'daily': task.daily,
      if (task.cron != null) 'cron': task.cron,
      'sessionId': task.sessionId,
      'enabled': task.enabled,
    };

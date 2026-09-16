/// cron 服务：任务注册表与共享操作（工具与宿主共用）。
///
/// 服务本身不读墙钟语义之外的时钟：列表与视图用 [clock] 采样，调度推进由
/// [CronRuntime] 驱动。运行历史与任务表分别委托 [CronHistoryBook] 与
/// [CronTaskRegistry]，这里只保留共享操作与交付收尾。
library;

import 'package:conatus_core/conatus_core.dart';

import 'cron_book.dart';
import 'cron_errors.dart';
import 'cron_history.dart';
import 'cron_message.dart';
import 'cron_registry.dart';
import 'cron_rules.dart';
import 'cron_storage.dart';
import 'cron_types.dart';
import 'cron_update.dart';

/// cron 任务服务；服务键 `'cron'`。
class CronService {
  /// 构造并装配服务：注册表加载持久化状态并叠加 [configTasks]。
  CronService({
    required CronStorage storage,
    List<Map<String, Object?>> configTasks = const <Map<String, Object?>>[],
    DateTime Function()? clock,
    void Function(String message)? onWarning,
  })  : _clock = clock ?? DateTime.now,
        onWarning = onWarning,
        _registry = CronTaskRegistry(
          storage: storage,
          clock: clock ?? DateTime.now,
          onWarning: onWarning,
        ),
        _book = CronHistoryBook(storage: storage, clock: clock) {
    _startedAt = _clock();
    _registry.boot(configTasks);
  }

  /// 告警回调；[CronRuntime] 缺省复用同一通道。
  final void Function(String message)? onWarning;

  final DateTime Function() _clock;
  final CronTaskRegistry _registry;
  final CronHistoryBook _book;

  late final DateTime _startedAt;

  /// 服务装配时刻；every / cron 从未运行的任务以它为锚点。
  DateTime get startedAt => _startedAt;

  /// 全部任务内部记录（配置 + 动态）。
  List<CronTask> get tasks => _registry.tasks;

  /// 按 id 找任务；不存在返回 null（运行时投递用）。
  CronTask? findTask(String id) => _registry.findTask(id);

  /// 列出全部任务的模型可见视图。
  List<CronTaskView> listTasks() {
    final DateTime now = _clock();
    return <CronTaskView>[
      for (final CronTask task in _registry.tasks)
        buildTaskView(task, now, _startedAt),
    ];
  }

  /// 单个任务的模型可见视图（按当前墙钟）。
  CronTaskView taskView(CronTask task) =>
      buildTaskView(task, _clock(), _startedAt);

  /// 添加动态任务；[input] 形状同 dsh-cron（id 缺省生成，调用方会话绑定可覆盖）。
  CronTaskView addDynamicTask(Map<String, Object?> input,
      {String? callerSessionId}) {
    final CronTask task =
        _registry.addDynamic(input, callerSessionId: callerSessionId);
    return taskView(task);
  }

  /// 编辑动态任务；patch 含任何规则键则整组规则替换并重置运行戳。
  CronTaskView updateDynamicTask(String id, Map<String, Object?> patch) {
    final CronTask task = _registry.requireDynamicTask(id, 'edit');
    final String prompt = resolveCronPrompt(task.prompt, patch['prompt']);
    final bool touched = patchTouchesSchedule(patch);
    final Map<String, Object?> merged =
        mergeTaskRules(task, prompt, touched, patch);
    final String? invalid = validateTaskInput((
      id: id,
      prompt: prompt,
      at: merged['at'],
      every: merged['every'],
      daily: merged['daily'],
      cron: merged['cron'],
    ));
    if (invalid != null) throw CronException(CronErrorCode.invalidTask, invalid);
    applyTaskRules(task, merged);
    if (touched) resetCronRunState(task);
    _registry.save();
    return taskView(task);
  }

  /// 删除动态任务；配置任务抛 [CronErrorCode.configTask]。
  void removeDynamicTask(String id) {
    _registry.requireDynamicTask(id, 'remove');
    _registry.removeTask(id);
  }

  /// 设置启停覆盖；与声明值一致时归 null。
  CronTaskView setEnabled(String id, bool enabled) {
    final CronTask task = _registry.requireTask(id);
    task.enabledOverride = enabled == task.enabled ? null : enabled;
    _registry.save();
    return taskView(task);
  }

  /// 最新在前的运行历史；[limit] 非法退化为 100，封顶 [kCronMaxHistory]。
  List<CronRunRecord> listHistory({int? limit}) => _book.list(limit: limit);

  /// 推进一条运行记录到终态（completed / failed）；不存在返回 null。
  CronRunRecord? finishRun(String recordId,
          {required bool ok, String? excerpt}) =>
      _book.finish(recordId, ok: ok, excerpt: excerpt);

  /// 预分配运行记录标识（交付端口以 id 关联 finishRun）。
  CronRecordRef allocateRecordRef(DateTime now) => _book.allocateRef(now);

  /// 交付被拒时归还标识，保持 seq 连续。
  void releaseRecordRef(CronRecordRef ref) => _book.releaseRef(ref);

  /// 交付成功后收尾：更新运行戳、落盘、追加 delivered 记录。
  CronRunRecord commitFire({
    required CronRecordRef ref,
    required String taskId,
    required DateTime slot,
    required DateTime firedAt,
  }) {
    final CronTask? task = _registry.findTask(taskId);
    if (task != null) {
      task.lastRunAt = firedAt;
      if (task.at != null) task.firedAt = firedAt;
      task.cronNext = null;
    }
    _registry.save();
    return _book.append(CronRunRecord(
      id: ref.id,
      seq: ref.seq,
      taskId: taskId,
      prompt: task?.prompt ?? '',
      sessionId: task?.sessionId,
      scheduledFor: slot,
      firedAt: firedAt,
      status: CronRunStatus.delivered,
    ));
  }
}

/// 把 [CronService] 作为 `'cron'` 服务提供到上下文。
CronService provideCron(
  Context ctx, {
  required CronStorage storage,
  List<Map<String, Object?>> configTasks = const <Map<String, Object?>>[],
  DateTime Function()? clock,
  void Function(String message)? onWarning,
}) {
  final CronService service = CronService(
    storage: storage,
    configTasks: configTasks,
    clock: clock,
    onWarning: onWarning,
  );
  ctx.provide('cron', service);
  return service;
}

/// `ctx.cron`：当前上下文可见的 cron 服务。
extension CronContext on Context {
  /// 当前上下文提供的 cron 服务。
  CronService get cron => require<CronService>('cron');
}

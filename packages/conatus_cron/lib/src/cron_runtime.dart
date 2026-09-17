/// cron 运行时：定时扫描到期任务并交付给宿主注入的端口。
///
/// 启动 3 秒后首 tick，之后每 [CronRuntimeOptions.tickSeconds] 一次；每个任务
/// 独立隔离，单任务故障不影响其他。交付端口返回 false 或抛错时不消费时段，
/// 下个 tick 重试。所有定时器随 [dispose] 取消。
library;

import 'dart:async';

import 'cron.dart';
import 'cron_errors.dart';
import 'cron_history.dart';
import 'cron_message.dart';
import 'cron_notify.dart';
import 'cron_rules.dart';
import 'cron_types.dart';

/// 交付端口：把 [framing] 投递给 [recordId] 关联的运行，返回是否成功入队。
///
/// 返回 false 表示当前无法投递，运行时不会写运行戳，下个 tick 重试。
typedef CronDelivery = Future<bool> Function(String recordId, String framing);

/// 默认 tick 间隔（秒）。
const int kDefaultCronTickSeconds = 15;

/// 运行时选项；全部可选，缺省与 dsh-cron 配置一致。
class CronRuntimeOptions {
  /// 构造一组运行时选项。
  const CronRuntimeOptions({
    this.clock,
    this.notifier,
    this.tickSeconds = kDefaultCronTickSeconds,
    this.firstTickDelay = const Duration(seconds: 3),
    this.onWarning,
  });

  /// 墙钟；缺省 [DateTime.now]。
  final DateTime Function()? clock;

  /// 系统通知端口；缺省不通知。
  final CronNotifier? notifier;

  /// tick 间隔秒数；小于 1 时按 1 处理。
  final int tickSeconds;

  /// 启动后到首次 tick 的延迟（让装配完成）。
  final Duration firstTickDelay;

  /// 告警回调；缺省静默。
  final void Function(String message)? onWarning;
}

/// cron 定时运行时。
class CronRuntime {
  /// 构造并启动定时器；告警缺省走 [CronService.onWarning] 同一通道。
  CronRuntime({
    required this.service,
    required this.deliver,
    CronRuntimeOptions options = const CronRuntimeOptions(),
  })  : _clock = options.clock ?? DateTime.now,
        _notifier = options.notifier,
        _onWarning = options.onWarning ?? service.onWarning,
        _tickSeconds = options.tickSeconds < 1 ? 1 : options.tickSeconds {
    _arm(options.firstTickDelay);
  }

  /// cron 服务（任务与历史的权威状态）。
  final CronService service;

  /// 交付端口。
  final CronDelivery deliver;

  final DateTime Function() _clock;
  final CronNotifier? _notifier;
  final void Function(String message)? _onWarning;
  final int _tickSeconds;

  Timer? _firstTimer;
  Timer? _intervalTimer;
  bool _disposed = false;
  bool _ticking = false;

  /// 扫描一轮全部任务，交付到期者。
  Future<void> tick() async {
    final DateTime now = _clock();
    final DateTime startedAt = service.startedAt;
    for (final CronTask task in service.tasks) {
      if (_disposed) return;
      try {
        final DateTime? slot = dueSlot(task, now, startedAt);
        if (slot != null) await fire(task, slot);
      } on Object catch (error) {
        _warn('cron: tick failed for task "${task.id}": $error');
      }
    }
  }

  /// 立即交付一个任务（宿主手动触发）；投递不可用抛 [CronException]。
  Future<CronRunRecord> runTaskNow(String id) async {
    final CronTask? task = service.findTask(id);
    if (task == null) {
      throw CronException(CronErrorCode.notFound, 'no task with id "$id"');
    }
    final CronRunRecord? record = await fire(task, _clock());
    if (record == null) {
      throw const CronException(CronErrorCode.deliveryUnavailable,
          'no delivery target is available to receive the task');
    }
    return record;
  }

  /// 一轮执行完成后由装配方调用：推进记录状态并按结果发系统通知。
  void finishRun(String recordId, {required bool ok, String? excerpt}) {
    final CronRunRecord? record =
        service.finishRun(recordId, ok: ok, excerpt: excerpt);
    final CronNotifier? notifier = _notifier;
    if (record == null || notifier == null) return;
    final String title =
        ok ? '定时任务完成：${record.taskId}' : '定时任务失败：${record.taskId}';
    notifier(title, record.excerpt ?? record.prompt);
  }

  /// 停止定时器；进行中的交付自然结束，不再触发新 tick。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _firstTimer?.cancel();
    _firstTimer = null;
    _intervalTimer?.cancel();
    _intervalTimer = null;
  }

  /// 交付一个到期任务；成功才写运行戳与历史，拒绝/抛错返回 null。
  Future<CronRunRecord?> fire(CronTask task, DateTime slot) async {
    final DateTime firedAt = _clock();
    final String framing = renderTaskMessage(
      id: task.id,
      prompt: task.prompt,
      slot: slot,
      firedAt: firedAt,
    );
    final CronRecordRef ref = service.allocateRecordRef(firedAt);
    final bool accepted;
    try {
      accepted = await deliver(ref.id, framing);
    } on Object catch (error) {
      service.releaseRecordRef(ref);
      _warn('cron: deliver failed for task "${task.id}": $error');
      return null;
    }
    if (!accepted) {
      service.releaseRecordRef(ref);
      _warn('cron: task "${task.id}" is due but delivery was refused; '
          'will retry next tick');
      return null;
    }
    return service.commitFire(
        ref: ref, taskId: task.id, slot: slot, firedAt: firedAt);
  }

  void _arm(Duration firstDelay) {
    _firstTimer = Timer(firstDelay, () {
      _firstTimer = null;
      _runTick();
    });
    _intervalTimer =
        Timer.periodic(Duration(seconds: _tickSeconds), (_) => _runTick());
  }

  void _runTick() {
    if (_disposed || _ticking) return;
    _ticking = true;
    unawaited(_driveTick());
  }

  Future<void> _driveTick() async {
    try {
      await tick();
    } on Object catch (error) {
      _warn('cron: tick failed: $error');
    } finally {
      _ticking = false;
    }
  }

  void _warn(String message) {
    final void Function(String message)? handler = _onWarning;
    if (handler != null) handler(message);
  }
}

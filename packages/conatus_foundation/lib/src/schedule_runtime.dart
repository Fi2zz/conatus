/// 到期运行时：把到期提醒交付进会话，并安排下一次唤醒。
///
/// 一次推导的顺序固定：等待检查点 → 折叠 → 采样墙钟 → 交付 → 交付成功后才追加
/// dispatch → 再等待检查点。交付失败或拒绝投递时不写 dispatch，记录保持活动。
library;

import 'dart:async';
import 'dart:core';

import 'schedule.dart';
import 'schedule_delivery.dart';
import 'schedule_due.dart';
import 'schedule_errors.dart';
import 'schedule_types.dart';

/// 交付端口：把 framing 文本投递进会话，返回是否成功入队。
///
/// 返回 `false` 表示当前无法投递（例如会话正在回答），运行时不会写 dispatch，
/// 记录保持活动并在下一次触发时重试。
typedef ScheduleDelivery = Future<bool> Function(String text);

/// 单个定时器分段的上限；每次唤醒都会重新读取墙钟。
const Duration kMaxTimerSegment = Duration(milliseconds: 2147483647);

/// 一个会话的到期运行时。
class ScheduleRuntime {
  /// 构造一个运行时；[requestDrive] 触发首次推导。
  ScheduleRuntime({
    required this.schedule,
    required this.deliver,
    DateTime Function()? clock,
    void Function(String message)? onWarning,
  })  : _clock = clock ?? DateTime.now,
        _onWarning = onWarning;

  /// 提供提醒状态与持久化检查点的服务。
  final SessionSchedule schedule;

  /// 把 framing 文本投递进会话的端口。
  final ScheduleDelivery deliver;

  final DateTime Function() _clock;
  final void Function(String message)? _onWarning;

  Timer? _timer;
  Future<void>? _run;
  bool _requested = false;
  bool _disposed = false;
  bool _faulted = false;

  /// 请求一次推导：取消当前定时器，并合并到正在进行的推导上。
  void requestDrive() {
    if (_disposed || _faulted) return;
    _clearTimer();
    _requested = true;
    if (_run != null) return;
    final Future<void> run = _runRequested();
    _run = run;
    unawaited(run.then(
      (_) => _retire(run),
      onError: (Object error) {
        _warn('schedule: runtime failed: $error');
        _faulted = true;
        _retire(run);
      },
    ));
  }

  /// 释放运行时：停止新工作并取消定时器，但不删除任何持久记录。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _requested = false;
    _clearTimer();
    final Future<void>? run = _run;
    if (run == null) return;
    try {
      await run;
    } on Object {
      // 释放期间的失败只影响这一次推导，不影响已经落盘的记录。
    }
  }

  Future<void> _runRequested() async {
    while (_requested && !_disposed && !_faulted) {
      _requested = false;
      await _driveOnce();
    }
  }

  void _retire(Future<void> run) {
    if (!identical(_run, run)) return;
    _run = null;
    if (_requested && !_disposed && !_faulted) requestDrive();
  }

  Future<void> _driveOnce() async {
    _clearTimer();
    if (_disposed) return;
    try {
      await schedule.checkpoint(ScheduleOperation.list);
    } on Object catch (error) {
      _warn('schedule: preflight failed: $error');
      return;
    }
    if (_disposed) return;
    final ScheduleFold folded;
    try {
      folded = schedule.fold();
    } on Object catch (error) {
      _faulted = true;
      _warn('schedule: corrupt schedule log: $error');
      return;
    }
    final DateTime wakeNow = _clock();
    final DueDecision decision;
    try {
      decision = dueDecision(folded, wakeNow);
    } on Object catch (error) {
      _warn('schedule: due decision failed: $error');
      return;
    }
    if (decision is ScheduleWait) {
      final DateTime? target = decision.target;
      if (target != null) _arm(target, wakeNow);
      return;
    }
    await _deliverDue(decision);
  }

  Future<void> _deliverDue(DueDecision decision) async {
    final ScheduleDeliveryOutcome outcome = await deliverDueDecision(
      decision: decision,
      schedule: schedule,
      deliver: deliver,
      onWarning: _warn,
    );
    if (outcome == ScheduleDeliveryOutcome.faulted) {
      _faulted = true;
      _clearTimer();
      return;
    }
    if (outcome != ScheduleDeliveryOutcome.dispatched) return;
    if (!_disposed) requestDrive();
  }

  void _arm(DateTime target, DateTime now) {
    final Duration remaining = target.difference(now);
    if (remaining <= Duration.zero) return;
    _timer = Timer(
      remaining > kMaxTimerSegment ? kMaxTimerSegment : remaining,
      _onTimerFired,
    );
  }

  void _onTimerFired() {
    _timer = null;
    requestDrive();
  }

  void _clearTimer() {
    final Timer? timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
  }

  void _warn(String message) {
    final void Function(String message)? handler = _onWarning;
    if (handler != null) handler(message);
  }
}

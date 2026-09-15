/// timer 插件：把定时器做成 **Context 的可逆效应**。
///
/// 所有定时器都登记在调用方上下文的 [EffectScope] 上，随上下文释放自动清理；
/// 也可通过返回的 [Disposer] 提前取消。
///
/// ```dart
/// final ctx = Context.root();
/// ctx.timeout(() => print('hi'), const Duration(seconds: 1));
/// final Disposer tick = ctx.interval(() => print('tick'), const Duration(seconds: 1));
/// tick(); // 提前取消
/// ```
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';

/// [Context] 的定时器能力。
extension TimerContext on Context {
  /// 延迟 [delay] 后执行一次 [callback]；返回的 [Disposer] 可提前取消。
  Disposer timeout(void Function() callback, Duration delay) => effect(() {
        final Timer timer = Timer(delay, callback);
        return timer.cancel;
      });

  /// 每 [delay] 执行一次 [callback]；返回的 [Disposer] 可提前取消。
  Disposer interval(void Function() callback, Duration delay) => effect(() {
        final Timer timer = Timer.periodic(delay, (_) => callback());
        return timer.cancel;
      });

  /// 等待 [delay]。
  ///
  /// 若上下文在到点前被释放，返回的 Future 以 [StateError] 结束，
  /// 避免调用方悬挂。
  Future<void> sleep(Duration delay) {
    final Completer<void> completer = Completer<void>();
    effect(() {
      final Timer timer = Timer(delay, () {
        if (!completer.isCompleted) completer.complete();
      });
      return () {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('上下文 "$name" 已释放，sleep 被中断。'),
          );
        }
      };
    });
    return completer.future;
  }

  /// 节流：[delay] 窗口内的重复调用最多执行一次。
  ///
  /// [trailing] 为 true（默认）时，被抑制的调用会在窗口结束时补执行一次；
  /// 为 false 时直接丢弃。
  Throttled throttle(
    void Function() callback,
    Duration delay, {
    bool trailing = true,
  }) {
    final Throttled throttled = Throttled(callback, delay, trailing: trailing);
    track(throttled.dispose);
    return throttled;
  }

  /// 防抖：最后一次调用后静默 [delay] 才执行 [callback]。
  Debounced debounce(void Function() callback, Duration delay) {
    final Debounced debounced = Debounced(callback, delay);
    track(debounced.dispose);
    return debounced;
  }
}

/// 节流后的可调用包装；`call()` 触发调用，[dispose] 取消挂起中的补执行。
class Throttled {
  Throttled(this._callback, this._delay, {bool trailing = true})
      : _trailing = trailing;

  final void Function() _callback;
  final Duration _delay;
  final bool _trailing;
  Timer? _timer;
  int _lastRun = 0;
  bool _disposed = false;

  /// 触发一次调用。
  void call() {
    if (_disposed) return;
    final int remaining = _delay.inMicroseconds - (_now() - _lastRun);
    if (remaining <= 0) {
      _run();
    } else if (_trailing) {
      _timer?.cancel();
      _timer = Timer(Duration(microseconds: remaining), _run);
    }
  }

  /// 取消挂起中的定时器并停用该包装（幂等）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _run() {
    _timer = null;
    _lastRun = _now();
    _callback();
  }

  static int _now() => DateTime.now().microsecondsSinceEpoch;
}

/// 防抖后的可调用包装；`call()` 触发调用，[dispose] 取消挂起中的执行。
class Debounced {
  Debounced(this._callback, this._delay);

  final void Function() _callback;
  final Duration _delay;
  Timer? _timer;
  bool _disposed = false;

  /// 触发一次调用（会重置计时）。
  void call() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_delay, () {
      _timer = null;
      _callback();
    });
  }

  /// 取消挂起中的定时器并停用该包装（幂等）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

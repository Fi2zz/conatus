/// 收集调度：标脏 → 合并窗口 → 串行收集 → 发布新快照。
library;

import 'dart:async';

import 'skill_collect.dart';
import 'skill_provider.dart';
import 'skill_types.dart';

/// 技能快照的收集器。
///
/// [invalidate] 合并密集请求并调度一次收集；[refresh] 立即收集，且把并发调用
/// 共用成同一次（收集期间再次失效会在本轮结束后补一轮）。
class SkillCollector {
  /// 构造收集器；三个回调分别提供当前 provider、运行时技能与快照发布出口。
  SkillCollector({
    required List<SkillProvider> Function() providers,
    required Iterable<SkillRegistration> Function() runtime,
    required void Function(List<SkillSummary> summaries) publish,
    this.debounce = const Duration(milliseconds: 50),
    this.onWarning,
  })  : _providers = providers,
        _runtime = runtime,
        _publish = publish;

  /// 失效到收集之间的合并窗口。
  final Duration debounce;

  /// provider 侧的降级上报。
  final void Function(String message)? onWarning;

  final List<SkillProvider> Function() _providers;
  final Iterable<SkillRegistration> Function() _runtime;
  final void Function(List<SkillSummary> summaries) _publish;

  Timer? _timer;
  Future<void>? _running;
  bool _pending = false;
  bool _disposed = false;

  /// 立即收集；收集期间的并发调用共用同一次收集。
  Future<void> refresh() {
    final Future<void>? running = _running;
    if (running != null) {
      _pending = true;
      return running;
    }
    final Future<void> task = _collect().whenComplete(_settle);
    _running = task;
    return task;
  }

  /// 标记快照已过期并调度一次收集；合并窗口内的多次调用只收集一次。
  void invalidate() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(refresh());
    });
  }

  /// 取消待执行的收集；此后再调用 [refresh] / [invalidate] 不再生效。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = false;
  }

  Future<void> _collect() async {
    final List<SkillSummary> collected = await collectSkillSummaries(
      providers: List<SkillProvider>.of(_providers()),
      runtime: List<SkillRegistration>.of(_runtime()),
      onWarning: onWarning,
    );
    if (_disposed) return;
    _publish(collected);
  }

  void _settle() {
    _running = null;
    if (!_pending || _disposed) return;
    _pending = false;
    unawaited(refresh());
  }
}

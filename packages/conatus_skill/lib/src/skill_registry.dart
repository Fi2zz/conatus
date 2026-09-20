/// 技能注册表：provider 与运行时技能的集散地，维护一份可同步读取的可用快照。
///
/// [available] 是目录渲染与工具过滤读取的同步快照；provider 产出、运行时注册
/// 与 [invalidate] 都只标脏并调度一次收集（[SkillCollector]），完成后若快照
/// 确有变化，经 [onChange] 通知监听者。
///
/// 传入 [parent] 时本注册表成为子作用域：父级快照经 [visible] 过滤后并入
/// [available]，同名由本注册表赢下。父级变化级联到这里，只重新合并已有的自身
/// 快照，不重跑本注册表的 provider。
library;

import 'package:conatus_core/conatus_core.dart';

import 'skill_provider.dart';
import 'skill_refresh.dart';
import 'skill_scope.dart';
import 'skill_types.dart';

/// 技能注册表。
class SkillRegistry {
  /// 构造注册表；[refreshDebounce] 合并密集的失效请求。
  ///
  /// [parent] 非空时本注册表是子作用域，[visible] 决定从父级继承哪些技能
  /// （`null` 表示全部继承）。
  SkillRegistry({
    Duration refreshDebounce = const Duration(milliseconds: 50),
    this.onWarning,
    SkillRegistry? parent,
    SkillVisibility? visible,
  })  : _parent = parent,
        _visible = visible {
    _collector = SkillCollector(
      providers: () => _providers,
      runtime: () => _runtime.values,
      publish: _publish,
      debounce: refreshDebounce,
      onWarning: onWarning,
    );
    _parentSubscription = parent?.onChange(_republish);
  }

  /// provider 侧的降级上报（不会中断收集）。
  final void Function(String message)? onWarning;

  final SkillRegistry? _parent;
  final SkillVisibility? _visible;
  final List<SkillProvider> _providers = <SkillProvider>[];
  final Map<String, SkillRegistration> _runtime = <String, SkillRegistration>{};
  final List<void Function()> _listeners = <void Function()>[];
  late final SkillCollector _collector;
  Disposer? _parentSubscription;
  List<SkillSummary> _own = const <SkillSummary>[];
  List<SkillSummary> _available = const <SkillSummary>[];
  bool _disposed = false;

  /// 父作用域；根注册表为 `null`。
  SkillRegistry? get parent => _parent;

  /// 从父级继承技能的过滤谓词；`null` 表示全部继承。
  SkillVisibility? get visibility => _visible;

  /// 本注册表**自己**注册的 provider（不含父级）。
  List<SkillProvider> get providers =>
      List<SkillProvider>.unmodifiable(_providers);

  /// 当前可用技能的同步快照（名字码位升序），含继承自父级的部分。
  List<SkillSummary> get available => _available;

  /// 快照里允许模型调用的技能。
  List<SkillSummary> get modelInvocable => <SkillSummary>[
        for (final SkillSummary summary in _available)
          if (summary.modelInvocable) summary,
      ];

  /// 注册表是否已释放。
  bool get disposed => _disposed;

  /// 注册一个 provider。返回撤销函数（幂等），撤销后重新收集。
  Disposer registerProvider(SkillProvider provider) {
    _ensureActive();
    if (!isSkillName(provider.name)) {
      throw ArgumentError.value(provider.name, 'provider.name', '必须是技能名格式');
    }
    if (_providers.any((SkillProvider p) => p.name == provider.name)) {
      throw StateError('技能 provider "${provider.name}" 已注册。');
    }
    _providers.add(provider);
    invalidate();
    return () {
      if (_providers.remove(provider)) invalidate();
    };
  }

  /// 注册一条运行时技能。返回撤销函数（幂等），撤销后重新收集。
  Disposer register(SkillRegistration registration) {
    _ensureActive();
    if (!isSkillName(registration.name)) {
      throw ArgumentError.value(registration.name, 'name', '必须是技能名格式');
    }
    if (registration.description.trim().isEmpty) {
      throw ArgumentError.value(
          registration.description, 'description', '不能为空');
    }
    if (_runtime.containsKey(registration.name)) {
      throw StateError('运行时技能 "${registration.name}" 已注册。');
    }
    _runtime[registration.name] = registration;
    invalidate();
    return () {
      if (_runtime.remove(registration.name) != null) invalidate();
    };
  }

  /// 监听快照变化（逐字段相同的重复收集不通知）；返回撤销函数（幂等）。
  Disposer onChange(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// 立即重新收集所有技能。
  Future<void> refresh() => _collector.refresh();

  /// 标记快照已过期并调度一次收集。
  void invalidate() => _collector.invalidate();

  /// 按名字加载完整定义。
  ///
  /// 只认当前可见集合里的名字：被作用域过滤掉、未知或已消失的都返回 `null`，
  /// 因此模型无法绕过目录调用一个不可见的技能。
  Future<SkillDefinition?> load(String name) async {
    if (!isSkillName(name)) return null;
    final SkillSummary? summary = findSkillSummary(_available, name);
    if (summary == null) return null;
    if (findSkillSummary(_own, name) == null) return _parent?.load(name);
    final SkillRegistration? registration = _runtime[name];
    if (registration != null) return registration.toDefinition();
    final SkillProvider? provider = providerNamed(_providers, summary.provider);
    return provider == null ? null : _loadFrom(provider, summary);
  }

  /// 释放注册表：取消待执行的收集、父级级联与全部监听。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _parentSubscription?.call();
    _parentSubscription = null;
    _collector.dispose();
    _providers.clear();
    _runtime.clear();
    _listeners.clear();
    _own = const <SkillSummary>[];
    _available = const <SkillSummary>[];
  }

  void _publish(List<SkillSummary> collected) {
    if (_disposed) return;
    _own = List<SkillSummary>.unmodifiable(collected);
    _republish();
  }

  /// 用当前自身快照与父级快照重新合并并发布；父级变化也走这里。
  void _republish() {
    if (_disposed) return;
    final List<SkillSummary> merged = mergeScopedSummaries(
      parent: _parent?.available ?? const <SkillSummary>[],
      own: _own,
      visible: _visible,
      onShadowed: onWarning,
    );
    if (sameSkillSnapshot(merged, _available)) return;
    _available = List<SkillSummary>.unmodifiable(merged);
    for (final void Function() listener
        in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  Future<SkillDefinition?> _loadFrom(
    SkillProvider provider,
    SkillSummary summary,
  ) async {
    final SkillDefinition? definition = await provider.load(summary);
    if (definition != null) return definition;
    invalidate();
    return null;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('技能注册表已释放，无法再注册。');
    }
  }
}

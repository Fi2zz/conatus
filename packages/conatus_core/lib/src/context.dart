import 'dart:async';
import 'effect_scope.dart';
import 'reactor.dart';

/// 统一上下文：同时承载**效应**（可逆副作用）与**共效应**（声明式依赖）。
///
/// 这是论文中“上下文范式”的落地：
///
/// * 效应通过 [track] / [effect] / [onDispose] 登记，随上下文释放而撤销；
/// * 共效应通过 [provide]（提供服务）与 [inject]（声明依赖）表达，
///   服务可用性变化时会自动激活 / 停用组件。
///
/// 上下文组成一棵树。服务查找沿父链向上：
///
/// ```
/// root ──┬── pluginA ──┬── sub1
///        └── pluginB   └── sub2
/// ```
///
/// 子上下文可见父上下文提供的服务；反之不成立。
class Context {
  Context._(this._parent, this._reactor, this.name);

  /// 创建一个根上下文。
  factory Context.root({String name = 'root'}) =>
      Context._(null, Reactor(), name);

  final Context? _parent;
  final Reactor _reactor;
  final EffectScope _scope = EffectScope();
  final Map<String, Object?> _services = <String, Object?>{};

  /// 上下文名称，用于调试与日志。
  final String name;

  /// 父上下文；根上下文为 `null`。
  Context? get parent => _parent;

  /// 本上下文**直接**提供的服务名（不含继承部分）。
  Iterable<String> get localServiceKeys => _services.keys;

  /// 上下文是否已释放。
  bool get disposed => _scope.disposed;

  // ══════════════════════════════════════════════════════════════
  // 服务（空间可组合性的载体）
  // ══════════════════════════════════════════════════════════════

  /// 沿父链查找服务；找不到返回 `null`。
  ///
  /// [T] 必须是非空类型，避免“服务值为 null”与“服务不存在”产生歧义。
  T? get<T extends Object>(String key) {
    if (_services.containsKey(key)) return _services[key] as T?;
    return _parent?.get<T>(key);
  }

  /// 与 [get] 相同，但找不到时抛出 [StateError]。
  T require<T extends Object>(String key) {
    final T? value = get<T>(key);
    if (value == null) {
      throw StateError('服务 "$key" 在上下文 "$name" 中不可用。');
    }
    return value;
  }

  /// 服务是否可见（含继承）。
  bool has(String key) =>
      _services.containsKey(key) || (_parent?.has(key) ?? false);

  /// 在当前上下文提供服务。
  ///
  /// 服务随本上下文释放而自动移除。返回的 [Disposer] 亦可提前手动撤销
  /// （幂等）。撤销时若服务已被覆盖，则不会误删新值。
  ///
  /// 同一上下文中重复提供同名服务会抛出 [StateError]。
  Disposer provide(String key, Object? value) {
    if (_scope.disposed) {
      throw StateError('上下文 "$name" 已释放，无法再提供服务 "$key"。');
    }
    if (_services.containsKey(key)) {
      throw StateError('服务 "$key" 已在上下文 "$name" 中提供。');
    }

    _services[key] = value;
    _reactor.notify();

    bool removed = false;
    void disposer() {
      if (removed) return;
      removed = true;
      if (!identical(_services[key], value)) return;
      _services.remove(key);
      _reactor.notify();
    }

    _scope.track(disposer);
    return disposer;
  }

  // ══════════════════════════════════════════════════════════════
  // 效应（时间可组合性）
  // ══════════════════════════════════════════════════════════════

  /// 登记一个撤销函数。上下文释放时按 LIFO 顺序执行。
  void track(Disposer disposer) => _scope.track(disposer);

  /// 执行 [body]；若其返回值是 [Disposer]，则自动登记。
  T effect<T>(T Function() body) => _scope.capture(body);

  /// [track] 的语义化别名。
  void onDispose(Disposer callback) => track(callback);

  // ══════════════════════════════════════════════════════════════
  // 共效应（空间可组合性）
  // ══════════════════════════════════════════════════════════════

  /// 声明式依赖注入。
  ///
  /// 行为：
  ///
  /// * 当 [deps] 全部可见时，在**一个全新的子上下文**中执行 [callback]；
  /// * 任一依赖消失时，该子上下文连同其所有效应被撤销；
  /// * 依赖重新齐全时，[callback] 会在另一个全新子上下文中再次执行。
  ///
  /// 返回的 [Disposer] 用于手动取消注入（幂等）。该取消动作本身也会
  /// 被登记到当前上下文，随宿主释放而自动执行。
  ///
  /// ```dart
  /// ctx.inject(['logger'], (child) {
  ///   final logger = child.require<Logger>('logger');
  ///   logger.info('activated');
  ///   child.onDispose(() => print('deactivated'));
  /// });
  /// ```
  Disposer inject(List<String> deps, void Function(Context ctx) callback) {
    // 去重并冻结依赖列表，避免调用方后续修改影响语义
    final List<String> keys = List<String>.unmodifiable(deps.toSet());

    Context? active;
    bool cancelled = false;

    void evaluate() {
      if (cancelled || _scope.disposed) return;
      final bool ready = keys.every(has);

      if (ready && active == null) {
        final String depLabel = keys.join('+');
        final Context child = Context._(this, _reactor, '$name<$depLabel>');
        active = child;
        try {
          callback(child);
        } catch (error, stackTrace) {
          // 激活失败：回滚，并把错误交给当前 Zone 上报
          child._disposeInternal();
          active = null;
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      } else if (!ready && active != null) {
        final Context child = active!;
        active = null;
        child._disposeInternal();
      }
    }

    _reactor.add(evaluate);
    evaluate(); // 立即做第一次评估

    void canceller() {
      if (cancelled) return;
      cancelled = true;
      _reactor.remove(evaluate);
      final Context? child = active;
      active = null;
      child?._disposeInternal();
    }

    _scope.track(canceller); // 随宿主上下文自动清理
    return canceller;
  }

  // ══════════════════════════════════════════════════════════════
  // 插件（组件的加载单元）
  // ══════════════════════════════════════════════════════════════

  /// 加载一个插件：在派生的子上下文中执行 [install]。
  ///
  /// 返回的子上下文可用于后续卸载（调用 `dispose()`）。
  /// 该子上下文同时会被登记到当前上下文，因此父上下文释放时会一并卸载。
  ///
  /// 若 [install] 抛出异常，子上下文会被回滚，异常继续向上传播。
  Context plugin(String name, void Function(Context ctx) install) {
    final Context child = Context._(this, _reactor, '$this/$name');
    track(child._disposeInternal);
    try {
      install(child);
    } catch (_) {
      child._disposeInternal();
      rethrow;
    }
    return child;
  }

  // ══════════════════════════════════════════════════════════════
  // 生命周期
  // ══════════════════════════════════════════════════════════════

  /// 释放上下文：撤销所有效应，移除所有提供的服务。
  /// 幂等。
  void dispose() => _disposeInternal();

  void _disposeInternal() {
    _scope.dispose();
    if (_services.isNotEmpty) {
      // 兜底：正常情况下 _services 已被 provide 的 disposer 清空。
      // 若某个 disposer 意外重新提供了服务，这里一并清掉。
      _services.clear();
      _reactor.notify();
    }
  }

  @override
  String toString() => 'Context($name)';
}

/// 时间可组合性（Temporal Composability）的实现。
///
/// 核心思想：组件每一次施加副作用，都同时登记一个“撤销函数”。
/// 组件卸载时，所有撤销函数按 LIFO 顺序执行，使组件仿佛从未存在过。
library;

/// 撤销函数。
///
/// 调用它应使系统恢复到副作用施加之前的状态。
/// 同一个 [Disposer] 可能被多次调用（例如作用域释放后又手动调用），
/// 因此实现应当是幂等的。
typedef Disposer = void Function();

/// 收集一组可逆副作用，并按 LIFO（后进先出）顺序统一撤销。
///
/// ```dart
/// final scope = EffectScope();
/// scope.track(() => print('cleanup 1'));
/// scope.track(() => print('cleanup 2'));
/// scope.dispose();
/// // 输出：cleanup 2 → cleanup 1
/// ```
///
/// 关键性质：
///
/// 1. **幂等**：重复调用 [dispose] 只会真正释放一次。
/// 2. **迟到安全**：作用域释放后再调用 [track]，撤销函数会立即执行，
///    避免异步初始化中的清理函数造成泄漏。
/// 3. **抗异常**：单个撤销函数抛出异常不会阻断其余撤销；
///    所有异常被收集后由 [dispose] 返回。
class EffectScope {
  final List<Disposer> _disposers = <Disposer>[];
  bool _disposed = false;

  /// 作用域是否已被释放。
  bool get disposed => _disposed;

  /// 当前登记的撤销函数数量。
  int get length => _disposers.length;

  /// 登记一个撤销函数。
  ///
  /// 若作用域已经释放，[disposer] 会被**立即执行**。
  void track(Disposer disposer) {
    if (_disposed) {
      disposer();
      return;
    }
    _disposers.add(disposer);
  }

  /// 执行 [body]；若其返回值是 [Disposer]，则自动登记。
  ///
  /// ```dart
  /// final sub = scope.capture(() => stream.listen(onData));
  /// // sub 已被登记为撤销函数
  /// ```
  T capture<T>(T Function() body) {
    final T result = body();
    if (result is Disposer) {
      track(result);
    }
    return result;
  }

  /// 释放作用域：按 LIFO 顺序执行所有撤销函数。
  ///
  /// 单个撤销函数抛出的异常不会阻断其余撤销。返回捕获到的所有错误，
  /// 由调用方决定如何上报。返回空列表表示全部成功。
  List<Object> dispose() {
    if (_disposed) return const <Object>[];
    _disposed = true;
    final List<Object> errors = <Object>[];
    while (_disposers.isNotEmpty) {
      final Disposer disposer = _disposers.removeLast();
      try {
        disposer();
      } catch (error) {
        errors.add(error);
      }
    }
    return errors;
  }
}

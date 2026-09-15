/// 空间可组合性（Spatial Composability）的调度核心。
library;

/// 反应器监听器签名。
typedef ReactorListener = void Function();

/// 服务变更的同步广播器。
///
/// 采用**“脏标记 + 重跑”**策略处理重入：若在通知过程中（某个监听器内）
/// 又发生了服务变更，则整个监听器列表会被重新评估一轮，直到系统收敛。
/// 这保证了依赖链 `A → B → C` 能一次性稳定下来，无需调用方手动编排顺序。
///
/// ```dart
/// final reactor = Reactor();
/// reactor.add(() => print('service changed'));
/// reactor.notify(); // 输出：service changed
/// ```
class Reactor {
  /// 创建反应器。
  ///
  /// [maxRounds] 限制单次 [notify] 中允许的最大重跑轮数，
  /// 用于在循环依赖导致无法收敛时快速失败，而不是死循环。
  Reactor({this.maxRounds = 100}) {
    if (maxRounds <= 0) {
      throw ArgumentError.value(maxRounds, 'maxRounds', '必须为正数');
    }
  }

  /// 单次 [notify] 中允许的最大重跑轮数；超过则抛出 [StateError]。
  final int maxRounds;

  final List<ReactorListener> _listeners = <ReactorListener>[];
  bool _running = false;
  bool _dirty = false;

  /// 是否正在广播中。
  bool get isRunning => _running;

  /// 已登记的监听器数量。
  int get length => _listeners.length;

  /// 添加监听器。同一函数可被重复添加。
  void add(ReactorListener listener) => _listeners.add(listener);

  /// 移除一个监听器。返回是否确实移除了一个实例。
  bool remove(ReactorListener listener) => _listeners.remove(listener);

  /// 触发一次广播。
  ///
  /// 若当前已有广播在进行中（重入），仅设置脏标记后立即返回，
  /// 由最外层的广播循环负责再跑一轮。
  ///
  /// 若在 [maxRounds] 轮内未能收敛（即每轮都产生新的脏标记），
  /// 抛出 [StateError]。这通常意味着两个组件在循环地互相激活。
  void notify() {
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    try {
      int round = 0;
      do {
        _dirty = false;
        if (++round > maxRounds) {
          throw StateError(
            '共效应重评估在 $maxRounds 轮后仍未收敛，'
            '可能存在循环依赖（A 的激活依赖 B，B 的激活又依赖 A）。',
          );
        }
        // 快照遍历，避免监听器在回调中修改 _listeners 造成并发修改异常
        for (final ReactorListener listener
            in List<ReactorListener>.of(_listeners)) {
          listener();
        }
      } while (_dirty);
    } finally {
      _running = false;
    }
  }
}

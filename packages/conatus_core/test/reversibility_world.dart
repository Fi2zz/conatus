/// 可逆效应验证用的「世界」：真实外部状态 + 独立可观测的投影。
///
/// 投影的每一项都必须**独立于被测插件的记账**，否则「忘了记账」会把泄漏一起
/// 掩盖掉：
///
/// * 定时器读 Dart 自己的 `Timer.isActive`；
/// * 订阅读 `StreamController.hasListener`；
/// * 资源句柄读自己的 `open` 标志；
/// * 服务读 `Context.localServiceKeys`。
///
/// 世界只**单调**记录「创建过哪些资源」，从不做删除，因此漏释放只会让投影变化。
/// 唯一由被测代码写入的是资源自身的状态位，而它正是逆必须作用的对象。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';

/// 可撤销效果的种类。
enum EffectKind {
  /// 改写共享值：逆必须恢复**它自己看到的上一个值**（顺序敏感）。
  bumpShared,

  /// 在子上下文提供服务（`Context.provide` 自带登记）。
  provideService,

  /// 开一条流并订阅（逆应取消订阅）。
  openStream,

  /// 起一个周期定时器（逆应取消它）。
  startTimer,

  /// 申请一个外部资源句柄（逆应关闭它）。
  acquireHandle,

  /// 往共享注册表登记一个名字（逆应移除它）。
  registerName,
}

/// 一个外部资源句柄。
class ResourceHandle {
  /// 用给定 id 构造，初始为打开。
  ResourceHandle(this.id);

  /// 资源标识。
  final String id;

  /// 是否仍然打开。
  bool open = true;

  /// 关闭它。
  void close() => open = false;
}

/// 验证世界：承载真实效果与真实资源。
class EffectWorld {
  /// 共享可变状态（多个插件的效果会在此互相影响）。
  final Map<String, int> shared = <String, int>{};

  /// 共享注册表。
  final Set<String> registry = <String>{};

  /// 创建过的全部定时器（只增不删）。
  final List<Timer> timers = <Timer>[];

  /// 创建过的全部流控制器（只增不删）。
  final List<StreamController<int>> streams = <StreamController<int>>[];

  /// 创建过的全部资源句柄（只增不删）。
  final List<ResourceHandle> handles = <ResourceHandle>[];

  int _seq = 0;

  /// 生成一个不重复的名字。
  String nextName(String prefix) => '$prefix-${_seq++}';

  /// 申请一个资源句柄。
  ResourceHandle acquire() {
    final ResourceHandle handle = ResourceHandle(nextName('h'));
    handles.add(handle);
    return handle;
  }

  /// 起一个周期定时器。
  Timer startTimer() {
    final Timer timer = Timer.periodic(const Duration(seconds: 1), (_) {});
    timers.add(timer);
    return timer;
  }

  /// 开一条流控制器（广播，便于观察 `hasListener`）。
  StreamController<int> openStream() {
    final StreamController<int> controller = StreamController<int>.broadcast();
    streams.add(controller);
    return controller;
  }

  /// 独立可观测的投影；行序稳定，便于失败时逐行 diff。
  List<String> project(List<Context> contexts) => <String>[
        '共享值: ${_pairs()}',
        '注册表: ${(registry.toList()..sort()).join('|')}',
        '句柄: ${_openHandles()}',
        '定时器存活: ${timers.where((Timer t) => t.isActive).length}',
        '订阅存活: ${streams.where((StreamController<int> c) => c.hasListener).length}',
        for (final Context ctx in contexts)
          if (!ctx.disposed)
            '上下文 ${ctx.name}: ${(ctx.localServiceKeys.toList()..sort()).join('|')}',
      ];

  /// 取消全部定时器、关闭全部流控制器（测试收尾用，与插件行为无关）。
  Future<void> teardown() async {
    for (final Timer timer in timers) {
      timer.cancel();
    }
    for (final StreamController<int> controller in streams) {
      await controller.close();
    }
  }

  String _pairs() {
    final List<String> keys = shared.keys.toList()..sort();
    return keys.map((String k) => '$k=${shared[k]}').join('|');
  }

  String _openHandles() => (handles
          .where((ResourceHandle h) => h.open)
          .map((ResourceHandle h) => h.id)
          .toList()
        ..sort())
      .join('|');
}

/// 施加一种效果，返回它的逆（**尚未**登记）。
///
/// 除 [EffectKind.provideService] 由 `Context.provide` 自登记外，其余逆都由调用方
/// 决定是否登记——这正是「漏登记」这一失败模式得以被构造的原因。
Disposer applyEffect(EffectWorld world, Context ctx, EffectKind kind) =>
    switch (kind) {
      EffectKind.bumpShared => _bumpShared(world),
      EffectKind.provideService =>
        ctx.provide(world.nextName('svc'), world.shared.length),
      EffectKind.openStream => _openStream(world),
      EffectKind.startTimer => world.startTimer().cancel,
      EffectKind.acquireHandle => world.acquire().close,
      EffectKind.registerName => _registerName(world),
    };

Disposer _bumpShared(EffectWorld world) {
  final int? previous = world.shared['shared'];
  world.shared['shared'] = (previous ?? 0) + 1;
  return () {
    if (previous == null) {
      world.shared.remove('shared');
    } else {
      world.shared['shared'] = previous;
    }
  };
}

Disposer _openStream(EffectWorld world) {
  final StreamSubscription<int> subscription =
      world.openStream().stream.listen((int _) {});
  return () => unawaited(subscription.cancel());
}

Disposer _registerName(EffectWorld world) {
  final String name = world.nextName('r');
  world.registry.add(name);
  return () => world.registry.remove(name);
}

/// 可逆效应验证的驱动：挂载/卸载插件，并按独立投影逐前缀比对。
///
/// oracle 按论文 Theorem 16 取：先记下「只装了前 k 个插件」时的投影，逆序卸载后
/// 第 k 步必须回到该投影——比「最终等于初始」强得多，能杀掉「几个逆互相抵消」与
/// 「只在整体 LIFO 下才成立」的假可逆。
library;

import 'dart:math';
import 'package:conatus_core/conatus_core.dart';
import 'reversibility_world.dart';

/// 插件的行为模式，用于构造真实失败模式与负向对照。
enum PluginMode {
  /// 正确：每个效果的逆都被登记。
  correct,

  /// 安慰剂：登记了逆，但它什么都不做。
  placebo,

  /// 漏登记：效果施加了，逆从未登记。
  unregistered,

  /// 半个逆：只登记第一个效果的逆，其余用安慰剂顶替。
  halfRestore,
}

/// 一个待挂载的插件。
class PluginSpec {
  /// 用名字、效果序列与行为模式构造。
  const PluginSpec(this.name, this.effects, {this.mode = PluginMode.correct});

  /// 插件名（子上下文名）。
  final String name;

  /// 依次施加的效果。
  final List<EffectKind> effects;

  /// 行为模式。
  final PluginMode mode;
}

/// 一次回放的两端轨迹。
typedef Playback = ({List<List<String>> mounted, List<List<String>> unmounted});

/// 驱动插件挂载与卸载，并按投影逐前缀比对。
class ReversibilityHarness {
  /// 建一个全新的根上下文与空世界。
  ReversibilityHarness()
      : root = Context.root(),
        world = EffectWorld();

  /// 根上下文。
  final Context root;

  /// 验证世界。
  final EffectWorld world;

  final List<Context> _mounted = <Context>[];

  /// 夹具自检用：真正交给作用域登记的逆的个数。
  ///
  /// 它观察的是**夹具自己**的行为，用于钉住三种失败模式确实被构造成了不同形态
  /// （`placebo` / `halfRestore` 会登记，`unregistered` 一个都不登记）。
  int tracked = 0;

  /// 当前独立可观测投影。
  List<String> project() => world.project(<Context>[root, ..._mounted]);

  /// 把 [spec] 挂载为一个子上下文（效果与逆都落在其中）。
  Context mount(PluginSpec spec) {
    final Context ctx = root.plugin(spec.name, (Context c) {
      for (int i = 0; i < spec.effects.length; i++) {
        _register(c, applyEffect(world, c, spec.effects[i]), spec, i);
      }
    });
    _mounted.add(ctx);
    return ctx;
  }

  /// 挂载全部插件，再按 [unmountOrder]（缺省 LIFO）卸载，返回两端轨迹。
  Playback play(List<PluginSpec> specs, {List<int>? unmountOrder}) {
    final List<Context> here = <Context>[];
    final List<List<String>> mounted = <List<String>>[project()];
    for (final PluginSpec spec in specs) {
      here.add(mount(spec));
      mounted.add(project());
    }
    final List<int> order =
        unmountOrder ?? <int>[for (int i = specs.length - 1; i >= 0; i--) i];
    final List<List<String>> unmounted = <List<String>>[];
    for (final int index in order) {
      here[index].dispose();
      unmounted.add(project());
    }
    return (mounted: mounted, unmounted: unmounted);
  }

  /// Theorem 16 的 oracle：逆序卸载后第 k 步必须等于「只装了前 n−k 个」。
  ///
  /// 返回违规描述；空列表表示通过。
  List<String> runLifo(List<PluginSpec> specs) {
    final Playback playback = play(specs);
    final List<String> problems = <String>[];
    for (int step = 0; step < playback.unmounted.length; step++) {
      final int index = specs.length - 1 - step;
      problems.addAll(
        _diff(specs[index].name, playback.mounted[index],
            playback.unmounted[step]),
      );
    }
    return problems;
  }

  /// 测试收尾：取消定时器、关闭流，避免泄漏的周期定时器拖住测试进程。
  Future<void> teardown() => world.teardown();

  void _register(Context ctx, Disposer inverse, PluginSpec spec, int index) {
    if (spec.mode == PluginMode.unregistered) return;
    ctx.track(_effective(inverse, spec.mode, index));
    tracked++;
  }

  Disposer _effective(Disposer inverse, PluginMode mode, int index) {
    if (mode == PluginMode.correct) return inverse;
    if (mode == PluginMode.halfRestore && index == 0) return inverse;
    return _placebo;
  }

  List<String> _diff(String name, List<String> expected, List<String> actual) {
    if (expected.length != actual.length) {
      return <String>['卸载 $name 后投影行数从 ${expected.length} 变成 ${actual.length}'];
    }
    final List<String> problems = <String>[];
    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != actual[i]) {
        problems.add('卸载 $name 后未还原，第 $i 行：期望「${expected[i]}」实际「${actual[i]}」');
      }
    }
    return problems;
  }
}

void _placebo() {}

/// 用 [seed] 生成 [count] 个随机插件（每个 1–3 个效果，名字唯一）。
List<PluginSpec> randomPlugins(int seed, int count) {
  final Random random = Random(seed);
  const List<EffectKind> kinds = EffectKind.values;
  return <PluginSpec>[
    for (int i = 0; i < count; i++)
      PluginSpec('p$i', <EffectKind>[
        for (int k = 0; k <= random.nextInt(3); k++)
          kinds[random.nextInt(kinds.length)],
      ]),
  ];
}

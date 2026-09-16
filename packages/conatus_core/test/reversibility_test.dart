import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';
import 'reversibility_harness.dart';
import 'reversibility_world.dart';

/// 两个都改写同一共享值的插件：只有按逆序还原才回得到基线。
List<PluginSpec> _bumpPair() => const <PluginSpec>[
      PluginSpec('x', <EffectKind>[EffectKind.bumpShared]),
      PluginSpec('y', <EffectKind>[EffectKind.bumpShared]),
    ];

/// 覆盖全部效果种类的定长序列。
List<PluginSpec> _allKinds() => const <PluginSpec>[
      PluginSpec('a', <EffectKind>[
        EffectKind.provideService,
        EffectKind.registerName,
      ]),
      PluginSpec('b', <EffectKind>[
        EffectKind.openStream,
        EffectKind.startTimer,
      ]),
      PluginSpec('c', <EffectKind>[
        EffectKind.acquireHandle,
        EffectKind.bumpShared,
      ]),
      PluginSpec('d', <EffectKind>[
        EffectKind.bumpShared,
        EffectKind.bumpShared,
      ]),
    ];

void main() {
  group('Theorem 16 — 逆序卸载逐前缀还原', () {
    for (final int seed in <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      test('随机插件序列 seed=$seed', () {
        final ReversibilityHarness harness = ReversibilityHarness();
        addTearDown(harness.teardown);

        expect(harness.runLifo(randomPlugins(seed, 5)), isEmpty);
      });
    }

    test('覆盖全部效果种类的定长序列', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);

      expect(harness.runLifo(_allKinds()), isEmpty);
    });

    test('两个改写同一共享值的插件', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);

      expect(harness.runLifo(_bumpPair()), isEmpty);
    });
  });

  group('Theorem 7 — 单个效果的逆直接见证方程 g(f(γ)) = γ', () {
    /// 事实上的核心方程：施加效果后手工调用它的逆，状态必须逐字节还原。
    /// 这条不经过 `EffectScope`，因此它验的是「逆本身对不对」，
    /// 与「累积器有没有按 LIFO 调用逆」是两件正交的事。
    test('每种效果的逆都能把它自己的效果还原', () {
      for (final EffectKind kind in EffectKind.values) {
        final EffectWorld world = EffectWorld();
        final Context root = Context.root();
        addTearDown(world.teardown);
        addTearDown(root.dispose);
        final Context plugin = root.plugin('p', (Context _) {});

        final List<String> before = world.project(<Context>[root, plugin]);
        final Disposer inverse = applyEffect(world, plugin, kind);

        expect(world.project(<Context>[root, plugin]), isNot(before),
            reason: '$kind 的效果没有发生');
        inverse();
        expect(world.project(<Context>[root, plugin]), before,
            reason: '$kind 的逆没有还原它自己施加的状态');
      }
    });
  });

  group('Definition 8 — 逆只在它被施加的状态上见证', () {
    test('乱序卸载必然发散：oracle 对顺序敏感', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();

      final Playback playback =
          harness.play(_bumpPair(), unmountOrder: <int>[0, 1]);

      expect(playback.unmounted.last, isNot(baseline));
    });
  });

  group('F7 — 外部资源真的释放', () {
    test('卸载后定时器 / 订阅 / 句柄全部归零，投影回到基线', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();

      harness.play(_allKinds());

      expect(
        harness.world.timers.where((Timer timer) => timer.isActive),
        isEmpty,
      );
      expect(
        harness.world.streams
            .where((StreamController<int> c) => c.hasListener),
        isEmpty,
      );
      expect(
        harness.world.handles.where((ResourceHandle h) => h.open),
        isEmpty,
      );
      expect(harness.project(), baseline);
    });

    test('反复挂载卸载 200 轮不漂移', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();
      final List<PluginSpec> specs = <PluginSpec>[
        const PluginSpec('a', <EffectKind>[
          EffectKind.startTimer,
          EffectKind.registerName,
          EffectKind.bumpShared,
        ]),
        const PluginSpec('b', <EffectKind>[
          EffectKind.openStream,
          EffectKind.acquireHandle,
        ]),
      ];

      for (int round = 0; round < 200; round++) {
        expect(harness.runLifo(specs), isEmpty, reason: '第 $round 轮');
      }

      expect(harness.project(), baseline);
      expect(
        harness.world.timers.where((Timer timer) => timer.isActive),
        isEmpty,
      );
    });
  });
}

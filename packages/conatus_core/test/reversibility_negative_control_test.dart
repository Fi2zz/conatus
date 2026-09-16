/// 负向对照：检查器必须先被证明**能失败**，它的通过才有意义。
///
/// 三个坏插件分别对应三种真实的假可逆（安慰剂逆 / 漏登记 / 半个逆），本文件断言
/// 它们**全部被检出**；同时断言正确插件不被误报、且投影在挂载期间确实变化——
/// 后者排除「投影是个常量、所以什么都不报」这种空转的检查器。
library;

import 'package:test/test.dart';
import 'reversibility_harness.dart';
import 'reversibility_world.dart';

List<String> _violationsFor(PluginSpec spec) {
  final ReversibilityHarness harness = ReversibilityHarness();
  addTearDown(harness.teardown);
  return harness.runLifo(<PluginSpec>[spec]);
}

/// 两个效果都**不由** `Context.provide` 自登记，因此 `harness.tracked` 只反映
/// 夹具自己的登记行为。
int _trackedFor(PluginMode mode) {
  final ReversibilityHarness harness = ReversibilityHarness();
  addTearDown(harness.teardown);
  harness.play(<PluginSpec>[
    PluginSpec(
      'p',
      <EffectKind>[EffectKind.registerName, EffectKind.openStream],
      mode: mode,
    ),
  ]);
  return harness.tracked;
}

/// 覆盖全部效果种类的正确插件。
const PluginSpec _good = PluginSpec('good', <EffectKind>[
  EffectKind.provideService,
  EffectKind.registerName,
  EffectKind.openStream,
  EffectKind.startTimer,
  EffectKind.acquireHandle,
  EffectKind.bumpShared,
]);

void main() {
  group('负向对照 — 检查器必须能失败', () {
    test('安慰剂逆（登记了但什么都不做）被检出', () {
      expect(
        _violationsFor(const PluginSpec(
          'p',
          <EffectKind>[EffectKind.startTimer],
          mode: PluginMode.placebo,
        )),
        isNotEmpty,
      );
    });

    test('漏登记（逆从未登记）被检出', () {
      expect(
        _violationsFor(const PluginSpec(
          'p',
          <EffectKind>[EffectKind.registerName],
          mode: PluginMode.unregistered,
        )),
        isNotEmpty,
      );
    });

    test('半个逆（只还原一部分）被检出', () {
      expect(
        _violationsFor(const PluginSpec(
          'p',
          <EffectKind>[EffectKind.registerName, EffectKind.bumpShared],
          mode: PluginMode.halfRestore,
        )),
        isNotEmpty,
      );
    });
  });

  group('夹具自检 — 三种失败模式确实被构造成了不同形态', () {
    test('登记个数：correct / placebo / halfRestore 会登记，unregistered 一个都不登记', () {
      expect(_trackedFor(PluginMode.correct), 2);
      expect(_trackedFor(PluginMode.placebo), 2);
      expect(_trackedFor(PluginMode.halfRestore), 2);
      expect(_trackedFor(PluginMode.unregistered), 0);
    });
  });

  group('阳性对照 — 正确插件不被误报', () {
    test('全部效果种类的正确插件零违规', () {
      expect(_violationsFor(_good), isEmpty);
    });

    test('无效果的插件零违规', () {
      expect(_violationsFor(const PluginSpec('p', <EffectKind>[])), isEmpty);
    });

    test('投影在挂载期间确实变化，卸载后确实复原', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();

      final Playback playback = harness.play(<PluginSpec>[_good]);

      expect(playback.mounted.last, isNot(baseline));
      expect(playback.unmounted.last, baseline);
    });
  });
}

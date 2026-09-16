/// 可逆效应的对抗探针：把验证期间证明有效的攻击固定为永久用例。
///
/// 前三条是**泄漏检测的端到端钉**（只泄漏一种资源，确保投影的每一行都被独立钉住）；
/// 后两条是机制没直接覆盖的失败模式（嵌套级联、逆抛异常）。
///
/// 每一条在写成前都被反向验过：对应的投影行或逻辑被变异时，它会失败（见
/// `tool/mutate_reversibility.sh` 与 handoff-5.md §3）。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';
import 'reversibility_harness.dart';
import 'reversibility_world.dart';

void main() {
  group('泄漏检测：每一行投影都被独立钉住', () {
    test('安慰剂逆泄漏流被检出（只泄漏流）', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);

      expect(
        harness.runLifo(<PluginSpec>[
          const PluginSpec(
            'p',
            <EffectKind>[EffectKind.openStream],
            mode: PluginMode.placebo,
          ),
        ]),
        isNotEmpty,
      );
    });

    test('安慰剂逆泄漏句柄被检出（只泄漏句柄）', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);

      expect(
        harness.runLifo(<PluginSpec>[
          const PluginSpec(
            'p',
            <EffectKind>[EffectKind.acquireHandle],
            mode: PluginMode.placebo,
          ),
        ]),
        isNotEmpty,
      );
    });
  });

  group('嵌套插件：父释放带动子释放', () {
    test('嵌套挂载 → 卸载父 → 投影回基线', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();

      final Context outer = harness.root.plugin('outer', (Context c) {
        c.plugin('inner', (Context inner) {
          inner.track(
              applyEffect(harness.world, inner, EffectKind.registerName));
          inner.track(applyEffect(harness.world, inner, EffectKind.bumpShared));
        });
      });
      expect(harness.project(), isNot(baseline));

      outer.dispose();

      expect(harness.project(), baseline);
      expect(harness.world.registry, isEmpty);
      expect(harness.world.shared, isEmpty);
    });
  });

  group('逆抛异常：不阻断其余逆', () {
    test('一个逆抛异常时其余效果仍被还原，dispose 不传播', () {
      final ReversibilityHarness harness = ReversibilityHarness();
      addTearDown(harness.teardown);
      final List<String> baseline = harness.project();

      final Context ctx = harness.root.plugin('p', (Context c) {
        c.track(applyEffect(harness.world, c, EffectKind.registerName));
        c.track(() => throw StateError('boom'));
        c.track(applyEffect(harness.world, c, EffectKind.bumpShared));
      });

      expect(ctx.dispose, returnsNormally);

      expect(harness.project(), baseline);
      expect(harness.world.registry, isEmpty);
      expect(harness.world.shared, isEmpty);
    });
  });
}

import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

void main() {
  group('EffectScope 元数据', () {
    test('id 缺省自动分配且唯一', () {
      final EffectScope a = EffectScope();
      final EffectScope b = EffectScope();
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });

    test('id 可显式指定', () {
      expect(EffectScope(id: 'patch-42').id, 'patch-42');
    });

    test('reversibility 缺省 internal，可指定', () {
      expect(EffectScope().reversibility, EffectReversibility.internal);
      expect(
        EffectScope(reversibility: EffectReversibility.oneWayDoor)
            .reversibility,
        EffectReversibility.oneWayDoor,
      );
    });

    test('元数据不改变 dispose 语义', () {
      final List<String> order = <String>[];
      final EffectScope scope = EffectScope(
        id: 's',
        reversibility: EffectReversibility.compensable,
      )
        ..track(() => order.add('a'))
        ..track(() => order.add('b'));
      expect(scope.dispose(), isEmpty);
      expect(order, <String>['b', 'a']);
    });
  });
}

import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

void main() {
  group('EffectScope', () {
    test('按 LIFO 顺序撤销', () {
      final scope = EffectScope();
      final order = <int>[];
      scope.track(() => order.add(1));
      scope.track(() => order.add(2));
      scope.track(() => order.add(3));

      final errors = scope.dispose();

      expect(errors, isEmpty);
      expect(order, <int>[3, 2, 1]);
    });

    test('dispose 是幂等的', () {
      final scope = EffectScope();
      var count = 0;
      scope.track(() => count++);

      scope.dispose();
      scope.dispose();
      scope.dispose();

      expect(count, 1);
    });

    test('已释放后 track 会立即执行', () {
      final scope = EffectScope();
      scope.dispose();

      var called = false;
      scope.track(() => called = true);

      expect(called, isTrue);
    });

    test('单个撤销抛错不阻断其余撤销', () {
      final scope = EffectScope();
      final order = <int>[];
      scope.track(() => order.add(1));
      scope.track(() => throw StateError('boom'));
      scope.track(() => order.add(3));

      final errors = scope.dispose();

      expect(order, <int>[3, 1]);
      expect(errors, hasLength(1));
      expect(errors.first, isA<StateError>());
    });

    test('capture 自动登记 Disposer 返回值', () {
      final scope = EffectScope();
      var disposed = false;

      scope.capture(() => () {
            disposed = true;
          });

      expect(disposed, isFalse);
      scope.dispose();
      expect(disposed, isTrue);
    });

    test('capture 对非 Disposer 返回值不做处理', () {
      final scope = EffectScope();
      final result = scope.capture(() => 42);
      expect(result, 42);
      expect(scope.length, 0);
    });

    test('disposed 与 length 反映作用域状态', () {
      final scope = EffectScope();
      expect(scope.disposed, isFalse);
      expect(scope.length, 0);

      scope.track(() {});
      scope.track(() {});

      expect(scope.length, 2);
      scope.dispose();
      expect(scope.disposed, isTrue);
      expect(scope.length, 0);
    });
  });
}

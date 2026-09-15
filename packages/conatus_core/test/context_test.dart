import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

void main() {
  group('Context — 服务', () {
    test('provide / get / has 基础行为', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      expect(ctx.has('foo'), isFalse);
      expect(ctx.get<String>('foo'), isNull);

      ctx.provide('foo', 'bar');

      expect(ctx.has('foo'), isTrue);
      expect(ctx.get<String>('foo'), 'bar');
    });

    test('require 找不到时抛 StateError', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      expect(() => ctx.require<String>('foo'), throwsStateError);
    });

    test('重复 provide 抛 StateError', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      ctx.provide('foo', 'bar');
      expect(() => ctx.provide('foo', 'baz'), throwsStateError);
    });

    test('已释放的上下文不能再提供服务', () {
      final ctx = Context.root();
      ctx.dispose();
      expect(() => ctx.provide('foo', 'bar'), throwsStateError);
    });

    test('子上下文继承父上下文服务', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('foo', 'bar');

      final child = root.plugin('child', (_) {});

      expect(child.has('foo'), isTrue);
      expect(child.get<String>('foo'), 'bar');
    });

    test('子上下文提供同名服务会遮蔽父级', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('foo', 'root');

      final child = root.plugin('child', (ctx) => ctx.provide('foo', 'child'));

      expect(child.get<String>('foo'), 'child');
      expect(root.get<String>('foo'), 'root');
    });

    test('子上下文提供的服务对父级不可见', () {
      final root = Context.root();
      addTearDown(root.dispose);

      root.plugin('child', (ctx) => ctx.provide('foo', 'bar'));

      expect(root.has('foo'), isFalse);
    });

    test('provide 返回的 Disposer 可提前撤销服务', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      final stop = ctx.provide('foo', 'bar');
      expect(ctx.has('foo'), isTrue);

      stop();
      expect(ctx.has('foo'), isFalse);

      // 幂等
      stop();
      expect(ctx.has('foo'), isFalse);
    });

    test('localServiceKeys 只列出本上下文直接提供的服务', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('foo', 1);

      final child = root.plugin('child', (ctx) => ctx.provide('bar', 2));

      expect(root.localServiceKeys, <String>['foo']);
      expect(child.localServiceKeys, <String>['bar']);
    });
  });

  group('Context — 效应', () {
    test('track 登记撤销函数', () {
      final ctx = Context.root();
      var disposed = false;
      ctx.track(() => disposed = true);

      expect(disposed, isFalse);
      ctx.dispose();
      expect(disposed, isTrue);
    });

    test('onDispose 是 track 的别名', () {
      final ctx = Context.root();
      var disposed = false;
      ctx.onDispose(() => disposed = true);

      ctx.dispose();
      expect(disposed, isTrue);
    });

    test('effect 自动登记 Disposer 返回值', () {
      final ctx = Context.root();
      var disposed = false;
      ctx.effect(() => () {
            disposed = true;
          });

      ctx.dispose();
      expect(disposed, isTrue);
    });

    test('释放后 effect 会立即执行撤销', () {
      final ctx = Context.root();
      ctx.dispose();

      var disposed = false;
      ctx.effect(() => () {
            disposed = true;
          });

      expect(disposed, isTrue);
    });
  });

  group('Context — 插件', () {
    test('plugin 返回子上下文', () {
      final root = Context.root();
      addTearDown(root.dispose);

      final child = root.plugin('a', (_) {});

      expect(child.parent, same(root));
      expect(child.name, contains('a'));
    });

    test('卸载子上下文不影响父上下文', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('root-service', 1);

      final child =
          root.plugin('child', (ctx) => ctx.provide('child-service', 2));

      child.dispose();

      expect(child.disposed, isTrue);
      expect(root.disposed, isFalse);
      expect(root.has('root-service'), isTrue);
      expect(root.has('child-service'), isFalse);
    });

    test('父上下文释放会级联释放子上下文', () {
      final root = Context.root();

      final child = root.plugin('child', (_) {});

      root.dispose();

      expect(child.disposed, isTrue);
    });

    test('plugin 抛异常时会回滚子上下文并重新抛出', () {
      final root = Context.root();
      addTearDown(root.dispose);

      expect(
        () => root.plugin('bad', (ctx) {
          ctx.provide('temp', 1);
          throw StateError('install failed');
        }),
        throwsStateError,
      );

      expect(root.has('temp'), isFalse);
    });

    test('卸载父上下文会级联执行所有子孙的撤销函数', () {
      final root = Context.root();
      final log = <String>[];

      root.plugin('a', (a) {
        a.onDispose(() => log.add('a'));
        a.plugin('b', (b) {
          b.onDispose(() => log.add('b'));
          b.plugin('c', (c) {
            c.onDispose(() => log.add('c'));
          });
        });
      });

      root.dispose();

      expect(log, containsAll(<String>['a', 'b', 'c']));
    });
  });
}

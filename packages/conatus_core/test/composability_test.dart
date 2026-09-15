import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

void main() {
  group('inject — 依赖激活与停用', () {
    test('依赖满足时立即激活', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('logger', 'L');

      var activated = false;
      root.inject(<String>['logger'], (_) => activated = true);

      expect(activated, isTrue);
    });

    test('依赖不满足时不激活', () {
      final root = Context.root();
      addTearDown(root.dispose);

      var activated = false;
      root.inject(<String>['logger'], (_) => activated = true);

      expect(activated, isFalse);
    });

    test('依赖后到时激活', () {
      final root = Context.root();
      addTearDown(root.dispose);

      var activated = false;
      root.inject(<String>['logger'], (_) => activated = true);
      expect(activated, isFalse);

      root.provide('logger', 'L');
      expect(activated, isTrue);
    });

    test('依赖消失时停用，回调中的效应被撤销', () {
      final root = Context.root();
      addTearDown(root.dispose);

      final stop = root.provide('logger', 'L');
      var activated = false;
      var deactivated = false;

      root.inject(<String>['logger'], (child) {
        activated = true;
        child.onDispose(() => deactivated = true);
      });

      expect(activated, isTrue);
      expect(deactivated, isFalse);

      stop();

      expect(deactivated, isTrue);
    });

    test('重新激活会创建全新的子上下文', () {
      final root = Context.root();
      addTearDown(root.dispose);

      final stop = root.provide('logger', 'L');
      final contexts = <Context>[];
      root.inject(<String>['logger'], contexts.add);

      stop();
      root.provide('logger', 'L2');

      expect(contexts, hasLength(2));
      expect(identical(contexts[0], contexts[1]), isFalse);
    });

    test('多依赖需要全部满足', () {
      final root = Context.root();
      addTearDown(root.dispose);

      var activated = false;
      root.provide('a', 1);
      root.inject(<String>['a', 'b'], (_) => activated = true);
      expect(activated, isFalse);

      root.provide('b', 2);
      expect(activated, isTrue);
    });

    test('返回的 Disposer 可手动取消注入', () {
      final root = Context.root();
      addTearDown(root.dispose);

      root.provide('logger', 'L');
      var deactivated = false;

      final cancel = root.inject(<String>['logger'], (child) {
        child.onDispose(() => deactivated = true);
      });

      cancel();

      expect(deactivated, isTrue);
      // 取消注入不影响被依赖的服务本身
      expect(root.has('logger'), isTrue);
    });

    test('宿主上下文释放会撤销所有注入', () {
      final root = Context.root();
      root.provide('logger', 'L');

      var deactivated = false;
      final plugin = root.plugin('p', (ctx) {
        ctx.inject(<String>['logger'], (child) {
          child.onDispose(() => deactivated = true);
        });
      });

      plugin.dispose();

      expect(deactivated, isTrue);
      root.dispose();
    });

    test('注入回调抛异常不会传播到 notify 调用者，但会被回滚', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('x', 1);

      var childDisposed = false;

      runZonedGuarded(
        () {
          root.inject(<String>['x'], (child) {
            child.onDispose(() => childDisposed = true);
            throw StateError('boom');
          });
        },
        (error, stack) {
          expect(error, isA<StateError>());
        },
      );

      expect(childDisposed, isTrue);
    });

    test('重复依赖会被去重', () {
      final root = Context.root();
      addTearDown(root.dispose);
      root.provide('a', 1);

      var count = 0;
      root.inject(<String>['a', 'a', 'a'], (_) => count++);

      expect(count, 1);
    });
  });

  group('时空可组合性 — 级联', () {
    test('卸载服务提供者插件导致依赖者停用', () {
      final root = Context.root();
      addTearDown(root.dispose);
      final container = root.plugin('container', (_) {});

      final provider = container.plugin(
        'provider',
        (ctx) => ctx.provide('service', 42),
      );
      expect(container.has('service'), isFalse);
      // 服务在 provider 上下文内提供，对 container 不可见 —— 这是设计预期
      expect(provider.has('service'), isTrue);

      // 在 provider 内部注入依赖者
      var deactivated = false;
      provider.inject(<String>['service'], (child) {
        child.onDispose(() => deactivated = true);
      });

      provider.dispose();

      expect(deactivated, isTrue);
    });

    test('父上下文卸载导致子上下文的 inject 停用', () {
      final root = Context.root();
      addTearDown(root.dispose);

      var deactivated = false;

      final a = root.plugin('A', (ctx) {
        ctx.provide('service', 42);
        ctx.plugin('B', (child) {
          child.inject(<String>['service'], (grand) {
            grand.onDispose(() => deactivated = true);
          });
        });
      });

      a.dispose();

      expect(deactivated, isTrue);
    });

    test('两级级联：x 消失 → B 停用 → B 提供的 y 也随之消失', () {
      final root = Context.root();
      addTearDown(root.dispose);
      final log = <String>[];

      final a = root.plugin('A', (ctx) => ctx.provide('x', 1));

      a.plugin('B', (ctx) {
        ctx.inject(<String>['x'], (child) {
          log.add('B.activate');
          child.provide('y', 2);
          child.onDispose(() => log.add('B.deactivate'));
        });
      });

      expect(log, <String>['B.activate']);

      a.dispose();

      expect(log, <String>['B.activate', 'B.deactivate']);
      expect(root.has('x'), isFalse);
    });

    test('服务重新出现时依赖者以新上下文重新激活', () {
      final root = Context.root();
      addTearDown(root.dispose);

      final log = <String>[];
      final stop = root.provide('dep', 1);

      root.inject(<String>['dep'], (child) {
        log.add('activate');
        child.onDispose(() => log.add('deactivate'));
      });

      stop();
      expect(log, <String>['activate', 'deactivate']);

      root.provide('dep', 2);
      expect(log, <String>['activate', 'deactivate', 'activate']);
    });
  });

  group('异步场景', () {
    test('异步完成后迟到登记清理函数会被立即执行', () async {
      final ctx = Context.root();
      ctx.dispose();

      var cleaned = false;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      ctx.track(() => cleaned = true);

      expect(cleaned, isTrue);
    });

    test('异步初始化期间 context 被释放，服务不会泄漏', () async {
      final root = Context.root();
      addTearDown(root.dispose);

      final plugin = root.plugin('async', (ctx) async {
        // 模拟异步初始化
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (ctx.disposed) return;
        ctx.provide('late', 1);
      });

      plugin.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(plugin.has('late'), isFalse);
    });
  });
}

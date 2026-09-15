import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('timeout', () {
    test('延迟后执行一次', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var count = 0;

      ctx.timeout(() => count++, const Duration(milliseconds: 20));
      expect(count, 0);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);
    });

    test('返回的 Disposer 可提前取消', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var fired = false;

      final Disposer stop =
          ctx.timeout(() => fired = true, const Duration(milliseconds: 30));
      stop();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, isFalse);
    });

    test('上下文释放会取消未触发的定时器', () async {
      final ctx = Context.root();
      var fired = false;

      ctx.timeout(() => fired = true, const Duration(milliseconds: 30));
      ctx.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, isFalse);
    });
  });

  group('interval', () {
    test('反复触发，释放后停止', () async {
      final ctx = Context.root();
      var count = 0;

      ctx.interval(() => count++, const Duration(milliseconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(count, greaterThanOrEqualTo(2));

      ctx.dispose();
      final int frozen = count;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(count, frozen);
    });
  });

  group('sleep', () {
    test('到期后完成', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      await ctx.sleep(const Duration(milliseconds: 20));
      expect(ctx.disposed, isFalse);
    });

    test('上下文先释放则以 StateError 结束', () async {
      final ctx = Context.root();
      final Future<void> future = ctx.sleep(const Duration(seconds: 5));

      ctx.dispose();
      await expectLater(future, throwsStateError);
    });
  });

  group('throttle', () {
    test('窗口内只执行一次，结束时补执行', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var count = 0;

      final Throttled throttled =
          ctx.throttle(() => count++, const Duration(milliseconds: 40));
      throttled();
      throttled();
      throttled();
      expect(count, 1);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(count, 2);
    });

    test('trailing: false 时丢弃窗口内的后续调用', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var count = 0;

      final Throttled throttled = ctx.throttle(
        () => count++,
        const Duration(milliseconds: 40),
        trailing: false,
      );
      throttled();
      throttled();
      expect(count, 1);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(count, 1);
    });
  });

  group('debounce', () {
    test('静默期后才执行一次', () async {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var count = 0;

      final Debounced debounced =
          ctx.debounce(() => count++, const Duration(milliseconds: 30));
      debounced();
      debounced();
      debounced();
      expect(count, 0);

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(count, 1);
    });
  });
}

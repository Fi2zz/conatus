import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

void main() {
  group('Reactor', () {
    test('基础广播', () {
      final reactor = Reactor();
      var count = 0;
      reactor.add(() => count++);

      reactor.notify();

      expect(count, 1);
    });

    test('多个监听器都会被调用', () {
      final reactor = Reactor();
      final order = <String>[];
      reactor.add(() => order.add('a'));
      reactor.add(() => order.add('b'));

      reactor.notify();

      expect(order, <String>['a', 'b']);
    });

    test('重入会触发额外一轮', () {
      final reactor = Reactor();
      var count = 0;
      reactor.add(() {
        count++;
        if (count == 1) reactor.notify();
      });

      reactor.notify();

      expect(count, 2);
    });

    test('remove 移除监听器', () {
      final reactor = Reactor();
      var count = 0;
      void listener() => count++;

      reactor.add(listener);
      reactor.remove(listener);
      reactor.notify();

      expect(count, 0);
    });

    test('remove 返回是否成功移除', () {
      final reactor = Reactor();
      void listener() {}

      reactor.add(listener);
      expect(reactor.remove(listener), isTrue);
      expect(reactor.remove(listener), isFalse);
    });

    test('无法收敛时抛 StateError', () {
      final reactor = Reactor(maxRounds: 5);
      reactor.add(reactor.notify);

      expect(reactor.notify, throwsStateError);
    });

    test('抛出后 reactor 仍可复用', () {
      final reactor = Reactor(maxRounds: 3);
      void bad() => reactor.notify();
      reactor.add(bad);

      expect(reactor.notify, throwsStateError);

      reactor.remove(bad);
      var count = 0;
      reactor.add(() => count++);
      reactor.notify();
      expect(count, 1);
    });

    test('构造时校验 maxRounds', () {
      expect(() => Reactor(maxRounds: 0), throwsArgumentError);
      expect(() => Reactor(maxRounds: -1), throwsArgumentError);
    });

    test('isRunning 在广播期间为 true', () {
      final reactor = Reactor();
      bool? during;
      reactor.add(() => during = reactor.isRunning);

      reactor.notify();

      expect(during, isTrue);
      expect(reactor.isRunning, isFalse);
    });

    test('监听器在回调中修改列表不会引发并发修改异常', () {
      final reactor = Reactor();
      void extra() {}
      reactor.add(() => reactor.remove(extra));
      reactor.add(extra);

      expect(reactor.notify, returnsNormally);
    });
  });
}

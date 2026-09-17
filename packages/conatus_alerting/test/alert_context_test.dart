import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

void main() {
  group('AlertContext（注入时钟）', () {
    late DateTime now;
    late AlertContext ctx;

    setUp(() {
      now = DateTime(2026, 9, 17, 10);
      ctx = AlertContext(now: () => now);
    });

    test('未触发过不冷却', () {
      expect(ctx.isCoolingDown('llm-slow'), isFalse);
    });

    test('标记触发后进入冷却，冷却期过后解除', () {
      ctx.registerCooldown('llm-slow', const Duration(minutes: 5));
      ctx.markFired('llm-slow');

      now = now.add(const Duration(minutes: 3));
      expect(ctx.isCoolingDown('llm-slow'), isTrue);

      now = now.add(const Duration(minutes: 3));
      expect(ctx.isCoolingDown('llm-slow'), isFalse);
    });

    test('未注册冷却期的规则用默认 5 分钟', () {
      ctx.markFired('unknown');
      now = now.add(const Duration(minutes: 4));
      expect(ctx.isCoolingDown('unknown'), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(ctx.isCoolingDown('unknown'), isFalse);
    });

    test('窗口计数只统计窗口内的事件', () {
      ctx.record('tool.failed');
      now = now.add(const Duration(seconds: 30));
      ctx.record('tool.failed');

      expect(ctx.countInWindow('tool.failed', const Duration(minutes: 1)), 2);

      now = now.add(const Duration(seconds: 40));
      expect(ctx.countInWindow('tool.failed', const Duration(minutes: 1)), 1);
    });

    test('prune 清理过期记录并移除空键', () {
      ctx.record('tool.failed');
      now = now.add(const Duration(hours: 2));
      ctx.prune();

      expect(ctx.countInWindow('tool.failed', const Duration(hours: 1)), 0);
    });
  });
}

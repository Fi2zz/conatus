import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('provideTimePrompt — 时间锚点', () {
    test('注册日期 + 星期 + 时区，精确到日', () {
      final Context ctx = Context.root();
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      // 用 UTC 时刻注入，偏移固定为 +00:00，断言不受运行环境时区影响。
      provideTimePrompt(
        ctx,
        prompt: prompt,
        clock: () => DateTime.utc(2026, 9, 16, 6, 3, 22),
        zoneName: 'Asia/Shanghai',
      );

      expect(prompt.contexts.single.name, kTimeContextName);
      expect(
        prompt.assemble().contexts.single.text,
        '[当前时间]\n2026-09-16 周三 · Asia/Shanghai (UTC+00:00)',
      );
    });

    test('provider 每轮重新求值，跨天自动更新', () {
      final Context ctx = Context.root();
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      DateTime day = DateTime.utc(2026, 9, 16);
      provideTimePrompt(
        ctx,
        prompt: prompt,
        clock: () => day,
        zoneName: 'UTC',
      );

      expect(prompt.renderContexts(prompt.assemble()), contains('2026-09-16'));

      day = DateTime.utc(2026, 9, 17);
      expect(prompt.renderContexts(prompt.assemble()), contains('2026-09-17'));
    });

    test('缺省时区名取本地时区名', () {
      final Context ctx = Context.root();
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      provideTimePrompt(ctx, prompt: prompt, clock: () => DateTime.utc(2026));

      final String text = prompt.assemble().contexts.single.text;

      expect(text, startsWith('[当前时间]\n2026-01-01'));
      expect(text, contains('(UTC+00:00)'));
    });

    test('撤销后不再贡献内容', () {
      final Context ctx = Context.root();
      final SystemPrompt prompt = provideSystemPrompt(ctx);
      final Disposer off = provideTimePrompt(ctx, prompt: prompt);

      off();

      expect(prompt.contexts, isEmpty);
      expect(prompt.renderContexts(prompt.assemble()), isEmpty);
    });
  });

  group('formatClockOffset', () {
    test('按符号与时分格式化', () {
      expect(formatClockOffset(const Duration(hours: 8)), '+08:00');
      expect(
        formatClockOffset(const Duration(hours: -5, minutes: -30)),
        '-05:30',
      );
      expect(formatClockOffset(Duration.zero), '+00:00');
    });
  });
}

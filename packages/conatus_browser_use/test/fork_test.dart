import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/mock_provider.dart';

void main() {
  group('fork 语义', () {
    test('fork 出新 Session 创建全新浏览器，登录状态不恢复', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      final Session s1 = Session(id: 's1');
      provideBrowserUse(ctx, provider: provider, session: s1);
      await pumpEventQueue();
      expect(provider.initialized, hasLength(1));

      final Session s2 = s1.fork();
      s1.close(); // 释放旧 Session 的浏览器，腾出工具名
      await pumpEventQueue();

      final SessionBrowser browser2 = await initializeBrowserFor(ctx, s2);
      expect(browser2.sessionId, s2.id);
      expect(provider.initialized, hasLength(2));
      expect(provider.initialized.last, s2);
      expect(provider.released, contains(s1));

      // 新 Session 的工具重新可用
      final ToolResult result =
          await ctx.tools.call(const ToolCall(name: 'browser_navigate'));
      expect(result.isError, isFalse);
    });

    test('旧 Session 未释放时初始化新 Session 因工具同名失败', () async {
      final Context ctx = Context.root();
      provideTools(ctx);
      final MockBrowserUseProvider provider = MockBrowserUseProvider();
      final Session s1 = Session(id: 's1');
      provideBrowserUse(ctx, provider: provider, session: s1);
      await pumpEventQueue();

      final Session s2 = s1.fork();
      await expectLater(
        initializeBrowserFor(ctx, s2),
        throwsStateError,
        reason: '同一时刻仅一个 Session 可持有浏览器工具（handoff 4.2）',
      );
    });
  });
}

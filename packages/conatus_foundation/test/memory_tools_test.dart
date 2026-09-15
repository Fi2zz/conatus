import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryStore 显式遗忘', () {
    test('forgetByText 精确匹配删除全部相同正文', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('咖啡');
      await store.remember('咖啡');
      await store.remember('茶');

      expect(await store.forgetByText('咖啡'), 2);
      expect(store.entries.map((MemoryEntry e) => e.text), <String>['茶']);
      expect(await store.forgetByText('咖啡'), 0);
    });

    test('forgetMatching 包含匹配且不区分大小写', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('用户喜欢京剧');
      await store.remember('用户喜欢旅游');

      expect(await store.forgetMatching('京剧'), 1);
      expect(await store.forgetMatching('用户'), 1);
      expect(store.length, 0);
    });

    test('forgetMatching 空关键字不删除', () async {
      final MemoryStore store = MemoryStore();
      await store.remember('x');
      expect(await store.forgetMatching('   '), 0);
      expect(store.length, 1);
    });
  });

  group('remember / forget 工具', () {
    test('remember 写入并可召回', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      final MemoryStore store = provideMemory(ctx);
      provideMemoryTools(ctx);

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'remember',
        arguments: <String, Object?>{
          'text': '用户喜欢京剧',
          'tags': <Object?>['偏好'],
        },
      ));

      expect(result.isError, isFalse);
      expect(store.recall('京剧').single.text, '用户喜欢京剧');
      expect(store.entries.single.tags, <String>{'偏好'});
    });

    test('remember 空文本失败', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      provideMemory(ctx);
      provideMemoryTools(ctx);

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'remember',
        arguments: <String, Object?>{'text': '  '},
      ));
      expect(result.isError, isTrue);
      expect(result.error!.code, 'EMPTY_TEXT');
    });

    test('forget 按 id 删除', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      final MemoryStore store = provideMemory(ctx);
      provideMemoryTools(ctx);
      final MemoryEntry entry = await store.remember('待删');

      final ToolResult result = await ctx.tools.call(ToolCall(
        name: 'forget',
        arguments: <String, Object?>{'id': entry.id},
      ));

      expect(result.isError, isFalse);
      expect(store.length, 0);
    });

    test('forget 按关键字删除', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      final MemoryStore store = provideMemory(ctx);
      provideMemoryTools(ctx);
      await store.remember('用户喜欢京剧');
      await store.remember('用户喜欢旅游');

      final ToolResult result = await ctx.tools.call(const ToolCall(
        name: 'forget',
        arguments: <String, Object?>{'text': '京剧'},
      ));

      expect(result.isError, isFalse);
      expect(result.value, <String, Object?>{'deleted': 1});
      expect(store.entries.single.text, '用户喜欢旅游');
    });

    test('forget 未命中与参数不合法都失败', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      provideMemory(ctx);
      provideMemoryTools(ctx);

      final ToolResult missing = await ctx.tools.call(const ToolCall(
        name: 'forget',
        arguments: <String, Object?>{'id': 'nope'},
      ));
      expect(missing.error!.code, 'MEMORY_NOT_FOUND');

      final ToolResult both = await ctx.tools.call(const ToolCall(
        name: 'forget',
        arguments: <String, Object?>{'id': 'a', 'text': 'b'},
      ));
      expect(both.error!.code, 'INVALID_ARGS');

      final ToolResult neither =
          await ctx.tools.call(const ToolCall(name: 'forget'));
      expect(neither.error!.code, 'INVALID_ARGS');
    });
  });

  group('提供器', () {
    test('provideRememberTool / provideForgetTool 分别注册', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      provideTools(ctx);
      provideMemory(ctx);
      final ToolRegistry tools = ctx.tools;

      final List<Tool> remember = provideRememberTool(ctx);
      expect(remember.single.name, 'remember');
      expect(tools.get('remember'), isNotNull);

      final List<Tool> forget = provideForgetTool(ctx);
      expect(forget.single.name, 'forget');
      expect(tools.get('forget'), isNotNull);

      ctx.dispose();
      expect(tools.get('remember'), isNull);
    });
  });
}

import 'dart:convert';

import 'package:conatus_context/conatus_context.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late CcrMemoryStore store;

  setUp(() => store = CcrMemoryStore());

  Future<ToolResult> call(Map<String, Object?> args) =>
      ContextRetrievalTool(store).call(
        ToolContext(
          ToolCall(name: 'context_retrieve', arguments: args),
        ),
      );

  test('按 id 取回原文并返回元数据', () async {
    final String id = await store.put('0123456789');
    final ToolResult r = await call(<String, Object?>{'id': id});
    expect(r.isError, false);
    expect(r.content, '0123456789');
    final Map<String, Object?> value = r.value! as Map<String, Object?>;
    expect(value['chars'], 10);
    expect(value['truncated'], false);
  });

  test('offset 与 limit 正确切片，越界不崩溃', () async {
    final String id = await store.put('abcdefghij');
    expect(
      (await call(<String, Object?>{'id': id, 'offset': 2, 'limit': 3}))
          .content,
      'cde',
    );
    expect(
      (await call(<String, Object?>{'id': id, 'offset': -5})).content,
      'abcdefghij',
    );
    final ToolResult beyond =
        await call(<String, Object?>{'id': id, 'offset': 100});
    expect(beyond.isError, true);
    expect(beyond.error!.code, 'ccr_offset');
    expect(
      (await call(<String, Object?>{'id': id, 'limit': 0})).content,
      'abcdefghij',
    );
  });

  test('编造 id 返回可读失败而非异常', () async {
    final ToolResult r =
        await call(<String, Object?>{'id': 'ffffffffffffffff'});
    expect(r.isError, true);
    expect(r.content, contains('未找到'));
    expect(r.error!.code, 'ccr_miss');
  });

  test('stats 工具输出 estimated 标记', () async {
    final ToolResult r = await ContextStatsTool(CompressionStats())
        .call(const ToolContext(ToolCall(name: 'context_stats')));
    expect(jsonDecode(r.content)['estimated'], true);
  });
}

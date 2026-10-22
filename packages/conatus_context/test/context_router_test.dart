import 'dart:convert';

import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

class _FakeCompressor implements ContentCompressor {
  _FakeCompressor({this.kind = ContentKind.text});

  @override
  final ContentKind kind;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      const CompressionDraft('压缩后', itemsOmitted: 90);
}

class _IdentityCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      CompressionDraft(input);
}

class _ThrowingCompressor implements ContentCompressor {
  @override
  ContentKind get kind => ContentKind.text;

  @override
  CompressionDraft? compress(String input, CompressionBudget budget) =>
      throw StateError('boom');
}

ContextRouter _router({
  Set<String> protectedTools = const <String>{},
  Set<ContentKind> disabledKinds = const <ContentKind>{},
  List<ContentCompressor>? compressors,
}) =>
    ContextRouter(
      config: ContextCompressionConfig(
        minChars: 10,
        protectedTools: protectedTools,
        disabledKinds: disabledKinds,
      ),
      store: CcrMemoryStore(),
      compressors: compressors ?? <ContentCompressor>[_FakeCompressor()],
    );

void main() {
  test('低于最小尺寸直接透传', () async {
    final ContextRouter router = _router();
    final ContextCompressionResult r =
        await router.compress('short', toolName: 't');
    expect(r.applied, false);
    expect(r.skippedReason, 'tooSmall');
  });

  test('保护工具与禁用类型透传', () async {
    final ContextRouter router = _router(protectedTools: {'secret'});
    expect(
      (await router.compress(List<String>.filled(100, 'x').join(),
              toolName: 'secret'))
          .skippedReason,
      'protected',
    );
    final ContextRouter disabled =
        _router(disabledKinds: <ContentKind>{ContentKind.jsonArray});
    final ContextCompressionResult r = await disabled.compress(
        jsonEncode(
            List<Map<String, Object?>>.filled(5, <String, Object?>{'a': 1})),
        toolName: 't');
    expect(r.skippedReason, 'disabled');
  });

  test('已含标记的输入不再压缩', () async {
    final ContextRouter router = _router();
    final ContextCompressionResult r = await router.compress(
        '${List<String>.filled(100, 'x').join()} '
        '<<ctx:0123456789abcdef 1_items_omitted>>',
        toolName: 't');
    expect(r.skippedReason, 'alreadyCompressed');
  });

  test('应用压缩时存入原文并注入标记', () async {
    final ContextRouter router = _router(compressors: <ContentCompressor>[
      _FakeCompressor(kind: ContentKind.jsonArray),
    ]);
    final String input = jsonEncode(
        List<Map<String, Object?>>.filled(50, <String, Object?>{'a': 'b'}));
    final ContextCompressionResult r =
        await router.compress(input, toolName: 't');
    expect(r.applied, true);
    expect(r.content, contains('<<ctx:'));
    expect(r.ccrId, isNotNull);
    expect(await router.store.get(r.ccrId!), input);
    expect(router.stats.ccrStored, 1);
    expect(router.stats.applied, 1);
  });

  test('压缩器抛错时 fail-open 并计数', () async {
    final ContextRouter router =
        _router(compressors: <ContentCompressor>[_ThrowingCompressor()]);
    final String input = List<String>.filled(1000, 'x').join();
    final ContextCompressionResult r =
        await router.compress(input, toolName: 't');
    expect(r.applied, false);
    expect(r.content, input);
    expect(r.skippedReason, 'error');
    expect(router.stats.failures, 1);
  });

  test('收益不足回退原文', () async {
    final ContextRouter router =
        _router(compressors: <ContentCompressor>[_IdentityCompressor()]);
    final ContextCompressionResult r = await router
        .compress(List<String>.filled(1000, 'x').join(), toolName: 't');
    expect(r.applied, false);
    expect(r.skippedReason, 'noSaving');
  });

  test('关闭 CCR 时不注入标记', () async {
    final ContextRouter router = ContextRouter(
      config: const ContextCompressionConfig(minChars: 10, ccrEnabled: false),
      store: CcrMemoryStore(),
      compressors: <ContentCompressor>[
        _FakeCompressor(kind: ContentKind.jsonArray),
      ],
    );
    final String input = jsonEncode(
        List<Map<String, Object?>>.filled(50, <String, Object?>{'a': 'b'}));
    final ContextCompressionResult r =
        await router.compress(input, toolName: 't');
    expect(r.applied, true);
    expect(r.content, isNot(contains('<<ctx:')));
    expect(r.ccrId, isNull);
  });
}

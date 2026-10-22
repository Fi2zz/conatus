/// 压缩路由：检测类型、执行安全门、存 CCR、注入标记、统计与 fail-open。
library;

import 'ccr_marker.dart';
import 'ccr_store.dart';
import 'compression_result.dart';
import 'compression_stats.dart';
import 'content_compressor.dart';
import 'content_detector.dart';
import 'content_kind.dart';
import 'context_compression_config.dart';
import 'default_compressors.dart';

/// 单条内容的压缩入口。
class ContextRouter {
  ContextRouter({
    required this.config,
    required this.store,
    Detector? detector,
    List<ContentCompressor>? compressors,
    CompressionStats? stats,
  })  : detector = detector ?? detectContent,
        stats = stats ?? CompressionStats(),
        _compressors = <ContentKind, ContentCompressor>{
          for (final ContentCompressor compressor
              in compressors ?? defaultContentCompressors())
            compressor.kind: compressor,
        };

  /// 配置。
  final ContextCompressionConfig config;

  /// CCR 存储。
  final CcrStore store;

  /// 检测器。
  final Detector detector;

  /// 统计。
  final CompressionStats stats;

  final Map<ContentKind, ContentCompressor> _compressors;

  /// 压缩一条内容；任何失败都返回原文。
  Future<ContextCompressionResult> compress(
    String input, {
    required String toolName,
    bool conservative = false,
  }) async {
    if (!config.enabled) {
      return _skip(input, ContentKind.text, 'disabled');
    }
    if (input.isEmpty) return _skip(input, ContentKind.text, 'empty');
    final ContentKind kind;
    try {
      kind = detector(input).kind;
    } on Object {
      stats.recordFailure(ContentKind.text);
      return _skip(input, ContentKind.text, 'error');
    }
    if (config.protectedTools.contains(toolName)) {
      return _skip(input, kind, 'protected');
    }
    if (input.length < config.minChars) {
      return _skip(input, kind, 'tooSmall');
    }
    if (containsCcrMarker(input)) {
      return _skip(input, kind, 'alreadyCompressed');
    }
    if (_kindDisabled(kind)) return _skip(input, kind, 'disabled');
    final ContentCompressor? compressor = _compressors[kind];
    if (compressor == null) return _skip(input, kind, 'disabled');
    return _attempt(compressor, input, kind, conservative);
  }

  Future<ContextCompressionResult> _attempt(
    ContentCompressor compressor,
    String input,
    ContentKind kind,
    bool conservative,
  ) async {
    try {
      return await _run(compressor, input, kind, conservative);
    } on Object {
      stats.recordFailure(kind);
      return _skip(input, kind, 'error');
    }
  }

  bool _kindDisabled(ContentKind kind) =>
      kind == ContentKind.sourceCode ||
      kind == ContentKind.passthrough ||
      config.disabledKinds.contains(kind);

  Future<ContextCompressionResult> _run(
    ContentCompressor compressor,
    String input,
    ContentKind kind,
    bool conservative,
  ) async {
    final CompressionBudget budget = _budget(kind, input, conservative);
    final CompressionDraft? draft;
    try {
      draft = compressor.compress(input, budget);
    } on Object {
      stats.recordFailure(kind);
      return _skip(input, kind, 'error');
    }
    if (draft == null) return _skip(input, kind, 'noSaving');
    return _apply(input, kind, draft, budget);
  }

  Future<ContextCompressionResult> _apply(
    String input,
    ContentKind kind,
    CompressionDraft draft,
    CompressionBudget budget,
  ) async {
    String content = draft.output;
    final bool wantsMarker = draft.itemsOmitted > 0 && config.ccrEnabled;
    if (wantsMarker && !containsCcrMarker(content)) {
      content = '$content\n'
          '${encodeCcrMarker(budget.retrievalId, draft.itemsOmitted, draft.unit)}';
    }
    final double ratio = content.length / input.length;
    if (ratio > 1 - config.minSavingRatio) {
      return _skip(input, kind, 'noSaving');
    }
    final bool stored = wantsMarker;
    if (stored) await store.put(input);
    final ContextCompressionResult result = ContextCompressionResult(
      applied: true,
      kind: kind,
      content: content,
      beforeChars: input.length,
      afterChars: content.length,
      ccrId: stored ? budget.retrievalId : null,
    );
    stats.record(result, ccrStored: stored);
    config.onCompressed?.call(result);
    return result;
  }

  CompressionBudget _budget(
    ContentKind kind,
    String input,
    bool conservative,
  ) =>
      CompressionBudget(
        maxItems: kind == ContentKind.tabular
            ? config.maxTableRows
            : config.maxJsonItems,
        maxLines: _maxLines(kind),
        maxFiles: config.maxSearchFiles,
        targetRatio: config.textTargetRatio,
        retrievalId: config.ccrEnabled ? ccrIdOf(input) : '',
        conservative: conservative,
      );

  int _maxLines(ContentKind kind) => switch (kind) {
        ContentKind.buildLog => config.maxLogLines,
        ContentKind.searchResults => config.maxSearchLines,
        ContentKind.diff => config.maxDiffLines,
        ContentKind.tabular => config.maxTableRows,
        _ => config.maxLogLines,
      };

  ContextCompressionResult _skip(
    String input,
    ContentKind kind,
    String reason,
  ) {
    final ContextCompressionResult result = ContextCompressionResult.skipped(
        input: input, kind: kind, reason: reason);
    stats.record(result);
    return result;
  }
}

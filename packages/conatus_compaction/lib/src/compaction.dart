/// compaction 插件：把会话日志里较早的事件汇总成滚动摘要。
///
/// 服务键 `'compaction'`。汇总器由调用方注入（通常是 `llm` 插件），本插件只负责
/// 预算判断、切点安全、摘要记忆与日志记录。日志本身不被改写：被折叠的事件仍在
/// 日志里，压缩只是在末尾追加三个记录事件，使「发给模型的这段摘要从哪来」可以
/// 从日志重建。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'compaction_engine.dart';
import 'compaction_tool_pairing.dart';
import 'compaction_types.dart';

/// 一次压缩的进行态：身份、开始事件、切点、保留条数与上一版摘要。
typedef _Txn = ({
  CompactionId id,
  SessionEvent start,
  int cut,
  int kept,
  String previous,
});

/// 基础压缩器：按预算折叠较早事件。
class Compactor implements CompactionEngine {
  Compactor({this.keepRecent = 20}) {
    if (keepRecent < 0) {
      throw ArgumentError.value(keepRecent, 'keepRecent', '必须是非负整数');
    }
  }

  @override
  final int keepRecent;

  final Map<String, String> _summaries = <String, String>{};

  @override
  String? summaryOf(String sessionId) => _summaries[sessionId];

  @override
  void forget(String sessionId) => _summaries.remove(sessionId);

  @override
  Future<CompactionResult?> compactIfNeeded(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  }) async {
    final int keep = keepRecent ?? this.keepRecent;
    final int total = session.length;
    final int cut = balancedCutAtOrBefore(session, total - keep);
    if (cut <= 0) return null;
    final CompactionId id = nextCompactionId();
    final SessionEvent start = session.append(kCompactionStartEvent,
        data: <String, Object?>{'compactionId': id, 'keepRecent': keep});
    final _Txn txn = (
      id: id,
      start: start,
      cut: cut,
      kept: total - cut,
      previous: _summaries[session.id] ?? '',
    );
    try {
      return await _commit(session, txn, summarize);
    } catch (error) {
      session.append(kCompactionEndEvent,
          data: <String, Object?>{'compactionId': id, 'error': '$error'});
      rethrow;
    }
  }

  /// 把待折叠的事件交给汇总器；分层压缩器覆盖它来按类别整理。
  Future<CompactionSummary> summarizeFolded(
    CompactionFold fold,
    Summarizer summarize,
  ) =>
      summarize(fold.events, fold.previous);

  Future<CompactionResult> _commit(
    Session session,
    _Txn txn,
    Summarizer summarize,
  ) async {
    final List<SessionEvent> folded = session.events.sublist(0, txn.cut);
    final CompactionSummary summary = await summarizeFolded(
      CompactionFold(events: folded, previous: txn.previous, kept: txn.kept),
      summarize,
    );
    final List<int> shadowed = <int>[
      for (final SessionEvent event in folded) event.seq,
    ];
    final SessionEvent record = session.append(kCompactionSummaryEvent,
        data: _summaryPayload(txn, summary, shadowed));
    final SessionEvent end = session.append(kCompactionEndEvent,
        data: <String, Object?>{'compactionId': txn.id});
    _summaries[session.id] = summary.text;
    return CompactionResult(
      compactionId: txn.id,
      startSeq: txn.start.seq,
      summarySeq: record.seq,
      endSeq: end.seq,
      summary: summary.text,
      shadowedSeqs: shadowed,
      kept: txn.kept,
    );
  }

  Map<String, Object?> _summaryPayload(
    _Txn txn,
    CompactionSummary summary,
    List<int> shadowed,
  ) =>
      <String, Object?>{
        'compactionId': txn.id,
        'summary': summary.text,
        'shadowedSeqs': shadowed,
        'kept': txn.kept,
        if (summary.provider != null) 'provider': summary.provider,
        if (summary.model != null) 'model': summary.model,
      };
}

/// 把压缩器作为 `'compaction'` 服务提供到上下文。
CompactionEngine provideCompaction(Context ctx, {CompactionEngine? engine}) {
  final CompactionEngine resolved = engine ?? Compactor();
  ctx.provide('compaction', resolved);
  return resolved;
}

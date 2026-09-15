/// compaction 插件：把会话日志中较早的事件汇总成滚动摘要。
///
/// 服务键 `'compaction'`。汇总器由调用方注入（通常是 `llm` 插件），本插件
/// 只负责预算判断、切片与摘要记忆：会话事件数超过 `keepRecent` 时，把更早的
/// 事件连同上一版摘要交给汇总器，产出新摘要并按会话缓存。日志本身不被改写。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 汇总器：接收待折叠的事件与上一版摘要，返回新摘要。
typedef Summarizer = Future<String> Function(
  List<SessionEvent> events,
  String previousSummary,
);

/// 一次压缩的结局。
class CompactionResult {
  const CompactionResult({
    required this.summary,
    required this.compacted,
    required this.kept,
  });

  /// 产出的滚动摘要。
  final String summary;

  /// 被折叠进摘要的事件数。
  final int compacted;

  /// 保留为原始日志的最近事件数。
  final int kept;
}

/// 会话压缩器：按预算折叠较早事件。
class Compactor {
  Compactor({this.keepRecent = 20}) {
    if (keepRecent < 0) {
      throw ArgumentError.value(keepRecent, 'keepRecent', '必须是非负整数');
    }
  }

  /// 默认保留的最近事件数。
  final int keepRecent;

  final Map<String, String> _summaries = <String, String>{};

  /// 某会话当前的滚动摘要；尚未压缩过时为 `null`。
  String? summaryOf(String sessionId) => _summaries[sessionId];

  /// 丢弃某会话的摘要记忆。
  void forget(String sessionId) => _summaries.remove(sessionId);

  /// 若事件数超过保留数，折叠较早部分并返回结果；否则返回 `null`。
  ///
  /// 汇总器抛错时不更新摘要记忆，异常原样上抛。
  Future<CompactionResult?> compact(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  }) async {
    final int keep = keepRecent ?? this.keepRecent;
    final List<SessionEvent> events = session.events;
    if (events.length <= keep) return null;
    final List<SessionEvent> older = events.sublist(0, events.length - keep);
    final String summary = await summarize(older, _summaries[session.id] ?? '');
    _summaries[session.id] = summary;
    return CompactionResult(
      summary: summary,
      compacted: older.length,
      kept: keep,
    );
  }
}

/// 将 [Compactor] 作为 `'compaction'` 服务提供到上下文。
Compactor provideCompaction(Context ctx, {Compactor? compaction}) {
  final Compactor resolved = compaction ?? Compactor();
  ctx.provide('compaction', resolved);
  return resolved;
}

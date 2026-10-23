import 'rag_chunk.dart';

/// 检索审计事件：记录一次检索的关键指标，不含正文。
class RetrievalAudit {
  const RetrievalAudit({
    required this.tenantId,
    required this.principalId,
    required this.queryLength,
    required this.hitIds,
    required this.tokens,
    required this.elapsedMs,
  });

  final String tenantId;
  final String? principalId;
  final int queryLength;
  final List<String> hitIds;
  final int tokens;
  final int elapsedMs;
}

/// 审计观察者回调类型。
typedef RetrievalObserver = void Function(RetrievalAudit audit);

/// 把命中列表格式化为证据块；空列表返回空串。
///
/// 命中按 `startTime` 升序输出、按 `chunk.id` 去重（保留排序后的首条）；
/// 时间格式 `yyyy-MM-dd HH:mm`，手写补零，不引 intl。
String formatHits(List<RagHit> hits) {
  if (hits.isEmpty) return '';
  final List<RagHit> sorted = List<RagHit>.from(hits)
    ..sort(
        (RagHit a, RagHit b) => a.chunk.startTime.compareTo(b.chunk.startTime));
  final Set<String> seen = <String>{};
  final StringBuffer buf = StringBuffer('[相关历史证据]\n');
  buf.writeln('以下片段来自会话历史原文，按时间升序。据此推导答案；缺失的信息不要臆测。');
  for (final RagHit hit in sorted) {
    if (!seen.add(hit.chunk.id)) continue;
    buf.writeln('- ${_formatCitation(hit)}');
  }
  return buf.toString().trimRight();
}

String _formatCitation(RagHit hit) {
  final DateTime ts = hit.chunk.startTime;
  final String stamp =
      '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)} ${_pad(ts.hour)}:${_pad(ts.minute)}';
  final String? firstSeq = hit.chunk.firstSeq?.toString();
  final String? lastSeq = hit.chunk.lastSeq?.toString();
  final String seq = firstSeq == null
      ? ''
      : ' seq:$firstSeq${lastSeq == null ? '' : '-$lastSeq'}';
  return '[$stamp] (${hit.chunk.sourceKind}:${hit.chunk.sourceId}$seq) ${hit.chunk.text}';
}

String _pad(int n) => n < 10 ? '0$n' : '$n';

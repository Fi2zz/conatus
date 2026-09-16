/// 压缩词汇：交易身份、汇总产出、压缩结果与 `compaction/*` 日志事件名。
///
/// 对应 dsh `packages/compaction/compaction` 的 `brand.ts` 与 `types.ts`。Dart 侧
/// 压缩不重写日志——更早的事件折叠成滚动摘要进入 system，被折叠的事件仍在日志
/// 里——因此三个 `compaction/*` 事件是**纯记录**：它们只记下一次压缩的边界与
/// 输入，不参与消息派生（`deriveAgentMessages` 只认三类消息事件）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 一次压缩交易的稳定身份，贯穿 `start` / `summary` / `end` 三个事件。
typedef CompactionId = String;

int _compactionSeq = 0;

/// 铸一个新的压缩身份（进程内单调，跨会话唯一）。
String nextCompactionId() =>
    'cmp-${DateTime.now().microsecondsSinceEpoch}-${_compactionSeq++}';

/// 压缩开始事件：记录本次压缩的身份与预算。
const String kCompactionStartEvent = 'compaction/start';

/// 压缩摘要事件：记录本次折叠出的摘要与它覆盖的事件。
const String kCompactionSummaryEvent = 'compaction/summary';

/// 压缩结束事件：本次压缩收尾；带 `error` 表示这次压缩失败。
const String kCompactionEndEvent = 'compaction/end';

/// 一次汇总的产出：摘要文本与写它的模型。
class CompactionSummary {
  const CompactionSummary(this.text, {this.provider, this.model});

  /// 摘要文本。
  final String text;

  /// 写摘要的提供方；未知时为 `null`。
  final String? provider;

  /// 写摘要的模型；未知时为 `null`。
  final String? model;
}

/// 汇总器：接收待折叠的事件与上一版摘要，返回本次汇总产出。
typedef Summarizer = Future<CompactionSummary> Function(
  List<SessionEvent> events,
  String previousSummary,
);

/// 一次折叠的输入：待折叠的事件、上一版摘要与本次保留条数。
class CompactionFold {
  const CompactionFold({
    required this.events,
    required this.previous,
    required this.kept,
  });

  /// 待折叠的事件（日志开头的一段）。
  final List<SessionEvent> events;

  /// 上一版滚动摘要；首次压缩时为空串。
  final String previous;

  /// 本次压缩后保留为原文的事件数。
  final int kept;
}

/// 一次压缩的结局。
class CompactionResult {
  const CompactionResult({
    required this.compactionId,
    required this.startSeq,
    required this.summarySeq,
    required this.endSeq,
    required this.summary,
    required this.shadowedSeqs,
    required this.kept,
  });

  /// 本次压缩的身份（与日志中三个事件的 `compactionId` 一致）。
  final CompactionId compactionId;

  /// `compaction/start` 事件的 seq。
  final int startSeq;

  /// `compaction/summary` 事件的 seq。
  final int summarySeq;

  /// `compaction/end` 事件的 seq。
  final int endSeq;

  /// 产出的滚动摘要。
  final String summary;

  /// 被折叠进摘要的事件 seq（按日志顺序）。
  final List<int> shadowedSeqs;

  /// 本次压缩后保留为原文的事件数。
  final int kept;

  /// 被折叠的事件数。
  int get compacted => shadowedSeqs.length;
}

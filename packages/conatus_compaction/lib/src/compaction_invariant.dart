/// 压缩日志不变式：一次压缩的三个事件必须成对、同身份，且 `compaction/summary`
/// 记录的折叠区间确实是日志开头的一段。
///
/// 对应 dsh `packages/compaction/compaction` 的 `invariant.ts`。Dart 侧没有宿主
/// 不变式注册表，改为与 `conatus_agent` 的「模型可见即已记录」一致的纯函数形态：
/// 返回违规描述列表，另配一个开发模式断言。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'compaction_types.dart';

/// 一次压缩的进行态。
class _Txn {
  String? id;
  bool summarized = false;
}

/// 检查日志里的压缩事件，返回全部违规描述（空列表表示通过）。
List<String> checkCompactionInvariant(Iterable<SessionEvent> events) {
  final List<SessionEvent> all = List<SessionEvent>.of(events);
  final List<String> violations = <String>[];
  final _Txn txn = _Txn();
  for (final SessionEvent event in all) {
    _checkEvent(txn, event, all, violations);
  }
  _checkClosed(txn, violations);
  return violations;
}

/// 断言不变式，违规时抛 [StateError]（开发模式使用，生产可不启用）。
void assertCompactionInvariant(Iterable<SessionEvent> events) {
  final List<String> violations = checkCompactionInvariant(events);
  if (violations.isEmpty) return;
  throw StateError('压缩日志不变式被破坏：\n${violations.join('\n')}');
}

void _checkEvent(
  _Txn txn,
  SessionEvent event,
  List<SessionEvent> all,
  List<String> violations,
) {
  switch (event.type) {
    case kCompactionStartEvent:
      _checkStart(txn, event, violations);
    case kCompactionSummaryEvent:
      _checkSummary(txn, event, all, violations);
    case kCompactionEndEvent:
      _checkEnd(txn, event, violations);
  }
}

void _checkStart(_Txn txn, SessionEvent event, List<String> violations) {
  final String? open = txn.id;
  if (open != null) {
    violations
        .add('seq ${event.seq} 的 $kCompactionStartEvent 之前，身份 $open 的压缩还没有收尾');
  }
  final String? id = _idOf(event);
  if (id == null) {
    violations.add('seq ${event.seq} 的 $kCompactionStartEvent 缺少 compactionId');
  }
  txn
    ..id = id
    ..summarized = false;
}

void _checkSummary(
  _Txn txn,
  SessionEvent event,
  List<SessionEvent> all,
  List<String> violations,
) {
  final String? id = _idOf(event);
  if (id == null || id != txn.id) {
    violations.add('seq ${event.seq} 的 $kCompactionSummaryEvent 身份 '
        '${id ?? '（缺失）'} 与进行中的压缩 ${txn.id ?? '（无）'} 不一致');
  }
  if (txn.summarized) {
    violations.add('seq ${event.seq} 的 $kCompactionSummaryEvent 在一次压缩里重复出现');
  }
  _checkShadowed(event, all, violations);
  txn.summarized = true;
}

void _checkEnd(_Txn txn, SessionEvent event, List<String> violations) {
  final String? id = _idOf(event);
  if (id == null || id != txn.id) {
    violations.add('seq ${event.seq} 的 $kCompactionEndEvent 身份 '
        '${id ?? '（缺失）'} 与进行中的压缩 ${txn.id ?? '（无）'} 不一致');
  }
  if (!_failed(event) && !txn.summarized) {
    violations.add('seq ${event.seq} 的 $kCompactionEndEvent 没有报错，'
        '但这次压缩没有 $kCompactionSummaryEvent');
  }
  txn
    ..id = null
    ..summarized = false;
}

void _checkClosed(_Txn txn, List<String> violations) {
  if (txn.id == null) return;
  violations.add('身份 ${txn.id} 的压缩没有 $kCompactionEndEvent 收尾');
}

void _checkShadowed(
  SessionEvent event,
  List<SessionEvent> all,
  List<String> violations,
) {
  final List<int>? seqs = _seqsOf(event);
  if (seqs == null || seqs.isEmpty) {
    violations
        .add('seq ${event.seq} 的 $kCompactionSummaryEvent 缺少 shadowedSeqs');
    return;
  }
  final List<int> prefix = <int>[
    for (final SessionEvent folded in all.take(seqs.length)) folded.seq,
  ];
  if (!_sameSeqs(seqs, prefix)) {
    violations.add('seq ${event.seq} 的 $kCompactionSummaryEvent 折叠的不是日志开头的一段');
  }
}

String? _idOf(SessionEvent event) {
  final Object? data = event.data;
  if (data is! Map) return null;
  final Object? id = data['compactionId'];
  return id is String && id.isNotEmpty ? id : null;
}

bool _failed(SessionEvent event) {
  final Object? data = event.data;
  return data is Map && data['error'] != null;
}

List<int>? _seqsOf(SessionEvent event) {
  final Object? data = event.data;
  if (data is! Map) return null;
  final Object? raw = data['shadowedSeqs'];
  if (raw is! List) return null;
  final List<int> seqs = <int>[];
  for (final Object? item in raw) {
    if (item is! int) return null;
    seqs.add(item);
  }
  return seqs;
}

bool _sameSeqs(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// 工具配对平衡：压缩的切点不能把助手的工具调用与它的 `tool/result` 劈到两边
/// ——保留窗口若以孤立的工具结果开头，模型会收到没有对应调用的 tool 消息。
///
/// 对应 dsh `packages/compaction/compaction` 的 `tool-pairing.ts`。Dart 侧日志只
/// 追加、不替换，切点直接按事件顺序折叠，无需 surface 位置换算。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 单个会话的增量平衡状态。
class _BalanceCache {
  _BalanceCache(this.folded);

  /// 已折叠进 [cutBalanced] 的事件条数。
  int folded;

  /// N 条事件有 N + 1 个切点：[cutBalanced] 的第 i 项是第 i 条事件**之前**的
  /// 切点，末项是尾切点。
  final List<bool> cutBalanced = <bool>[true];

  /// 当前各事件在日志中的下标。
  final Map<int, int> indexBySeq = <int, int>{};

  /// 尾切点处尚未闭合的工具调用数。
  int inProgressCalls = 0;
}

final Expando<_BalanceCache> _caches =
    Expando<_BalanceCache>('compaction.toolPairing');

/// 折叠 [session] 尚未进入缓存的尾部事件。
///
/// 先校验完整个尾部再落缓存：日志出现「结果先于调用」的错位时抛 [StateError]，
/// 且不留下半推进的状态。
_BalanceCache _extend(Session session, _BalanceCache cache) {
  final List<SessionEvent> events = session.events;
  final List<bool> pending = <bool>[];
  int inProgress = cache.inProgressCalls;
  for (final SessionEvent event in events.skip(cache.folded)) {
    inProgress += _eventDelta(event);
    if (inProgress < 0) {
      throw StateError('工具配对平衡：seq ${event.seq} 的 $kToolResultEvent 没有对应的工具调用');
    }
    pending.add(inProgress == 0);
  }
  for (int index = cache.folded; index < events.length; index++) {
    cache.indexBySeq[events[index].seq] = index;
  }
  cache.folded = events.length;
  cache.cutBalanced.addAll(pending);
  cache.inProgressCalls = inProgress;
  _caches[session] = cache;
  return cache;
}

/// [session] 当前日志对应的平衡状态。
_BalanceCache _cacheFor(Session session) {
  final _BalanceCache? cached = _caches[session];
  if (cached == null) return _extend(session, _BalanceCache(0));
  if (cached.folded == session.length) return cached;
  return _extend(session, cached);
}

/// 一条事件对「未闭合工具调用数」的增量。
int _eventDelta(SessionEvent event) {
  switch (event.type) {
    case kAssistantMessageEvent:
      return _openCalls(event.data);
    case kToolResultEvent:
      return -1;
    default:
      return 0;
  }
}

/// 助手事件里声明的工具调用数。
int _openCalls(Object? data) {
  if (data is! Map) return 0;
  final Object? calls = data['toolCalls'];
  return calls is List ? calls.length : 0;
}

/// 某条事件之前（[offset] 为 0）或之后（[offset] 为 1）的切点是否平衡。
bool _cutBalance(_BalanceCache cache, int seq, int offset) {
  final int? index = cache.indexBySeq[seq];
  if (index == null) {
    throw StateError('工具配对平衡：会话日志中没有 seq 为 $seq 的事件');
  }
  return cache.cutBalanced[index + offset];
}

/// [session] 中 [seq] 之前的切点是否平衡（不劈开工具调用与结果）。
///
/// [seq] 不在日志里、或日志出现「结果先于调用」的错位时抛 [StateError]。
bool toolPairingBalancedBefore(Session session, int seq) =>
    _cutBalance(_cacheFor(session), seq, 0);

/// [session] 中 [seq] 之后的切点是否平衡。
bool toolPairingBalancedAfter(Session session, int seq) =>
    _cutBalance(_cacheFor(session), seq, 1);

/// 把切点吸附到最近的平衡位置：从第 [cut] 个切点（折叠前 [cut] 条事件）向前找
/// 第一个平衡切点，找不到时返回 0（无事可折叠）。
///
/// [cut] 必须落在 `0..session.length`；平衡状态会折叠到日志末尾。
int balancedCutAtOrBefore(Session session, int cut) {
  final List<bool> balanced = _cacheFor(session).cutBalanced;
  for (int index = cut; index > 0; index--) {
    if (balanced[index]) return index;
  }
  return 0;
}

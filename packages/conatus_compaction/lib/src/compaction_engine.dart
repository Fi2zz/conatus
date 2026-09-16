/// 压缩能力缝（服务键 `'compaction'`）：实现方决定何时压缩、保留多少，并把更早
/// 的历史折叠成一条滚动摘要；消费方只依赖本接口。
///
/// 对应 dsh `packages/compaction/compaction` 的 `CompactionEngine`。dsh 的手动
/// 与区间两种入口在 Dart 侧暂未落地（没有 surface 替换层，也没有 `/compact`
/// 命令），见包 README 的限制一节。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'compaction_types.dart';

/// 压缩能力接口，注册为 `'compaction'` 服务。
abstract class CompactionEngine {
  /// 保留为原始日志的最近事件数。
  int get keepRecent;

  /// 某会话当前的滚动摘要；尚未压缩过时为 `null`。
  String? summaryOf(String sessionId);

  /// 丢弃某会话的摘要记忆。
  void forget(String sessionId);

  /// 事件数超过预算时折叠较早部分并返回结果；没有可折叠的平衡切点时返回 `null`。
  ///
  /// 一次成功的压缩在日志留下 `compaction/start` → `compaction/summary` →
  /// `compaction/end` 三个事件，且切点不劈开工具调用与其结果。汇总器抛错时
  /// `compaction/end` 记下错误、摘要记忆不更新，异常原样上抛。
  Future<CompactionResult?> compactIfNeeded(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  });
}

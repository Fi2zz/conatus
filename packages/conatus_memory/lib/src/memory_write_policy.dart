/// 写入判定：一条轮次内容该不该写、写进去是什么样子。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 判定原因；`store` 之外的取值都表示不写。
enum MemoryWriteVerdict {
  store,
  emptyReply,
  greeting,
  shortReply,
  duplicate,
  rejected,
}

/// 一次写入判定的结果。
class MemoryWriteDecision {
  const MemoryWriteDecision._(this.verdict, [this.text]);

  /// 写入，[text] 为落库正文。
  const MemoryWriteDecision.store(String text)
      : this._(MemoryWriteVerdict.store, text);

  /// 不写。
  const MemoryWriteDecision.skip(MemoryWriteVerdict verdict) : this._(verdict);

  /// 判定原因。
  final MemoryWriteVerdict verdict;

  /// 落库正文；不写时为 null。
  final String? text;

  /// 是否写入。
  bool get store => verdict == MemoryWriteVerdict.store;
}

/// 写入策略：一轮结束后决定是否保留。
abstract interface class MemoryWritePolicy {
  /// 判定 [userInput] / [reply] 这一轮是否值得写入长期记忆。
  MemoryWriteDecision review({
    required String userInput,
    required String reply,
    required Iterable<MemoryEntry> existing,
  });
}

/// 默认寒暄 / 确认词表（归一化后整句匹配）。
const Set<String> kDefaultGreetings = <String>{
  'hi',
  'hey',
  'hello',
  'thanks',
  'thank you',
  'ok',
  '你好',
  '您好',
  '在吗',
  '早上好',
  '晚上好',
  '谢谢',
  '好的',
  '嗯',
};

/// 内置规则：空回复 / 寒暄 / 短回复 / 近重复不写，超长截断。
class PolicyMemoryWritePolicy implements MemoryWritePolicy {
  const PolicyMemoryWritePolicy({
    this.minReplyChars = 12,
    this.duplicateThreshold = 0.6,
    this.maxChars = 600,
    this.greetings = kDefaultGreetings,
  });

  /// 回复正文的最小保留长度。
  final int minReplyChars;

  /// 判重用的字符 bigram Jaccard 阈值。
  final double duplicateThreshold;

  /// 落库正文的长度上限。
  final int maxChars;

  /// 寒暄词表。
  final Set<String> greetings;

  @override
  MemoryWriteDecision review({
    required String userInput,
    required String reply,
    required Iterable<MemoryEntry> existing,
  }) {
    final String trimmed = reply.trim();
    if (trimmed.isEmpty) {
      return const MemoryWriteDecision.skip(MemoryWriteVerdict.emptyReply);
    }
    if (greetings.contains(_normalize(userInput))) {
      return const MemoryWriteDecision.skip(MemoryWriteVerdict.greeting);
    }
    if (trimmed.length < minReplyChars) {
      return const MemoryWriteDecision.skip(MemoryWriteVerdict.shortReply);
    }
    final String text = '用户：${userInput.trim()}\n助手：$trimmed';
    if (existing.any((MemoryEntry entry) => _similar(text, entry.text))) {
      return const MemoryWriteDecision.skip(MemoryWriteVerdict.duplicate);
    }
    return MemoryWriteDecision.store(_truncate(text));
  }

  String _truncate(String text) =>
      text.length <= maxChars ? text : text.substring(0, maxChars);

  bool _similar(String a, String b) {
    final Set<String> left = _bigrams(a);
    final Set<String> right = _bigrams(b);
    if (left.isEmpty || right.isEmpty) return false;
    final int shared = left.intersection(right).length;
    return shared / left.union(right).length >= duplicateThreshold;
  }

  static Set<String> _bigrams(String text) {
    final String clean =
        text.toLowerCase().replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '');
    return <String>{
      for (int i = 0; i + 1 < clean.length; i++) clean.substring(i, i + 2),
    };
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'[\s,.!?;:，。！？；：]+$'), '');
}

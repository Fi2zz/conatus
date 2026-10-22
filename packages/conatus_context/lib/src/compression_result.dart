/// 一次压缩的结局：压缩后正文、长度与 CCR 身份。
library;

import 'content_kind.dart';

/// 一条内容的压缩结果。
///
/// [applied] 为 false 时 [content] 必须等于原文；[skippedReason] 说明原因，
/// 便于调用方与遥测区分「不值得压」与「压了但失败」。
class ContextCompressionResult {
  const ContextCompressionResult({
    required this.applied,
    required this.kind,
    required this.content,
    required this.beforeChars,
    required this.afterChars,
    this.ccrId,
    this.skippedReason,
  });

  /// 构造一个原样透传的结果。
  factory ContextCompressionResult.skipped({
    required String input,
    required ContentKind kind,
    required String reason,
  }) =>
      ContextCompressionResult(
        applied: false,
        kind: kind,
        content: input,
        beforeChars: input.length,
        afterChars: input.length,
        skippedReason: reason,
      );

  /// 是否实际改变了内容。
  final bool applied;

  /// 检测到的内容类型。
  final ContentKind kind;

  /// 压缩后正文；未应用时等于原文。
  final String content;

  /// 压缩前字符数。
  final int beforeChars;

  /// 压缩后字符数。
  final int afterChars;

  /// CCR 身份；未存原文时为 null。
  final String? ccrId;

  /// 未压缩原因（tooSmall / protected / disabled / alreadyCompressed /
  /// noSaving / error / empty）；已压缩时为 null。
  final String? skippedReason;
}

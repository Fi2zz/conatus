/// 压缩器能力缝：预算、草稿与统一接口。
library;

import 'content_kind.dart';

/// 一次压缩的预算，由 Router 按配置构造。
class CompressionBudget {
  const CompressionBudget({
    required this.maxItems,
    required this.maxLines,
    required this.maxFiles,
    required this.targetRatio,
    required this.retrievalId,
    this.conservative = false,
  });

  /// 结构化项上限（JSON / 表格）。
  final int maxItems;

  /// 行数上限（日志 / 搜索 / diff）。
  final int maxLines;

  /// 文件数上限（搜索结果）。
  final int maxFiles;

  /// 纯文本目标保留比例。
  final double targetRatio;

  /// CCR 身份；为空表示未启用 CCR，压缩器不应嵌入标记。
  final String retrievalId;

  /// 保守模式：工具错误结果使用更小的预算。
  final bool conservative;
}

/// 压缩草稿：编译器只产出正文，标记与存储由 Router 统一处理。
class CompressionDraft {
  const CompressionDraft(
    this.output, {
    this.itemsOmitted = 0,
    this.unit = 'items',
  });

  /// 压缩后正文。
  final String output;

  /// 省略数量；0 表示只做格式紧凑化。
  final int itemsOmitted;

  /// 数量单位。
  final String unit;
}

/// 内容压缩器。
abstract class ContentCompressor {
  /// 处理的内容类型。
  ContentKind get kind;

  /// 压缩；无事可做或不安全时返回 null。
  CompressionDraft? compress(String input, CompressionBudget budget);
}

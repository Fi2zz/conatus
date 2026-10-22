/// 上下文压缩的配置。
///
/// 所有阈值都是「字符数」口径；token 数只在统计里按 4 字符 ≈ 1 token 估算，
/// 并显式标注 `estimated`，不用于计费。
library;

import 'compression_result.dart';
import 'content_kind.dart';

/// 压缩配置。默认值即推荐值。
class ContextCompressionConfig {
  const ContextCompressionConfig({
    this.enabled = true,
    this.minChars = 4000,
    this.minSavingRatio = 0.15,
    this.protectedTools = const <String>{},
    this.disabledKinds = const <ContentKind>{},
    this.ccrEnabled = true,
    this.ccrMaxEntries = 1000,
    this.ccrTtl = const Duration(hours: 1),
    this.maxJsonItems = 30,
    this.maxLogLines = 200,
    this.maxSearchLines = 80,
    this.maxSearchFiles = 40,
    this.maxDiffLines = 150,
    this.maxTableRows = 30,
    this.textTargetRatio = 0.5,
    this.compressToolErrors = true,
    this.onCompressed,
  });

  /// 总开关；false 时中间件直接透传。
  final bool enabled;

  /// 低于该字符数不压缩。
  final int minChars;

  /// 最小节省比例；达不到就回退原文。
  final double minSavingRatio;

  /// 永不压缩的工具名。
  final Set<String> protectedTools;

  /// 禁用压缩的内容类型。
  final Set<ContentKind> disabledKinds;

  /// 是否启用 CCR（存原文 + 注入标记 + 注册取回工具）。
  final bool ccrEnabled;

  /// CCR 最多保留的条目数。
  final int ccrMaxEntries;

  /// CCR 条目存活时间。
  final Duration ccrTtl;

  /// JSON 数组最多保留的元素数。
  final int maxJsonItems;

  /// 日志最多保留的行数。
  final int maxLogLines;

  /// 搜索结果最多保留的行数。
  final int maxSearchLines;

  /// 搜索结果最多保留的文件数。
  final int maxSearchFiles;

  /// diff 最多保留的行数。
  final int maxDiffLines;

  /// 表格最多保留的行数。
  final int maxTableRows;

  /// 纯文本目标保留比例。
  final double textTargetRatio;

  /// 工具错误结果是否也压缩（走保守模式）。
  final bool compressToolErrors;

  /// 每次压缩后的回调，供调用方接遥测。
  final void Function(ContextCompressionResult)? onCompressed;
}

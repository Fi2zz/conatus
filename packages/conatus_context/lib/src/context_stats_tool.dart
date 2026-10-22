/// `context_stats` 工具：输出压缩与 CCR 命中统计。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'compression_stats.dart';

/// 查询本次运行期的压缩统计。
class ContextStatsTool extends Tool {
  ContextStatsTool(this.stats);

  /// 统计数据。
  final CompressionStats stats;

  @override
  String get name => 'context_stats';

  @override
  String get description => '查看上下文压缩的累计统计（字符数与估算 token 数）。';

  @override
  Future<ToolResult> call(ToolContext context) async => ToolResult.success(
        jsonEncode(stats.toJson()),
        value: stats.toJson(),
      );
}

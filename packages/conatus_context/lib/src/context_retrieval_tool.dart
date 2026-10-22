/// `context_retrieve` 工具：按 CCR id 取回原文，支持分段读取。
library;

import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'ccr_store.dart';

/// 取回一条被压缩内容的原文。
class ContextRetrievalTool extends Tool {
  ContextRetrievalTool(this.store, {this.onHit});

  /// 原文存储。
  final CcrStore store;

  /// 命中回调，供统计计数。
  final void Function()? onHit;

  @override
  String get name => 'context_retrieve';

  @override
  String get description => '取回被压缩内容的原文。看到形如 <<ctx:ID N_items_omitted>> 的标记时，'
      '用这里的 id 读取；可用 offset/limit 分段读取，避免一次取回过多内容。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id', description: 'CCR 标记里的 id', required: true),
        ParamSpec.integer('offset', description: '字符偏移，默认 0'),
        ParamSpec.integer('limit', description: '最多返回字符数，默认 40000'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String id = context.str('id');
    final String? content = await store.get(id);
    if (content == null) {
      return ToolResult.failure(
        '未找到 id=$id 的原文；可能已过期，或标记不是由本会话产生。',
        error: const ToolError('ccr_miss', '未找到该 id 的原文'),
      );
    }
    onHit?.call();
    final int offset = math.max(0, context.integer('offset') ?? 0);
    if (offset > content.length) {
      return ToolResult.failure(
        '偏移超出原文长度：offset=$offset, length=${content.length}',
        error: const ToolError('ccr_offset', 'offset 超出原文长度'),
      );
    }
    final int requested = context.integer('limit') ?? 40000;
    final int limit = requested <= 0 || requested > 40000 ? 40000 : requested;
    final int end = math.min(content.length, offset + limit);
    final String part = content.substring(offset, end);
    return ToolResult.success(
      part,
      value: <String, Object?>{
        'id': id,
        'chars': content.length,
        'offset': offset,
        'returned': part.length,
        'truncated': end < content.length,
      },
    );
  }
}

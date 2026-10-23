import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_chunk.dart';
import 'rag_query.dart';
import 'rag_scope.dart';
import 'rag_service.dart';

/// 把 [RagService] 的检索能力暴露给模型的工具。
///
/// [scope] 为 null 时 fail closed：不查任何数据，直接返回权限错误，
/// 避免共享进程里靠 `session_id` 猜测租户。
class RagSearchTool extends Tool {
  RagSearchTool({required RagService service, RagScope? scope})
      : _service = service,
        _scope = scope;

  final RagService _service;
  final RagScope? _scope;

  @override
  String get name => 'rag_search';

  @override
  String get description => '检索会话历史原文，返回与查询相关的证据片段及引用来源。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('query', required: true, description: '检索查询'),
        ParamSpec.integer('limit',
            defaultValue: 5, description: '返回命中数（1..15）'),
        ParamSpec.string('session_id', description: '限定来源会话'),
        ParamSpec.string('from', description: '起始时间（ISO 8601）'),
        ParamSpec.string('to', description: '结束时间（ISO 8601）'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final RagScope? scope = _scope;
    if (scope == null) {
      return ToolResult.failure(
        '未配置检索作用域，拒绝执行。',
        error: const ToolError('rag_scope_missing', '缺少 RagScope'),
      );
    }
    final List<RagHit> hits = await _service.retrieve(_request(context, scope));
    return ToolResult.success(
      _service.formatHits(hits),
      value: <String, Object?>{
        'count': hits.length,
        'hits': <Map<String, Object?>>[
          for (final RagHit hit in hits) _hitValue(hit),
        ],
      },
    );
  }

  RetrievalRequest _request(ToolContext context, RagScope scope) {
    return RetrievalRequest(
      query: context.str('query').trim(),
      scope: scope,
      limit: _clampLimit(context.integer('limit') ?? 5),
      sourceIds: _optionalSourceIds(context.string('session_id')),
      from: _parseTime(context.string('from'), 'from'),
      to: _parseTime(context.string('to'), 'to'),
    );
  }
}

int _clampLimit(int limit) => limit.clamp(1, 15).toInt();

Set<String>? _optionalSourceIds(String? sessionId) =>
    sessionId == null ? null : <String>{sessionId};

DateTime? _parseTime(String? value, String name) {
  if (value == null) return null;
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ToolArgumentException('参数 "$name" 不是合法的 ISO 8601 时间');
  }
  return parsed;
}

Map<String, Object?> _hitValue(RagHit hit) => <String, Object?>{
      'id': hit.chunk.id,
      'sourceKind': hit.chunk.sourceKind,
      'sourceId': hit.chunk.sourceId,
      'firstSeq': hit.chunk.firstSeq,
      'lastSeq': hit.chunk.lastSeq,
      'score': hit.score,
      'startTime': hit.chunk.startTime.toIso8601String(),
    };

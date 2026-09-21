/// 语义诊断：从交互轨迹中提取共性语义错误。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 一个语义错误。
class SemanticError {
  const SemanticError({
    required this.description,
    required this.manifestation,
    required this.fixDirection,
    required this.traceIds,
  });

  factory SemanticError.fromJson(Map<String, Object?> json) => SemanticError(
        description: json['description']! as String,
        manifestation: json['manifestation']! as String,
        fixDirection: json['fixDirection']! as String,
        traceIds: <String>[
          for (final Object? id in (json['traceIds'] ?? const <Object?>[]) as List)
            id! as String,
        ],
      );

  final String description;
  final String manifestation;
  final String fixDirection;
  final List<String> traceIds;

  Map<String, Object?> toJson() => <String, Object?>{
        'description': description,
        'manifestation': manifestation,
        'fixDirection': fixDirection,
        'traceIds': traceIds,
      };
}

/// 诊断结果。
class SemanticDiagnosis {
  const SemanticDiagnosis(this.errors);

  final List<SemanticError> errors;
}

/// 从轨迹诊断共性语义错误。
Future<SemanticDiagnosis> diagnose(
  LlmProvider llm,
  List<SessionEvent> trajectories,
) async {
  final String prompt = '''
以下是 Data Agent 的交互轨迹，包含查询和结果。
请诊断共性语义错误：

${trajectories.map(_summarize).join('\n---\n')}

请提取 1-3 个语义错误，每个包含：
1. description 错误描述
2. manifestation 典型表现
3. fixDirection 修复方向
4. traceIds 相关的轨迹 ID 数组

以 JSON 数组返回。
''';
  final LlmResult result = await llm.chat(<LlmMessage>[
    const LlmMessage('system', '你是数据语义诊断专家。'),
    LlmMessage('user', prompt),
  ]);
  return parseDiagnosis(result.content);
}

/// 解析诊断 JSON；失败抛 [FormatException]。
SemanticDiagnosis parseDiagnosis(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_extractJson(content));
  } on FormatException catch (e) {
    throw FormatException('无法解析诊断 JSON: ${e.message}');
  }
  if (decoded is! List) throw const FormatException('诊断结果必须是 JSON 数组');
  final List<SemanticError> errors = <SemanticError>[];
  for (final Object? item in decoded) {
    if (item is! Map) continue;
    errors.add(SemanticError.fromJson(Map<String, Object?>.from(item)));
  }
  return SemanticDiagnosis(errors);
}

String _summarize(SessionEvent event) {
  final Map<String, Object?> data =
      event.data is Map ? Map<String, Object?>.from(event.data! as Map) : <String, Object?>{};
  final List<String> parts = <String>[
    for (final MapEntry<String, Object?> entry in data.entries.take(3))
      '${entry.key}=${entry.value}',
  ];
  return '${event.type}(${parts.join(', ')})';
}

String _extractJson(String content) {
  final int start = content.indexOf('[');
  final int end = content.lastIndexOf(']');
  if (start < 0 || end <= start) return content;
  return content.substring(start, end + 1);
}

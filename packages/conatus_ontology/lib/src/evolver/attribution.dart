/// 归因：把语义错误归因到 Content / Schema / Tool 层，并建议编辑。
library;

import 'dart:convert';

import 'package:conatus_llm/conatus_llm.dart';

import '../ontology/edits.dart';
import '../ontology/layer.dart';
import 'diagnosis.dart';

/// 归因目标。
enum AttributionTarget { content, schema, tool }

/// 归因结果。
class Attribution {
  const Attribution({
    required this.target,
    required this.errorType,
    required this.evidence,
    required this.suggestedEdits,
  });

  factory Attribution.fromJson(Map<String, Object?> json) => Attribution(
        target: _parseTarget(json['target']! as String),
        errorType: json['errorType']! as String,
        evidence: <String>[
          for (final Object? id in (json['evidence'] ?? const <Object?>[]) as List)
            id! as String,
        ],
        suggestedEdits: <TypedEdit>[
          for (final Object? edit in json['suggestedEdits'] as List)
            TypedEdit.fromJson(Map<String, Object?>.from(edit! as Map)),
        ],
      );

  final AttributionTarget target;
  final String errorType;
  final List<String> evidence;
  final List<TypedEdit> suggestedEdits;

  Map<String, Object?> toJson() => <String, Object?>{
        'target': target.name,
        'errorType': errorType,
        'evidence': evidence,
        'suggestedEdits': <Map<String, Object?>>[
          for (final TypedEdit edit in suggestedEdits) edit.toJson(),
        ],
      };

  static AttributionTarget _parseTarget(String name) =>
      AttributionTarget.values.firstWhere(
        (AttributionTarget target) => target.name == name,
        orElse: () => throw FormatException('未知归因目标: $name'),
      );
}

/// 归因引擎：从轨迹诊断中归因到具体层。
class AttributionEngine {
  const AttributionEngine({required this.llm});

  final LlmProvider llm;

  /// 从轨迹诊断中归因。
  Future<List<Attribution>> attribute(
    SemanticDiagnosis diagnosis,
    OntologyLayer currentLayer,
  ) async {
    final String prompt = '''
诊断出的语义错误：
${_describeErrors(diagnosis)}

当前本体层：
${_describeLayer(currentLayer)}

请对每个错误归因：
1. 归因到哪一层（content / schema / tool）
2. 错误类型
3. 支持的证据（轨迹 ID）
4. 建议的类型化编辑

以 JSON 数组返回，例如：
[{"target": "content", "errorType": "term_misunderstanding", "evidence": ["t1"], "suggestedEdits": [{"edit": "add_node", "node": {...}}]}]
''';
    final LlmResult result = await llm.chat(<LlmMessage>[
      const LlmMessage('system', '你是本体归因专家。'),
      LlmMessage('user', prompt),
    ]);
    return parseAttributions(result.content);
  }

  String _describeErrors(SemanticDiagnosis diagnosis) => diagnosis.errors
      .map((SemanticError error) =>
          '- ${error.description}（表现：${error.manifestation}）')
      .join('\n');

  String _describeLayer(OntologyLayer layer) {
    final StringBuffer buffer = StringBuffer('version=${layer.version}');
    for (final item in layer.nodes.take(20)) {
      buffer.writeln('  ${item.type}: ${item.id}');
    }
    return buffer.toString();
  }
}

/// 解析归因 JSON；失败抛 [FormatException]。
List<Attribution> parseAttributions(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_extractJson(content));
  } on FormatException catch (e) {
    throw FormatException('无法解析归因 JSON: ${e.message}');
  }
  if (decoded is! List) throw const FormatException('归因结果必须是 JSON 数组');
  return <Attribution>[
    for (final Object? item in decoded)
      if (item is Map)
        Attribution.fromJson(Map<String, Object?>.from(item)),
  ];
}

String _extractJson(String content) {
  final int start = content.indexOf('[');
  final int end = content.lastIndexOf(']');
  if (start < 0 || end <= start) return content;
  return content.substring(start, end + 1);
}

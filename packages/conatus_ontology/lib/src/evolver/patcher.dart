/// Typed Edits 生成：从归因结果生成类型化编辑。
library;

import 'dart:convert';

import 'package:conatus_llm/conatus_llm.dart';

import '../ontology/edits.dart';
import '../ontology/layer.dart';
import 'attribution.dart';

/// 从归因结果生成类型化编辑。
Future<List<TypedEdit>> generateEdits(
  LlmProvider llm,
  List<Attribution> attributions,
  OntologyLayer currentLayer,
) async {
  final String prompt = '''
归因结果：
${_describeAttributions(attributions)}

当前本体层：
${_describeLayer(currentLayer)}

请生成类型化编辑。可选类型（JSON 对象，edit 字段）：
- add_node / remove_node / update_node_fields
- add_relation / remove_relation
- add_reference / remove_reference
- merge_terms / split_term

以 JSON 数组返回。
''';
  final LlmResult result = await llm.chat(<LlmMessage>[
    const LlmMessage('system', '你是本体编辑专家。'),
    LlmMessage('user', prompt),
  ]);
  return parseTypedEdits(result.content);
}

/// 解析编辑 JSON；失败抛 [FormatException]。
List<TypedEdit> parseTypedEdits(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_extractJson(content));
  } on FormatException catch (e) {
    throw FormatException('无法解析编辑 JSON: ${e.message}');
  }
  if (decoded is! List) throw const FormatException('编辑结果必须是 JSON 数组');
  return <TypedEdit>[
    for (final Object? item in decoded)
      if (item is Map) TypedEdit.fromJson(Map<String, Object?>.from(item)),
  ];
}

String _describeAttributions(List<Attribution> attributions) =>
    attributions
        .map((Attribution attribution) =>
            '- [${attribution.target.name}] ${attribution.errorType}')
        .join('\n');

String _describeLayer(OntologyLayer layer) {
  final StringBuffer buffer = StringBuffer('version=${layer.version}');
  for (final item in layer.nodes.take(20)) {
    buffer.writeln('  ${item.type}: ${item.id}');
  }
  return buffer.toString();
}

String _extractJson(String content) {
  final int start = content.indexOf('[');
  final int end = content.lastIndexOf(']');
  if (start < 0 || end <= start) return content;
  return content.substring(start, end + 1);
}

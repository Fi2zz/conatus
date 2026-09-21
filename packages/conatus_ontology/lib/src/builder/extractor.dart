/// 概念提取：从数据源 schema 提取领域核心概念（Term）。
library;

import 'dart:convert';

import 'package:conatus_llm/conatus_llm.dart';

import '../ontology/node.dart';
import 'source.dart';

/// 从数据源提取候选 Term。
///
/// LLM 返回 JSON 数组，每个元素含 name / definition / aliases / domain。
Future<List<Term>> extractCandidates(
  LlmProvider llm,
  List<DataSource> sources,
) async {
  final String prompt = '''
以下是数据源的 schema：
${_describeSources(sources)}

请提取领域核心概念（Term），每个包含：
1. 概念名（中文）
2. 定义（一句话）
3. 别名（数组）
4. 可能的数据源映射（source.column 形式）

以 JSON 数组返回，例如：
[{"name": "营业收入", "definition": "主营业务收入", "aliases": ["revenue"], "domain": "财务", "mappings": ["sales.orders.amount"]}]
''';
  final LlmResult result = await llm.chat(<LlmMessage>[
    const LlmMessage('system', '你是数据语义分析专家。'),
    LlmMessage('user', prompt),
  ]);
  return parseTerms(result.content, DateTime.now());
}

/// 解析 LLM 返回的 Term JSON；失败抛 [FormatException]。
List<Term> parseTerms(String content, DateTime now) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_extractJson(content));
  } on FormatException catch (e) {
    throw FormatException('无法解析 Term JSON: ${e.message}');
  }
  if (decoded is! List) {
    throw const FormatException('Term 结果必须是 JSON 数组');
  }
  final List<Term> terms = <Term>[];
  for (final Object? item in decoded) {
    if (item is! Map) continue;
    final Map<String, Object?> json = Map<String, Object?>.from(item);
    terms.add(Term(
      id: 'term-${terms.length + 1}',
      createdAt: now,
      name: json['name']! as String,
      definition: json['definition']! as String,
      aliases: <String>[
        for (final Object? alias
            in (json['aliases'] ?? const <Object?>[]) as List)
          alias! as String,
      ],
      domain: json['domain'] as String?,
    ));
  }
  return terms;
}

/// 数据源摘要（LLM 输入内联格式）。
String describeSources(List<DataSource> sources) {
  final StringBuffer buffer = StringBuffer();
  for (final DataSource source in sources) {
    buffer.writeln('数据源 ${source.id}（${source.kind}）: ${source.name}');
    for (final DataColumn column in source.columns) {
      buffer.writeln(
          '  - ${column.name} (${column.type})${column.description == null ? '' : ' ${column.description}'}');
    }
  }
  return buffer.toString().trimRight();
}

String _describeSources(List<DataSource> sources) => describeSources(sources);

/// 从 LLM 回复中提取 JSON 数组（容忍 markdown 代码围栏）。
String _extractJson(String content) {
  final int fenceStart = content.indexOf('[');
  final int fenceEnd = content.lastIndexOf(']');
  if (fenceStart < 0 || fenceEnd <= fenceStart) return content;
  return content.substring(fenceStart, fenceEnd + 1);
}

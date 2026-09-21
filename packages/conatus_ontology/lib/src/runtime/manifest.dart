/// 会话清单：本体的紧凑概览，供注入 system prompt 而非全量本体。
library;

import '../ontology/layer.dart';
import '../ontology/node.dart';

/// 构建紧凑 manifest 文本。
///
/// 只包含数量统计与核心术语摘要（最多 20 个），不携带完整记录。
String buildManifest(OntologyLayer layer) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('<ontology-manifest version="${layer.version}">')
    ..writeln('可用术语：${layer.nodesOfType('term').length} 个')
    ..writeln('映射：${layer.nodesOfType('mapping').length} 个')
    ..writeln('约束：${layer.nodesOfType('constraint').length} 个')
    ..writeln()
    ..writeln('核心术语：');
  final List<OntologyNode> terms = layer.nodesOfType('term');
  final int end = terms.length < 20 ? terms.length : 20;
  for (final OntologyNode item in terms.sublist(0, end)) {
    final Term term = item as Term;
    buffer.writeln('- ${term.name}: ${term.definition}');
  }
  buffer.write('</ontology-manifest>');
  return buffer.toString();
}

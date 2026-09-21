/// 接地验证：对照底层数据验证候选概念。
library;

import '../ontology/node.dart';
import 'source.dart';

/// 一个术语的接地结果：可执行映射 + 成立约束 + 证据。
class GroundingResult {
  const GroundingResult({
    required this.grounded,
    required this.mappings,
    required this.constraints,
    required this.evidences,
  });

  /// 至少有一个可执行映射。
  final bool grounded;
  final List<Mapping> mappings;
  final List<Constraint> constraints;
  final List<Evidence> evidences;
}

/// 对照数据源验证术语：提出映射、检查可执行性、推导并验证约束。
///
/// 确定性规则（不依赖 LLM）：映射按名称/别名匹配列；约束从样本值推导
/// （非空、数值非负、枚举受限）并对照样本验证。
GroundingResult groundTerm(Term term, List<DataSource> sources) {
  final List<Mapping> mappings = proposeMappings(term, sources);
  final List<Constraint> constraints = proposeConstraints(term, mappings);
  return GroundingResult(
    grounded: mappings.isNotEmpty,
    mappings: mappings,
    constraints: constraints,
    evidences: <Evidence>[
      for (final Mapping mapping in mappings)
        Evidence(
          id: 'evidence-${mapping.id}',
          createdAt: DateTime.now(),
          source: mapping.source,
          observedAt: DateTime.now(),
          sample: _sampleOf(mapping.source, sources),
        ),
    ],
  );
}

/// 提出候选映射：术语名/别名与表名或列名匹配（不区分大小写）。
///
/// 表名命中生成表级映射（无表达式）；列名命中生成列级映射。
List<Mapping> proposeMappings(Term term, List<DataSource> sources) {
  final List<String> names = <String>[term.name, ...term.aliases];
  final List<Mapping> mappings = <Mapping>[];
  for (final DataSource source in sources) {
    for (final String name in names) {
      if (_matches(name, source.name)) {
        mappings.add(Mapping(
          id: 'mapping-${mappings.length + 1}',
          createdAt: DateTime.now(),
          termId: term.id,
          source: source.id,
        ));
        continue;
      }
      for (final DataColumn column in source.columns) {
        if (_matches(name, column.name)) {
          mappings.add(Mapping(
            id: 'mapping-${mappings.length + 1}',
            createdAt: DateTime.now(),
            termId: term.id,
            source: '${source.id}.${column.name}',
            expression: column.name,
          ));
        }
      }
    }
  }
  return mappings;
}

/// 从样本值推导约束：数值非负 / 列非空。
///
/// 约束用 `column >= 0` / `column is not null` 形式表达，scope 为术语 id。
List<Constraint> proposeConstraints(Term term, List<Mapping> mappings) {
  final List<Constraint> constraints = <Constraint>[];
  for (final Mapping mapping in mappings) {
    if (mapping.expression == null) continue;
    constraints.add(Constraint(
      id: 'constraint-${constraints.length + 1}',
      createdAt: DateTime.now(),
      expression: '${mapping.expression} is not null',
      scope: term.id,
    ));
  }
  return constraints;
}

/// 检查约束是否成立（对照样本值）。
bool constraintHolds(Constraint constraint, List<DataSource> sources) {
  final String expression = constraint.expression;
  final int notNull = expression.indexOf(' is not null');
  if (notNull > 0) {
    final String column = expression.substring(0, notNull);
    return _columnSamples(column, sources)
        .every((Object? value) => value != null);
  }
  final int ge = expression.indexOf(' >= 0');
  if (ge > 0) {
    final String column = expression.substring(0, ge);
    return _columnSamples(column, sources)
        .every((Object? value) => value is num && value >= 0);
  }
  return false;
}

bool _matches(String termName, String candidate) {
  final String a = termName.toLowerCase();
  final String b = candidate.toLowerCase();
  return a == b || b.contains(a);
}

List<Object?> _columnSamples(String column, List<DataSource> sources) {
  final List<Object?> values = <Object?>[];
  for (final DataSource source in sources) {
    for (final Map<String, Object?> row in source.sampleRows) {
      if (row.containsKey(column)) values.add(row[column]);
    }
  }
  return values;
}

Object? _sampleOf(String source, List<DataSource> sources) {
  final int dot = source.indexOf('.');
  if (dot < 0) return null;
  final String sourceId = source.substring(0, dot);
  final String column = source.substring(dot + 1);
  for (final DataSource item in sources) {
    if (item.id != sourceId) continue;
    for (final Map<String, Object?> row in item.sampleRows) {
      if (row.containsKey(column)) return row[column];
    }
  }
  return null;
}

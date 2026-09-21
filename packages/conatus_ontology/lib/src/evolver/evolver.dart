/// 进化候选：携带 typed edits 的本体变体。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';

import '../builder/grounding.dart';
import '../builder/source.dart';
import '../ontology/edit_validator.dart';
import '../ontology/edits.dart';
import '../ontology/layer.dart';
import '../ontology/node.dart';
import '../ontology/schema.dart';
import 'attribution.dart';
import 'diagnosis.dart';
import 'patcher.dart';

/// 本体进化候选。应用 [edits] 到 parent 层即得候选层。
class OntologyVariant {
  const OntologyVariant({
    required this.id,
    required this.parentVersion,
    required this.edits,
    required this.createdAt,
    this.reason,
  });

  factory OntologyVariant.fromJson(Map<String, Object?> json) => OntologyVariant(
        id: json['id']! as String,
        parentVersion: json['parentVersion']! as String,
        edits: <TypedEdit>[
          for (final Object? edit in json['edits']! as List)
            TypedEdit.fromJson(Map<String, Object?>.from(edit! as Map)),
        ],
        createdAt: DateTime.parse(json['createdAt']! as String),
        reason: json['reason'] as String?,
      );

  final String id;
  final String parentVersion;
  final List<TypedEdit> edits;
  final DateTime createdAt;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'parentVersion': parentVersion,
        'edits': <Map<String, Object?>>[
          for (final TypedEdit edit in edits) edit.toJson(),
        ],
        'createdAt': createdAt.toIso8601String(),
        'reason': reason,
      };
}

/// 从轨迹进化：诊断 → 归因 → 生成 edits → 验证。
///
/// 轨迹不足 [minOccurrences] 条时返回 `null`；edits 通过 schema 验证后才返回
/// 候选，否则抛 [StateError]。提供 [sources] 时对新 Term 做接地验证。
Future<OntologyVariant?> evolveVariant({
  required LlmProvider llm,
  required OntologyLayer current,
  required List<SessionEvent> trajectories,
  int minOccurrences = 3,
  List<DataSource>? sources,
}) async {
  if (trajectories.length < minOccurrences) return null;
  final SemanticDiagnosis diagnosis = await diagnose(llm, trajectories);
  final List<Attribution> attributions =
      await AttributionEngine(llm: llm).attribute(diagnosis, current);
  final List<TypedEdit> edits = await generateEdits(llm, attributions, current);
  _validateEdits(edits, current);
  if (sources != null) _groundEdits(edits, sources);
  return OntologyVariant(
    id: 'variant-${DateTime.now().microsecondsSinceEpoch}',
    parentVersion: current.version,
    edits: edits,
    createdAt: DateTime.now(),
    reason: '基于 ${trajectories.length} 条轨迹进化',
  );
}

void _validateEdits(List<TypedEdit> edits, OntologyLayer layer) {
  final TypedEditValidator validator = TypedEditValidator(layer.schema);
  for (final TypedEdit edit in edits) {
    final ValidationResult result = validator.validate(edit, layer);
    if (!result.isValid) {
      throw StateError('编辑校验失败: ${result.message}');
    }
  }
}

void _groundEdits(List<TypedEdit> edits, List<DataSource> sources) {
  for (final TypedEdit edit in edits) {
    if (edit is! AddNode || edit.node is! Term) continue;
    final GroundingResult result = groundTerm(edit.node as Term, sources);
    if (!result.grounded) {
      throw StateError('新术语 ${(edit.node as Term).name} 未通过接地验证');
    }
  }
}

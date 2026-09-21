/// OntologyService：本体层的浏览、解析、构建、进化与门控发布。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../builder/source.dart';
import '../evolver/evaluator.dart';
import '../evolver/evolver.dart';
import '../ontology/layer.dart';
import 'browse.dart';
import 'resolve.dart';

/// 本体事件（发布/拒绝的变更流）。
sealed class OntologyEvent {
  const OntologyEvent(this.variant);

  final OntologyVariant variant;
}

/// 本体发布成功。
class OntologyPublished extends OntologyEvent {
  const OntologyPublished(super.variant, this.layer);

  final OntologyLayer layer;
}

/// 本体候选被拒绝。
class OntologyRejected extends OntologyEvent {
  const OntologyRejected(super.variant, this.reason);

  final String reason;
}

/// 本体服务。
abstract class OntologyService {
  /// 当前生效层；未构建时为 `null`。
  OntologyLayer? get current;

  /// 已发布的所有版本。
  List<OntologyLayer> get versions;

  /// 从持久化存档恢复。
  Future<void> restore();

  /// 浏览本体层，返回节点摘要。
  Future<List<NodeSummary>> browse({String? type, String? query, int limit = 20});

  /// 解析术语（按名/别名），返回完整记录与关联对象。
  Future<ResolvedSemantics?> resolve(String term);

  /// 从数据源构建初始本体层。
  Future<OntologyLayer> build({
    required List<DataSource> sources,
    String version = 'ontology_v0',
  });

  /// 从轨迹进化：诊断 → 归因 → 生成 typed edits，产出候选。
  Future<OntologyVariant> evolve({
    required List<SessionEvent> trajectories,
    int minOccurrences = 3,
  });

  /// Backbone-conditional 配对评估候选。
  Future<ConditionalEvalResult> evaluate(OntologyVariant candidate);

  /// 发布或拒绝候选。
  Future<bool> publish(OntologyVariant candidate, {double threshold = 0.05});

  /// 回滚到指定版本。
  Future<void> rollback(String version);

  /// 变更流（发布/拒绝）。
  Stream<OntologyEvent> get changes;

  /// 释放资源。
  void dispose();
}

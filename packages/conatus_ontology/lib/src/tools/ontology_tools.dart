/// 面向模型的三个本体工具：浏览 / 解析 / 会话清单。
library;

import 'dart:convert';

import 'package:conatus_foundation/conatus_foundation.dart';

import '../ontology/layer.dart';
import '../runtime/browse.dart';
import '../runtime/manifest.dart';
import '../runtime/resolve.dart';
import '../runtime/service.dart';

/// 浏览本体层中的语义对象。返回摘要，不返回完整记录。
class BrowseSemanticsTool extends Tool {
  const BrowseSemanticsTool({required this.ontology});

  final OntologyService ontology;

  @override
  String get name => 'browse_semantics';

  @override
  String get description => '浏览本体层中的语义对象。返回摘要，不返回完整记录。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.enumeration(
            'type', const <String>['term', 'mapping', 'constraint', 'evidence'],
            description: '节点类型过滤'),
        ParamSpec.string('query', description: '搜索词'),
        ParamSpec.integer('limit', description: '返回数量上限，默认 20'),
      ];

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Future<ToolResult> call(ToolContext context) async {
    final List<NodeSummary> nodes = await ontology.browse(
      type: context.string('type'),
      query: context.string('query'),
      limit: context.integer('limit') ?? 20,
    );
    return ToolResult.success(
      jsonEncode(<Map<String, Object?>>[
        for (final NodeSummary node in nodes) node.toJson(),
      ]),
      value: <Map<String, Object?>>[
        for (final NodeSummary node in nodes) node.toJson(),
      ],
    );
  }
}

/// 解析术语语义。返回完整记录 + 关联对象。
class ResolveSemanticsTool extends Tool {
  const ResolveSemanticsTool({required this.ontology});

  final OntologyService ontology;

  @override
  String get name => 'resolve_semantics';

  @override
  String get description => '解析术语的完整语义：定义、映射、约束、证据与关联关系。';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('term', description: '术语名或别名', required: true),
      ];

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Future<ToolResult> call(ToolContext context) async {
    final ResolvedSemantics? resolved =
        await ontology.resolve(context.str('term'));
    if (resolved == null) {
      return ToolResult.failure('术语未找到',
          error: const ToolError('TERM_NOT_FOUND', '本体中不存在该术语'));
    }
    return ToolResult.success(jsonEncode(resolved.toJson()),
        value: resolved.toJson());
  }
}

/// 输出本体的紧凑会话清单。
class OntologyManifestTool extends Tool {
  const OntologyManifestTool({required this.ontology});

  final OntologyService ontology;

  @override
  String get name => 'ontology_manifest';

  @override
  String get description => '输出本体的紧凑清单：术语/映射/约束数量与核心术语摘要。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Future<ToolResult> call(ToolContext context) async {
    final OntologyLayer? layer = ontology.current;
    if (layer == null) return ToolResult.failure('本体尚未构建');
    final String manifest = buildManifest(layer);
    return ToolResult.success(manifest, value: <String, Object?>{'manifest': manifest});
  }
}

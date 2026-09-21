/// MCP 工具注册：把本体工具注册进 ctx.tools。
///
/// MCP 适配由外部 `conatus_mcp` 的 `McpToolAdapter` 衔接——注册进
/// `ToolRegistry` 的本地工具即可被 MCP 协议暴露。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import '../runtime/service.dart';
import '../tools/ontology_tools.dart';

/// 注册三个本体工具到上下文工具注册表。
///
/// 返回 [Disposer]，调用后注销全部工具。
Disposer registerOntologyTools(Context ctx, {required OntologyService ontology}) {
  final ToolRegistry tools = ctx.require<ToolRegistry>('tools');
  final Disposer browse = tools.register(BrowseSemanticsTool(ontology: ontology));
  final Disposer resolve =
      tools.register(ResolveSemanticsTool(ontology: ontology));
  final Disposer manifest =
      tools.register(OntologyManifestTool(ontology: ontology));
  return () {
    browse();
    resolve();
    manifest();
  };
}

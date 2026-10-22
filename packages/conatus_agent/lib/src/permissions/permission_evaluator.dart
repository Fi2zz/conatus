/// 一次工具调用的权限判定（含工作区外路径的 `external_directory` 追加检查）。
///
/// 主判定用工具动作 + 规范化资源；路径动作的目标落在工作区外时，再按
/// `external_directory` 动作对目录边界判定一次。两条判定取更严格者
/// （deny > ask > allow），因此用户既能写 `read` / `edit` 规则，也能写
/// `external_directory` 规则单独管控越界访问。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../approval_gate.dart' show pathArguments;
import 'permission_action.dart';
import 'permission_decision.dart';
import 'permission_effect.dart';
import 'permission_engine.dart';
import 'permission_path.dart';
import 'permission_scope.dart';
import 'permission_verdict.dart';

/// 工作区外路径检查使用的动作名。
const String kExternalDirectoryAction = 'external_directory';

/// 绑定交互模式与工作区的判定器。
class PermissionEvaluator {
  /// [workdir] 为 `null` 时跳过 `external_directory` 检查（无法判断边界）。
  const PermissionEvaluator({required this.interactive, this.workdir});

  /// 是否有人可应答；false（headless）时路径兜底不触发。
  final bool interactive;

  /// 工作区根目录（来自上下文的 `'workdir'` 服务）。
  final String? workdir;

  /// 判定一次调用。
  PermissionDecision evaluate(
    Tool tool,
    ToolCall call,
    PermissionScope scope,
  ) {
    final List<String> pathArgs = pathArguments(tool, call);
    final String action = permissionActionFor(call.name);
    final List<String> resources = permissionResourcesFor(call, pathArgs);
    const PermissionEngine engine = PermissionEngine();
    final PermissionVerdict primary = engine.evaluate(
      action: action,
      resources: resources,
      risk: tool.riskLevel,
      scope: scope,
    );
    final List<String> targetPaths = permissionPathsFor(call, pathArgs);
    final PermissionVerdict? external = _outsideVerdict(engine, (
      action: action,
      paths: targetPaths,
      risk: tool.riskLevel,
      scope: scope,
    ));
    final PermissionVerdict verdict =
        external != null && external.effect.index > primary.effect.index
            ? external
            : primary;
    final bool fallback =
        primary.rule == null && (external == null || external.rule == null);
    final bool pathFallback = interactive &&
        verdict.effect == PermissionEffect.allow &&
        fallback &&
        pathArgs.isNotEmpty &&
        scope.askThreshold != null;
    return PermissionDecision(
      effect: pathFallback ? PermissionEffect.ask : verdict.effect,
      action: action,
      resources: resources,
      pathArgs: pathArgs,
      verdict: verdict,
      fallback: fallback,
    );
  }

  PermissionVerdict? _outsideVerdict(
    PermissionEngine engine,
    ({
      String action,
      List<String> paths,
      ToolRisk risk,
      PermissionScope scope,
    }) input,
  ) {
    final String? root = workdir;
    if (root == null || !permissionActionUsesPath(input.action)) return null;
    final Set<String> boundaries = <String>{
      for (final String path in input.paths)
        if (!permissionPathUnder(path, root))
          permissionDirectoryBoundary(resolvePermissionPath(path, root)),
    };
    if (boundaries.isEmpty) return null;
    return engine.evaluate(
      action: kExternalDirectoryAction,
      resources: boundaries.toList(growable: false),
      risk: input.risk,
      scope: input.scope,
    );
  }
}

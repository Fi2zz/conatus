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
import 'permission_rule.dart';
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
    final PermissionScope expanded = _expandRules(scope, workdir);
    PermissionVerdict primary = _withResources(
      engine.evaluate(
        action: action,
        resources: _spellings(action, resources, workdir),
        risk: tool.riskLevel,
        scope: expanded,
      ),
      resources,
    );
    // 旧式 MCP 资源规则（`<server>_list_mcp_resources`）仍生效：别名与现行
    // 动作同时判定，取更严格者（allow < ask < deny）。
    final String? alias = mcpResourceAliasAction(call);
    if (alias != null) {
      final PermissionVerdict legacy = _withResources(
        engine.evaluate(
          action: alias,
          resources: <String>[...resources, '*'],
          risk: tool.riskLevel,
          scope: expanded,
        ),
        resources,
      );
      if (legacy.effect.index > primary.effect.index) primary = legacy;
    }
    final List<String> targetPaths = permissionBoundaryPathsFor(call, pathArgs);
    final PermissionVerdict? external = _outsideVerdict(engine, (
      action: action,
      paths: targetPaths,
      risk: tool.riskLevel,
      scope: expanded,
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

  /// 判定结果对外只暴露调用方看到的资源（词法拼写）；内部匹配用的 workdir /
  /// 真实路径拼写不上屏、不进遥测，否则同一次调用看起来像读了两个文件。
  PermissionVerdict _withResources(
    PermissionVerdict verdict,
    List<String> resources,
  ) =>
      PermissionVerdict(
        effect: verdict.effect,
        action: verdict.action,
        resources: resources,
        rule: verdict.rule,
      );

  /// 规则展开缓存：同一作用域对象（规则列表身份稳定）只做一次真实路径 IO。
  ///
  /// 规则展开原本每次工具调用都做，路径规则多时会把 `resolveSymbolicLinksSync`
  /// 堆在 TUI 事件循环上。作用域只在配置 / 会话 / 模式变化时替换，因此按
  /// workdir + 规则列表身份缓存；上限 8，够覆盖根作用域与子 Agent。
  static final Map<String, PermissionScope> _expandedScopes =
      <String, PermissionScope>{};
  static final Map<String, String?> _canonicalRoots = <String, String?>{};

  /// 规则里路径 pattern 的全部拼写（词法 / workdir / 真实路径）。
  ///
  /// 规则展开发生在判定时，因此库用法（不经过 `PermissionWiring`）也享有
  /// 同一套拼写；已展开的规则再次展开是幂等的。
  PermissionScope _expandRules(PermissionScope scope, String? root) {
    if (root == null || root.isEmpty) return scope;
    final String key =
        '$root#${identityHashCode(scope.rules)}#${scope.rules.length}';
    final PermissionScope? cached = _expandedScopes[key];
    if (cached != null) return cached;
    final List<PermissionRule> rules = <PermissionRule>[];
    for (final PermissionRule rule in scope.rules) {
      if (!permissionActionUsesPath(rule.action)) {
        rules.add(rule);
        continue;
      }
      for (final String spelling in permissionPatternSpellings(
        rule.resource,
        root,
      )) {
        rules.add(spelling == rule.resource
            ? rule
            : PermissionRule(
                action: rule.action,
                resource: spelling,
                effect: rule.effect,
                source: rule.source,
                configuredResource: rule.displayResource,
              ));
      }
    }
    final PermissionScope expanded = PermissionScope(
      rules: rules,
      askThreshold: scope.askThreshold,
      agentId: scope.agentId,
    );
    if (_expandedScopes.length >= 8) {
      _expandedScopes.remove(_expandedScopes.keys.first);
    }
    _expandedScopes[key] = expanded;
    return expanded;
  }

  /// 调用侧资源拼写：路径动作补 workdir / 真实路径，非路径动作原样。
  List<String> _spellings(
    String action,
    List<String> resources,
    String? root,
  ) {
    if (!permissionActionUsesPath(action)) return resources;
    final Set<String> spellings = <String>{};
    for (final String resource in resources) {
      spellings.addAll(
        action == 'glob'
            ? permissionPatternSpellings(resource, root)
            : permissionPathSpellings(resource, root),
      );
    }
    return spellings.toList(growable: false);
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
    if (root == null || input.paths.isEmpty) return null;
    final String? realRoot = _canonicalRoots.putIfAbsent(
      root,
      () => canonicalPermissionPath(root),
    );
    final Set<String> roots = <String>{
      normalizePermissionPath(root),
      if (realRoot != null) normalizePermissionPath(realRoot),
    };
    final Set<String> boundaries = <String>{};
    for (final String path in input.paths) {
      final String resolved = resolvePermissionPath(path, root);
      final String identity = canonicalPermissionPath(resolved) ?? resolved;
      if (roots.any((String base) => permissionPathUnder(identity, base))) {
        continue;
      }
      boundaries.add(permissionDirectoryBoundary(identity));
    }
    if (boundaries.isEmpty) return null;
    return engine.evaluate(
      action: kExternalDirectoryAction,
      resources: boundaries.toList(growable: false),
      risk: input.risk,
      scope: input.scope,
    );
  }
}

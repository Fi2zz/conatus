/// 权限引擎：规则优先级、多资源聚合与 `askThreshold` 兜底。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

PermissionVerdict _evaluate({
  String action = 'shell',
  List<String> resources = const <String>['git status'],
  ToolRisk risk = ToolRisk.low,
  PermissionScope scope = const PermissionScope(),
}) =>
    const PermissionEngine().evaluate(
      action: action,
      resources: resources,
      risk: risk,
      scope: scope,
    );

void main() {
  group('无规则命中时按 askThreshold 兜底', () {
    test('askThreshold 为 null 时全放行', () {
      for (final ToolRisk risk in ToolRisk.values) {
        expect(_evaluate(risk: risk).effect, PermissionEffect.allow);
      }
    });

    test('askThreshold 为 medium 时 low 放行、medium/high 询问', () {
      const PermissionScope scope =
          PermissionScope(askThreshold: ToolRisk.medium);
      expect(_evaluate(scope: scope).effect, PermissionEffect.allow);
      expect(_evaluate(risk: ToolRisk.medium, scope: scope).effect,
          PermissionEffect.ask);
      expect(_evaluate(risk: ToolRisk.high, scope: scope).effect,
          PermissionEffect.ask);
    });

    test('askThreshold 为 high 时只有 high 询问', () {
      const PermissionScope scope =
          PermissionScope(askThreshold: ToolRisk.high);
      expect(_evaluate(scope: scope).effect, PermissionEffect.allow);
      expect(_evaluate(risk: ToolRisk.medium, scope: scope).effect,
          PermissionEffect.allow);
      expect(_evaluate(risk: ToolRisk.high, scope: scope).effect,
          PermissionEffect.ask);
    });

    test('资源列表为空也走兜底', () {
      final PermissionVerdict verdict = _evaluate(
        resources: const <String>[],
        risk: ToolRisk.high,
        scope: const PermissionScope(askThreshold: ToolRisk.high),
      );
      expect(verdict.effect, PermissionEffect.ask);
      expect(verdict.rule, isNull);
    });

    test('兜底 allow 的 verdict 不带规则，但保留动作与资源', () {
      final PermissionVerdict verdict =
          _evaluate(action: 'read', resources: const <String>['a.txt']);
      expect(verdict.effect, PermissionEffect.allow);
      expect(verdict.rule, isNull);
      expect(verdict.action, 'read');
      expect(verdict.resources, <String>['a.txt']);
    });
  });

  group('规则命中优先于兜底', () {
    test('显式 deny 在 askThreshold 为 null 时依然生效', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      final PermissionVerdict verdict = _evaluate(
        resources: const <String>['git push origin main'],
        risk: ToolRisk.high,
        scope: scope,
      );
      expect(verdict.effect, PermissionEffect.deny);
      expect(verdict.rule!.resource, 'git push *');
    });

    test('显式 allow 压过高风险阈值', () {
      const PermissionScope scope = PermissionScope(
        askThreshold: ToolRisk.high,
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git status *',
            effect: PermissionEffect.allow,
          ),
        ],
      );
      final PermissionVerdict verdict = _evaluate(
        resources: const <String>['git status --short'],
        risk: ToolRisk.high,
        scope: scope,
      );
      expect(verdict.effect, PermissionEffect.allow);
      expect(verdict.rule!.resource, 'git status *');
    });

    test('action 不同的规则不参与判定', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: '*',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      expect(_evaluate(action: 'read', scope: scope).effect,
          PermissionEffect.allow);
    });
  });

  group('多资源聚合', () {
    test('任一资源 deny 压过其他资源的 ask / allow', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: '*',
            effect: PermissionEffect.allow,
          ),
          PermissionRule(
            action: 'shell',
            resource: 'rm *',
            effect: PermissionEffect.deny,
          ),
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.ask,
          ),
        ],
      );
      final PermissionVerdict verdict = _evaluate(
        resources: const <String>['git status', 'git push origin', 'rm -rf x'],
        scope: scope,
      );
      expect(verdict.effect, PermissionEffect.deny);
      expect(verdict.rule!.resource, 'rm *');
      expect(verdict.resources,
          <String>['git status', 'git push origin', 'rm -rf x']);
    });

    test('无 deny 时任一 ask 压过 allow', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git *',
            effect: PermissionEffect.allow,
          ),
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.ask,
          ),
        ],
      );
      final PermissionVerdict verdict = _evaluate(
        resources: const <String>['git status', 'git push origin'],
        scope: scope,
      );
      expect(verdict.effect, PermissionEffect.ask);
      expect(verdict.rule!.resource, 'git push *');
    });

    test('同级的最后一条规则作为判定规则', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'edit',
            resource: 'a*',
            effect: PermissionEffect.deny,
            source: 'config',
          ),
          PermissionRule(
            action: 'edit',
            resource: 'b*',
            effect: PermissionEffect.deny,
            source: 'session',
          ),
        ],
      );
      final PermissionVerdict verdict = _evaluate(
        action: 'edit',
        resources: const <String>['a.txt', 'b.txt'],
        scope: scope,
      );
      expect(verdict.effect, PermissionEffect.deny);
      expect(verdict.rule!.source, 'session');
    });
  });

  group('最后匹配生效', () {
    test('动作交错时同一动作仍按列表顺序覆盖', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: 'git *',
            effect: PermissionEffect.deny,
          ),
          PermissionRule(
            action: 'edit',
            resource: '*',
            effect: PermissionEffect.allow,
          ),
          PermissionRule(
            action: 'shell',
            resource: 'git status *',
            effect: PermissionEffect.allow,
            source: 'session',
          ),
          PermissionRule(
            action: 'read',
            resource: '*',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      expect(
        _evaluate(
          resources: const <String>['git status --short'],
          scope: scope,
        ).rule!.source,
        'session',
      );
      expect(
          _evaluate(resources: const <String>['git push'], scope: scope).effect,
          PermissionEffect.deny);
      expect(
        _evaluate(
                action: 'edit',
                resources: const <String>['a.dart'],
                scope: scope)
            .effect,
        PermissionEffect.allow,
      );
      expect(
        _evaluate(
                action: 'read',
                resources: const <String>['a.dart'],
                scope: scope)
            .effect,
        PermissionEffect.deny,
      );
    });

    test('后置 deny 覆盖前置 allow', () {
      const PermissionScope scope = PermissionScope(
        rules: <PermissionRule>[
          PermissionRule(
            action: 'shell',
            resource: '*',
            effect: PermissionEffect.allow,
          ),
          PermissionRule(
            action: 'shell',
            resource: 'git push *',
            effect: PermissionEffect.deny,
          ),
        ],
      );
      expect(
        _evaluate(
                resources: const <String>['git push origin main'], scope: scope)
            .effect,
        PermissionEffect.deny,
      );
    });
  });
}

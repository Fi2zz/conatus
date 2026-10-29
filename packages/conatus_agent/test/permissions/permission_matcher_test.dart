/// 权限规则通配匹配器。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

void main() {
  group('permissionPatternMatches', () {
    test('shell pattern trailing " *" matches bare command', () {
      expect(permissionPatternMatches('git status *', 'git status'), isTrue);
      expect(permissionPatternMatches('git status *', 'git status --short'),
          isTrue);
      expect(permissionPatternMatches('git status *', 'git stash'), isFalse);
    });

    test('star matches any characters including slash', () {
      expect(permissionPatternMatches('src/*.dart', 'src/a/b.dart'), isTrue);
      expect(permissionPatternMatches('src/*.dart', 'src/a.dart'), isTrue);
      expect(permissionPatternMatches('*', ''), isTrue);
      expect(permissionPatternMatches('a*c', 'ac'), isTrue);
    });

    test('question mark matches exactly one character', () {
      expect(permissionPatternMatches('a?c', 'abc'), isTrue);
      expect(permissionPatternMatches('a?c', 'ac'), isFalse);
      expect(permissionPatternMatches('a?c', 'abbc'), isFalse);
      expect(permissionPatternMatches('?', '/'), isTrue);
    });

    test('pattern is anchored to the whole value', () {
      expect(permissionPatternMatches('a', 'xa'), isFalse);
      expect(permissionPatternMatches('a', 'ax'), isFalse);
      expect(permissionPatternMatches('*.env', 'prod.env'), isTrue);
      expect(permissionPatternMatches('*.env', 'prod.env.bak'), isFalse);
      expect(permissionPatternMatches('a.c', 'abc'), isFalse);
    });

    test('matching is case-sensitive', () {
      expect(permissionPatternMatches('Git *', 'git status'), isFalse);
      expect(permissionPatternMatches('Src/*', 'src/a.dart'), isFalse);
    });

    test('regex metacharacters in pattern are literal', () {
      expect(permissionPatternMatches('a.b', 'a.b'), isTrue);
      expect(permissionPatternMatches('a.b', 'axb'), isFalse);
      expect(permissionPatternMatches(r'$HOME/*', r'$HOME/x'), isTrue);
      expect(permissionPatternMatches('a+b', 'aab'), isFalse);
    });

    test('trailing " *" accepts the bare value only as a suffix rule', () {
      expect(permissionPatternMatches('git *', 'git'), isTrue);
      expect(permissionPatternMatches('git status *', 'git status '), isTrue);
      expect(permissionPatternMatches('git * ', 'git'), isFalse);
    });
  });

  group('lastMatchingRule', () {
    test('last matching rule wins and deny wins across resources', () {
      final List<PermissionRule> rules = <PermissionRule>[
        const PermissionRule(
            action: 'edit', resource: '*', effect: PermissionEffect.allow),
        const PermissionRule(
            action: 'edit', resource: '*.env', effect: PermissionEffect.deny),
      ];
      expect(lastMatchingRule(rules, 'edit', 'src/a.dart')!.effect,
          PermissionEffect.allow);
      expect(lastMatchingRule(rules, 'edit', 'config/.env')!.effect,
          PermissionEffect.deny);
    });

    test('action must match exactly', () {
      final List<PermissionRule> rules = <PermissionRule>[
        const PermissionRule(
            action: 'edit', resource: '*', effect: PermissionEffect.deny),
      ];
      expect(lastMatchingRule(rules, 'read', 'src/a.dart'), isNull);
      expect(lastMatchingRule(rules, 'Edit', 'src/a.dart'), isNull);
    });

    test('returns null when no resource pattern matches', () {
      final List<PermissionRule> rules = <PermissionRule>[
        const PermissionRule(
            action: 'bash',
            resource: 'git status *',
            effect: PermissionEffect.allow),
      ];
      expect(lastMatchingRule(rules, 'bash', 'git push'), isNull);
      expect(lastMatchingRule(rules, 'bash', 'git status'), isNotNull);
      expect(lastMatchingRule(const <PermissionRule>[], 'bash', 'git status'),
          isNull);
    });

    test('later rule overrides earlier rule for the same resource', () {
      final List<PermissionRule> rules = <PermissionRule>[
        const PermissionRule(
            action: 'bash', resource: 'git *', effect: PermissionEffect.deny),
        const PermissionRule(
            action: 'bash',
            resource: 'git status *',
            effect: PermissionEffect.allow,
            source: 'session'),
      ];
      final PermissionRule? rule =
          lastMatchingRule(rules, 'bash', 'git status --short');
      expect(rule!.effect, PermissionEffect.allow);
      expect(rule.source, 'session');
    });
  });
}

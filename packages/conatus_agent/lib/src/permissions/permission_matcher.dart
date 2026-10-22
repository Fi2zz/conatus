/// 权限规则的通配匹配。
///
/// 匹配只做字符串通配，**不做**路径规范化、大小写折叠或 `~` 展开——这些属于
/// 调用方（工具参数抽取层）的职责。规则里 `*` 匹配任意长度的字符（含 `/`），
/// `?` 匹配恰好一个字符，pattern 整值锚定。
library;

import 'permission_rule.dart';

/// pattern 末尾的「空格 + 星号」后缀，用于兼容命令族写法。
const String _trailingStarSuffix = ' *';

/// 判断 [value] 是否匹配通配 [pattern]（大小写敏感、整值锚定）。
///
/// 追加语义：以 ` *` 结尾的 pattern 也匹配去掉该后缀的精确值，因此
/// `git status *` 同时匹配 `git status` 与 `git status --short`。
bool permissionPatternMatches(String pattern, String value) {
  final RegExp expression = RegExp(_patternToRegex(pattern), dotAll: true);
  return expression.hasMatch(value) || _matchesBareValue(pattern, value);
}

/// 把通配 pattern 转成整值锚定的正则源码：`*` → `.*`、`?` → `.`，
/// 其余字符（含正则元字符）按字面量转义。
String _patternToRegex(String pattern) {
  final StringBuffer buffer = StringBuffer('^');
  for (final int rune in pattern.runes) {
    final String char = String.fromCharCode(rune);
    if (char == '*') {
      buffer.write('.*');
    } else if (char == '?') {
      buffer.write('.');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  buffer.write(r'$');
  return buffer.toString();
}

/// pattern 以 ` *` 结尾时，接受去掉后缀后的精确值。
bool _matchesBareValue(String pattern, String value) {
  if (!pattern.endsWith(_trailingStarSuffix)) return false;
  final String bare =
      pattern.substring(0, pattern.length - _trailingStarSuffix.length);
  return bare == value;
}

/// 返回最后一条命中的规则；没有命中返回 `null`。
///
/// 先按 [action] 精确过滤，再按 [resource] 通配匹配。列表顺序即优先级：
/// 后出现的规则覆盖先出现的规则。
PermissionRule? lastMatchingRule(
  List<PermissionRule> rules,
  String action,
  String resource,
) {
  PermissionRule? matched;
  for (final PermissionRule rule in rules) {
    if (rule.action != action) continue;
    if (permissionPatternMatches(rule.resource, resource)) matched = rule;
  }
  return matched;
}

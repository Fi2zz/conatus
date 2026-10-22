/// 项目级权限规则存储：`{"version":1,"rules":[...]}` 的原子落盘与容错载入。
///
/// 写入先落到同目录临时文件、收紧 0600 后再 rename，读者永远看不到半截 JSON；
/// 载入把缺失 / 损坏 / 版本不符 / 单条非法一律当「没有规则」，**不抛异常**：
/// 权限文件坏掉时应回落到更保守的兜底阈值，而不是让整个 Agent 起不来。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_effect.dart';
import 'permission_rule.dart';

/// 当前落盘格式版本。
const int _storeVersion = 1;

/// 单文件 JSON 规则存储。
class PermissionStore {
  /// 创建指向 [path] 的存储；文件按需创建。
  PermissionStore(this.path);

  /// JSON 文件路径。
  final String path;

  /// 读取全部规则；文件不存在或内容不可用时返回空列表。
  Future<List<PermissionRule>> load() async {
    final File file = File(path);
    try {
      if (!await file.exists()) return const <PermissionRule>[];
      return _decode(jsonDecode(await file.readAsString()));
    } on FormatException {
      return const <PermissionRule>[];
    } on FileSystemException {
      return const <PermissionRule>[];
    }
  }

  /// 用 [rules] 整体替换文件内容（原子发布 + 0600）。
  Future<void> save(List<PermissionRule> rules) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    final String encoded = '${jsonEncode(_encode(rules))}\n';
    final File temp =
        File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsString(encoded, flush: true);
      await restrictFilePermissions(temp.path);
      await temp.rename(path);
    } on FileSystemException {
      await _discard(temp);
      rethrow;
    }
  }

  /// 载入 → 追加 → 整体保存。
  ///
  /// 读改写之间不加锁：同一进程内应串行调用（权限写入本来就低频）。
  Future<void> add(PermissionRule rule) async {
    final List<PermissionRule> rules = await load();
    await save(<PermissionRule>[...rules, rule]);
  }

  /// 临时文件清理失败不覆盖原始错误。
  Future<void> _discard(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } on FileSystemException {
      // 原始错误更重要：残留临时文件不影响正确性。
    }
  }
}

/// 编码为落盘结构。
Map<String, Object?> _encode(List<PermissionRule> rules) => <String, Object?>{
      'version': _storeVersion,
      'rules': rules.map(_encodeRule).toList(),
    };

/// 编码单条规则；[PermissionRule.source] 为空时不写键。
Map<String, Object?> _encodeRule(PermissionRule rule) {
  final Map<String, Object?> json = <String, Object?>{
    'action': rule.action,
    'resource': rule.resource,
    'effect': rule.effect.name,
  };
  final String? source = rule.source;
  if (source != null) json['source'] = source;
  return json;
}

/// 解码落盘结构；版本不符或形状不对返回空列表。
List<PermissionRule> _decode(Object? json) {
  if (json is! Map<String, Object?>) return const <PermissionRule>[];
  if (json['version'] != _storeVersion) return const <PermissionRule>[];
  final Object? raw = json['rules'];
  if (raw is! List<Object?>) return const <PermissionRule>[];
  final List<PermissionRule> rules = <PermissionRule>[];
  for (final Object? entry in raw) {
    final PermissionRule? rule = _decodeRule(entry);
    if (rule != null) rules.add(rule);
  }
  return rules;
}

/// 解码单条规则；任何字段非法返回 `null`（调用方跳过该条）。
PermissionRule? _decodeRule(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final Object? action = json['action'];
  final Object? resource = json['resource'];
  final Object? source = json['source'];
  if (action is! String || action.isEmpty) return null;
  if (resource is! String || resource.isEmpty) return null;
  if (source != null && source is! String) return null;
  final PermissionEffect? effect = _parseEffect(json['effect']);
  if (effect == null) return null;
  return PermissionRule(
    action: action,
    resource: resource,
    effect: effect,
    source: source as String?,
  );
}

/// 按枚举名解析效果；未知值返回 `null`。
PermissionEffect? _parseEffect(Object? raw) {
  for (final PermissionEffect effect in PermissionEffect.values) {
    if (effect.name == raw) return effect;
  }
  return null;
}

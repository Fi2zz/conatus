/// 项目级权限规则存储：`{"version":1,"rules":[...]}` 的原子落盘与容错载入。
///
/// 写入先落到同目录临时文件、收紧 0600 后再 rename，读者永远看不到半截 JSON；
/// [PermissionStore.load] 把缺失 / 损坏 / 版本不符 / 单条非法一律当「没有规则」，
/// **不抛异常**：权限文件坏掉时应回落到更保守的兜底阈值，而不是让整个 Agent
/// 起不来。但**写入**不允许把「读不懂」当成「没有规则」——[PermissionStore.add]
/// 对已存在却解不开的文件抛 [PermissionStoreException]，绝不覆盖用户手写的规则。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'permission_effect.dart';
import 'permission_rule.dart';

/// 当前落盘格式版本。
const int _storeVersion = 1;

/// 权限存储无法安全完成写入时抛出（例如已有文件损坏、拒绝覆盖）。
class PermissionStoreException implements Exception {
  /// 创建异常。
  PermissionStoreException(this.message);

  /// 面向用户的说明（含文件路径）。
  final String message;

  @override
  String toString() => 'PermissionStoreException($message)';
}

/// 单文件 JSON 规则存储。
class PermissionStore {
  /// 创建指向 [path] 的存储；文件按需创建。
  PermissionStore(this.path);

  /// JSON 文件路径。
  final String path;

  /// 最近一次 [load] 的失败原因；成功 / 文件缺失为 `null`。
  ///
  /// 载入失败仍然按「没有规则」处理（fail-open 保证 Agent 能启动），但调用方
  /// 要把这条原因摊给用户：静默禁用全部 deny 是最危险的一种「看起来正常」。
  String? get loadError => _loadError;
  String? _loadError;

  /// 最近一次 [load] 跳过的非法规则条数（单条坏规则不整体失败）。
  int get skippedRules => _skippedRules;
  int _skippedRules = 0;

  /// 读取全部规则；文件不存在或内容不可用时返回空列表。
  ///
  /// 单条非法规则被跳过，其余照常返回；版本 / 形状不符整体视为不可用。
  Future<List<PermissionRule>> load() async {
    _loadError = null;
    _skippedRules = 0;
    try {
      final File file = File(path);
      if (!await file.exists()) return <PermissionRule>[];
      final Object? json = jsonDecode(await file.readAsString());
      final List<PermissionRule>? rules = _decode(json);
      if (rules == null) {
        _loadError = '权限文件 $path 的格式或版本无法识别，已按无规则启动';
        return <PermissionRule>[];
      }
      final Object? rawRules =
          json is Map<String, Object?> ? json['rules'] : null;
      if (rawRules is List<Object?>) {
        _skippedRules = rawRules.length - rules.length;
      }
      return rules;
    } on FormatException {
      _loadError = '权限文件 $path 不是合法 JSON，已按无规则启动';
      return <PermissionRule>[];
    } on FileSystemException catch (error) {
      _loadError = '权限文件 $path 读取失败（${error.message}），已按无规则启动';
      return <PermissionRule>[];
    }
  }

  /// 用 [rules] 整体替换文件内容（原子发布 + 0600）。
  ///
  /// rename 之后 best-effort 刷一次盘（`sync`）：目录项本身在 Dart 里拿不到
  /// 可 fsync 的句柄，不刷的话「总是允许」在崩溃后可能连文件一起消失，而用户
  /// 以为规则已经生效。写入本来就低频（每次「总是允许」一次），代价可接受。
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
      _syncParent();
    } on Object catch (_) {
      await _discard(temp);
      rethrow;
    }
  }

  /// 目录项落盘（best-effort；失败不影响已经成功的 rename）。
  void _syncParent() {
    if (Platform.isWindows) return;
    try {
      Process.runSync('sync', const <String>[]);
    } on ProcessException {
      // 没有 sync 命令的环境（极简容器）只能接受「已 flush 文件内容」。
    }
  }

  /// 载入 → 追加 → 整体保存。
  ///
  /// 文件不存在时直接建立；文件存在但解不开时抛 [PermissionStoreException]
  /// 并保留原文件原样（否则一次「总是允许」就会永久抹掉看不见的 deny 规则）。
  /// 读改写之间不加锁：同一进程内应串行调用（权限写入本来就低频）。
  Future<void> add(PermissionRule rule) async {
    final File file = File(path);
    if (!await file.exists()) {
      await save(<PermissionRule>[rule]);
      return;
    }
    final List<PermissionRule>? existing = await _readRules(file);
    if (existing == null) {
      throw PermissionStoreException('$path 不可读或内容损坏，拒绝覆盖已有规则');
    }
    await save(<PermissionRule>[...existing, rule]);
  }

  /// 读取并解码；不可读或不可解码返回 `null`（与「合法但为空」区分）。
  Future<List<PermissionRule>?> _readRules(File file) async {
    try {
      return _decode(jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// 临时文件清理失败不覆盖原始错误。
  Future<void> _discard(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } on Object {
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

/// 解码落盘结构；版本或形状不符返回 `null`（区别于合法的空规则列表）。
List<PermissionRule>? _decode(Object? json) {
  if (json is! Map<String, Object?>) return null;
  if (json['version'] != _storeVersion) return null;
  final Object? raw = json['rules'];
  if (raw is! List<Object?>) return null;
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
  final String? action = _nonEmptyString(json['action']);
  final String? resource = _nonEmptyString(json['resource']);
  final PermissionEffect? effect = _parseEffect(json['effect']);
  if (action == null || resource == null || effect == null) return null;
  final Object? source = json['source'];
  if (source != null && source is! String) return null;
  return PermissionRule(
    action: action,
    resource: resource,
    effect: effect,
    source: source as String?,
  );
}

/// 只接受非空字符串。
String? _nonEmptyString(Object? raw) =>
    raw is String && raw.isNotEmpty ? raw : null;

/// 按枚举名解析效果；未知值返回 `null`。
PermissionEffect? _parseEffect(Object? raw) {
  for (final PermissionEffect effect in PermissionEffect.values) {
    if (effect.name == raw) return effect;
  }
  return null;
}

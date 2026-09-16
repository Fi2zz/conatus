/// 技能来源契约：把某个外部存储里的技能列成候选，并按需加载正文。
library;

import 'skill_types.dart';

/// 一类技能来源。
///
/// [list] 在每个发现根上收集候选（`rank` 决定同名遮蔽）；[load] 在模型真正
/// 需要时返回正文，返回 `null` 表示该技能已消失（注册表据此失效缓存）。
abstract class SkillProvider {
  /// 供子类继承。
  const SkillProvider();

  /// provider 名，必须小写字母/数字并用 `-` 分隔，且在注册表内唯一。
  String get name;

  /// 列出当前可见的候选。
  Future<List<SkillCandidate>> list();

  /// 加载 [summary] 对应的完整定义。
  Future<SkillDefinition?> load(SkillSummary summary);
}

/// provider 侧的失败：`code` 稳定可判，`message` 面向排障。
class SkillProviderException implements Exception {
  /// 构造异常。
  const SkillProviderException(this.code, this.message);

  /// 稳定的机器可读错误码。
  final String code;

  /// 可读消息。
  final String message;

  @override
  String toString() => '$code: $message';
}

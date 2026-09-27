/// 用户目录解析：默认数据目录的统一归宿。
///
/// 所有默认目录都落在用户目录下，绝不在当前工作目录兜底：解析不到用户
/// 目录时抛 [StateError] 快速失败，由调用方决定如何呈现。
library;

import 'dart:io';

/// 环境变量 `CONATUS_HOME`：覆盖 conatus 的用户级数据根目录。
const String kConatusHomeEnv = 'CONATUS_HOME';

/// conatus 用户级数据根目录名（位于用户目录下）。
const String kConatusHomeDirName = '.conatus';

/// 解析用户目录：`HOME` → Windows `USERPROFILE` → 都没有抛 [StateError]。
///
/// [env] 可注入（测试用），缺省读进程环境。
String resolveHomeDir({Map<String, String>? env}) {
  final Map<String, String> source = env ?? Platform.environment;
  final String? home =
      _nonBlank(source['HOME']) ?? _nonBlank(source['USERPROFILE']);
  if (home != null) return home;
  throw StateError('无法定位用户目录：请设置 HOME 或 $kConatusHomeEnv 环境变量');
}

/// 解析 conatus 用户级数据根目录：`CONATUS_HOME` 非空优先，
/// 否则 `<用户目录>/.conatus`。
String resolveConatusHome({Map<String, String>? env}) {
  final Map<String, String> source = env ?? Platform.environment;
  final String? overridden = _nonBlank(source[kConatusHomeEnv]);
  if (overridden != null) return overridden;
  return '${resolveHomeDir(env: source)}'
      '${Platform.pathSeparator}$kConatusHomeDirName';
}

String? _nonBlank(String? value) {
  final String? trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

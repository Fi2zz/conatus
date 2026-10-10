/// 文件权限收紧：把落盘文件设为仅属主可读写（0600）。
///
/// 为什么需要：会话 JSONL 是**逐行落盘的完整对话与工具输出**——用户可能在里面
/// 粘贴过密钥、token、私有代码片段，而 Dart 写文件默认权限随 umask（通常
/// 0644），同机其他用户能直接读。conatus_code 对含明文 API Key 的 config.toml
/// 已按 600 收紧（`writeConfigFile`），本插件让同样敏感的会话文件与之一致。
///
/// 放在 foundation 是因为「文件权限策略」是基础设施关注点：会话持久化、
/// 检查点归档等落盘方都应复用同一份语义，而不是各写一遍 chmod。
library;

import 'dart:io';

/// 把 [path] 指向的文件权限收紧为 0600（属主读写，组 / 其他无任何权限）。
///
/// Windows 没有 POSIX 权限位，直接返回（不改动文件）。其余平台若有一步失败
/// （如 chmod 不在 PATH），让它抛出而非吞掉——权限没收紧成功就不该被当作
/// 已收紧，静默失败会把安全承诺变成空话。
Future<void> restrictFilePermissions(String path) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', <String>['600', path]);
}

/// 把 [path] 指向的目录权限收紧为 0700（属主可读写执行，组 / 其他无权限）。
///
/// 用途：检查点这类「按会话分目录承载敏感内容」的落盘面，收紧**外层目录**
/// 一次即可挡住其他用户遍历进去（比逐文件收紧更强、也更省）；文件自身的
/// 600 作为兜底。Windows 无 POSIX 权限位，直接返回；失败同样抛出。
Future<void> restrictDirectoryPermissions(String path) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', <String>['700', path]);
}

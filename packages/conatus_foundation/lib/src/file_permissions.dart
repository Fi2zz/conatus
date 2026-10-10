/// 文件权限收紧：把落盘文件设为仅属主可读写（0600）、目录仅属主可访问（0700）。
///
/// 为什么需要：会话 JSONL、检查点归档等都是**逐行落盘的完整对话与工作区内容**
/// ——用户可能在里面粘贴过密钥、token、私有代码片段，而 Dart 写文件默认权限随
/// umask（通常 0644/0755），同机其他用户能直接读。conatus_code 对含明文 API Key
/// 的 config.toml 已按 600 收紧（`writeConfigFile`），本插件让同样敏感的落盘面
/// 与之一致。
///
/// 放在 foundation 是因为「文件权限策略」是基础设施关注点：会话持久化、检查点
/// 归档等落盘方都应复用同一份语义，而不是各写一遍 chmod。
library;

import 'dart:io';

/// 把 [path] 指向的文件权限收紧为 0600（属主读写，组 / 其他无任何权限）。
///
/// Windows 没有 POSIX 权限位，直接返回（不改动文件）。其余平台若 chmod 返回
/// 非 0（只读文件系统 / 权限不足 / 路径不存在），抛出 [FileSystemException]——
/// 权限没收紧成功就不该被当作已收紧，静默失败会把安全承诺变成空话。
Future<void> restrictFilePermissions(String path) => _chmod(path, '600');

/// 把 [path] 指向的目录权限收紧为 0700（属主可读写执行，组 / 其他无权限）。
///
/// 用途：检查点这类「按会话分目录承载敏感内容」的落盘面，收紧**外层目录**
/// 一次即可挡住其他用户遍历进去（比逐文件收紧更强、也更省）；文件自身的
/// 600 作为兜底。语义与失败处理同 [restrictFilePermissions]。
Future<void> restrictDirectoryPermissions(String path) => _chmod(path, '700');

/// 执行 `chmod [mode] [path]` 并校验退出码；失败抛 [FileSystemException]。
Future<void> _chmod(String path, String mode) async {
  if (Platform.isWindows) return;
  final ProcessResult result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'chmod $mode 失败（退出码 ${result.exitCode}）',
      path,
    );
  }
}

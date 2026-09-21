import 'dart:io';

/// ripgrep 二进制来源。
enum RipgrepSource {
  /// 系统已安装的 rg。
  system,

  /// 随包打包的二进制。
  bundled,
}

/// ripgrep 二进制。
class RipgrepBinary {
  const RipgrepBinary({required this.path, required this.source});

  /// 可执行文件路径（系统 rg 为 'rg'，打包二进制为绝对路径）。
  final String path;

  /// 来源。
  final RipgrepSource source;

  /// 发现二进制：优先系统 rg，回退打包二进制；都找不到返回 null。
  ///
  /// [probeRg] 用于测试注入探测逻辑；[packageRoot] 为打包二进制的
  /// 查找根（`vendor/ripgrep/<platform>/rg`）。
  static RipgrepBinary? discover({
    String? packageRoot,
    bool Function()? probeRg,
  }) {
    if ((probeRg ?? _probeSystemRg)()) {
      return const RipgrepBinary(path: 'rg', source: RipgrepSource.system);
    }
    final String? bundled = _bundledPath(packageRoot);
    if (bundled != null && File(bundled).existsSync()) {
      return RipgrepBinary(path: bundled, source: RipgrepSource.bundled);
    }
    return null;
  }

  static bool _probeSystemRg() {
    try {
      return Process.runSync('rg', <String>['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static String? _bundledPath(String? packageRoot) {
    if (packageRoot == null) return null;
    final String platform = Platform.operatingSystem;
    final String exe = Platform.isWindows ? 'rg.exe' : 'rg';
    return '$packageRoot${Platform.pathSeparator}vendor'
        '${Platform.pathSeparator}ripgrep${Platform.pathSeparator}'
        '$platform${Platform.pathSeparator}$exe';
  }
}

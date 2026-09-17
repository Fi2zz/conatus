/// Cua Driver 原生 Provider——骨架实现。
library;

import '../desktop.dart';
import '../provider.dart';

/// 随 npm 依赖安装的平台原生运行时桌面 Provider。
///
/// **骨架实现**：Cua Driver 原生运行时随 npm 依赖安装，本包不携带该运行时，
/// 因此 [initialize] 抛 [UnsupportedError]。平台限制由 Cua Driver README
/// 说明。接入方式：
///
/// ```dart
/// provideComputerUse(app, provider: CuaDriverNativeProvider());
/// ```
class CuaDriverNativeProvider implements ComputerUseProvider {
  /// 构造。
  CuaDriverNativeProvider({this.timeout = const Duration(seconds: 30)});

  /// 单次请求超时。
  final Duration timeout;

  @override
  String get name => 'cua-driver-native';

  @override
  Future<DesktopSession> initialize() {
    throw UnsupportedError(
      'Cua Driver 原生运行时需随 npm 依赖安装，'
      'conatus_computer_use 暂未接入。',
    );
  }

  @override
  Future<void> dispose() async {}
}

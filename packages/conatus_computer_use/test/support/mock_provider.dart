/// 测试共用的 Mock 桌面 Provider 与 DesktopSession。
library;

import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 可脚本化行为的桌面 Provider。
class MockComputerUseProvider implements ComputerUseProvider {
  MockComputerUseProvider({String? name}) : name = name ?? 'mock';

  @override
  final String name;

  /// 是否被 initialize 过。
  bool initialized = false;

  /// 是否被 dispose。
  bool disposed = false;

  /// 非空时 [initialize] 抛它。
  Object? initializeError;

  /// 返回的桌面会话；缺省自动构造。
  DesktopSession? session;

  @override
  Future<DesktopSession> initialize() async {
    final Object? error = initializeError;
    if (error != null) throw error;
    initialized = true;
    return session ??=
        MockDesktopSession(toolNames: const <String>['screen_capture', 'mouse_click']);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// 假桌面会话（不绑定任何 Session）。
class MockDesktopSession implements DesktopSession {
  MockDesktopSession({this.toolNames = const <String>[]});

  @override
  final List<String> toolNames;

  /// 收到的调用（toolName, args）。
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  /// 返回的结果；缺省成功。
  ToolResult? result;

  /// 非空时 [call] 抛它。
  Object? callError;

  /// [capture] 返回的截图；缺省一张 10x10 PNG。
  Screenshot? screenshot;

  @override
  Future<ToolResult> call(String toolName, Map<String, Object?> args) async {
    calls.add((toolName, args));
    final Object? error = callError;
    if (error != null) throw error;
    return result ?? ToolResult.success('ok');
  }

  @override
  Future<Screenshot> capture({ScreenRegion? region}) async {
    return screenshot ??
        Screenshot(
          bytes: const <int>[1, 2, 3, 4],
          width: 10,
          height: 10,
          capturedAt: DateTime.now(),
        );
  }

  @override
  Future<void> close() async {}
}

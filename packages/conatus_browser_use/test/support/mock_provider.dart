/// 测试共用的 Mock 浏览器 Provider 与 SessionBrowser。
library;

import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 可脚本化行为的浏览器 Provider。
class MockBrowserUseProvider implements BrowserUseProvider {
  MockBrowserUseProvider({String? name}) : name = name ?? 'mock';

  @override
  final String name;

  /// 已初始化过的 Session（按顺序）。
  final List<Session> initialized = <Session>[];

  /// 已释放过的 Session（按顺序）。
  final List<Session> released = <Session>[];

  /// 是否被 dispose。
  bool disposed = false;

  /// 非空时 [initializeFor] 抛它。
  Object? initializeError;

  /// 自定义初始化回调；缺省返回带默认工具集的浏览器。
  Future<SessionBrowser> Function(Session session)? onInitialize;

  @override
  Future<SessionBrowser> initializeFor(Session session) async {
    final Object? error = initializeError;
    if (error != null) throw error;
    initialized.add(session);
    final Future<SessionBrowser> Function(Session session)? custom = onInitialize;
    if (custom != null) return custom(session);
    return MockSessionBrowser(
      sessionId: session.id,
      toolNames: const <String>['browser_navigate', 'browser_click'],
    );
  }

  @override
  Future<void> release(Session session) async {
    released.add(session);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// 绑定 Session 的假浏览器。
class MockSessionBrowser implements SessionBrowser {
  MockSessionBrowser({
    required this.sessionId,
    this.toolNames = const <String>[],
  });

  @override
  final String sessionId;

  @override
  final List<String> toolNames;

  bool _active = true;

  @override
  bool get isActive => _active;

  /// 收到的调用（toolName, args）。
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  /// 返回的结果；缺省成功。
  ToolResult? result;

  /// 非空时 [call] 抛它。
  Object? callError;

  @override
  Future<ToolResult> call(String toolName, Map<String, Object?> args) async {
    calls.add((toolName, args));
    final Object? error = callError;
    if (error != null) throw error;
    return result ?? ToolResult.success('ok');
  }

  @override
  Future<void> close() async {
    _active = false;
  }
}

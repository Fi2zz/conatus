/// 假浏览器 Provider：记录动作，按工具名返回预设结果。
library;

import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 一次浏览器动作记录。
class BrowserCall {
  BrowserCall(this.tool, this.args);

  final String tool;
  final Map<String, Object?> args;
}

/// 实现 [BrowserUseProvider] 与 [SessionBrowser] 的假浏览器。
///
/// 通过 [stub] 预设某工具的返回文本；未预设时默认成功（`ok`）。
/// 所有工具调用记录在 [actions]，供断言。
class FakeBrowserUseProvider implements BrowserUseProvider {
  FakeBrowserUseProvider({
    List<String>? toolNames,
  }) : _toolNames = toolNames ??
            <String>[
              'browser_navigate',
              'browser_snapshot',
              'browser_submit',
              'browser_click',
            ];

  final List<String> _toolNames;
  final Map<String, String> _results = <String, String>{};

  /// 记录的所有浏览器动作，按调用顺序。
  final List<BrowserCall> actions = <BrowserCall>[];

  /// 视为失败的工具名（返回失败 [ToolResult]）。
  final Set<String> failingTools = <String>{};

  /// 预设某工具的返回文本。
  void stub(String tool, String content) => _results[tool] = content;

  @override
  String get name => 'fake-browser';

  @override
  Future<SessionBrowser> initializeFor(Session session) async =>
      FakeSessionBrowser(this, session.id);

  @override
  Future<void> release(Session session) async {}

  @override
  Future<void> dispose() async {}

  Future<ToolResult> call(String tool, Map<String, Object?> args) async {
    actions.add(BrowserCall(tool, args));
    if (failingTools.contains(tool)) {
      return ToolResult.failure(
        '浏览器工具失败: $tool',
        error: const ToolError('BROWSER_FAILED', 'browser tool failed'),
      );
    }
    return ToolResult.success(_results[tool] ?? 'ok');
  }
}

class FakeSessionBrowser implements SessionBrowser {
  FakeSessionBrowser(this._provider, this.sessionId);

  final FakeBrowserUseProvider _provider;

  @override
  final String sessionId;

  @override
  bool get isActive => true;

  @override
  List<String> get toolNames => _provider._toolNames;

  @override
  Future<ToolResult> call(String toolName, Map<String, Object?> args) =>
      _provider.call(toolName, args);

  @override
  Future<void> close() async {}
}

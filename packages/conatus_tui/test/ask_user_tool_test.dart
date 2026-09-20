/// `ask_user` 工具：自定义选项、内置权限模式选项集、缺选项与取消。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 只提供浮层与权限模式读写的测试宿主。
class _Host implements TuiUserPromptHost {
  _Host();

  @override
  final TuiChoicePrompt choice = TuiChoicePrompt();

  @override
  TuiPermissionMode permissionMode = TuiPermissionMode.askWhenNeeded;

  @override
  void applyPermissionMode(TuiPermissionMode mode) => permissionMode = mode;
}

void main() {
  test('自定义选项：返回选中项并回传文案', () async {
    final _Host host = _Host();
    final AskUserTool tool = AskUserTool(host: () => host);

    final Future<ToolResult> pending = tool.call(const ToolContext(ToolCall(
      name: kAskUserToolName,
      arguments: <String, Object?>{
        'question': '走哪条路？',
        'options': <String>['大路', '小路'],
      },
    )));
    host.choice
      ..move(1)
      ..confirm();

    final ToolResult result = await pending;
    expect(result.isError, isFalse);
    expect(result.content, contains('小路'));
  });

  test('未提供选项时不弹浮层，直接提示', () async {
    final _Host host = _Host();
    final AskUserTool tool = AskUserTool(host: () => host);

    final ToolResult result = await tool.call(const ToolContext(ToolCall(
      name: kAskUserToolName,
      arguments: <String, Object?>{'question': '在吗'},
    )));

    expect(result.isError, isFalse);
    expect(result.content, contains('未提供候选选项'));
    expect(host.choice.open, isFalse);
  });

  test('purpose=permission_mode 渲染内置模式并应用选择', () async {
    final _Host host = _Host();
    final AskUserTool tool = AskUserTool(host: () => host);

    final Future<ToolResult> pending = tool.call(const ToolContext(ToolCall(
      name: kAskUserToolName,
      arguments: <String, Object?>{
        'question': '用什么权限模式？',
        'purpose': kAskUserPurposePermissionMode,
      },
    )));
    final TuiChoiceRequest? request = host.choice.request;
    expect(request, isNotNull);
    expect(request!.choices.length, TuiPermissionMode.values.length);
    expect(
      request.choices.where((TuiChoice c) => c.current).single.id,
      TuiPermissionMode.askWhenNeeded.name,
    );

    host.choice
      ..move(-1)
      ..confirm();

    final ToolResult result = await pending;
    expect(host.permissionMode, TuiPermissionMode.alwaysAsk);
    expect(result.content, contains(TuiPermissionMode.alwaysAsk.label));
  });

  test('取消返回失败结果', () async {
    final _Host host = _Host();
    final AskUserTool tool = AskUserTool(host: () => host);

    final Future<ToolResult> pending = tool.call(const ToolContext(ToolCall(
      name: kAskUserToolName,
      arguments: <String, Object?>{
        'question': '选一个',
        'options': <String>['甲', '乙'],
      },
    )));
    host.choice.cancel();

    final ToolResult result = await pending;
    expect(result.isError, isTrue);
    expect(result.error!.code, 'ASK_USER_CANCELLED');
  });

  test('宿主未就绪时返回失败而非抛出', () async {
    final AskUserTool tool = AskUserTool(host: () => null);

    final ToolResult result = await tool.call(const ToolContext(ToolCall(
      name: kAskUserToolName,
      arguments: <String, Object?>{'question': '在吗'},
    )));

    expect(result.isError, isTrue);
    expect(result.error!.code, 'ASK_USER_UNAVAILABLE');
  });

  test('工具自身低风险且声明独立超时', () {
    final AskUserTool tool = AskUserTool(host: () => null);

    expect(tool.riskLevel, ToolRisk.low);
    expect(tool.timeout, kAskUserTimeout);
  });
}

import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'support/mock_provider.dart';

void main() {
  group('BrowserActionTool', () {
    late MockSessionBrowser browser;
    late BrowserActionTool tool;

    setUp(() {
      browser = MockSessionBrowser(
        sessionId: 's1',
        toolNames: const <String>['browser_click'],
      );
      tool = BrowserActionTool(browser, 'browser_click');
    });

    test('name 与描述来自工具名与 Session', () {
      expect(tool.name, 'browser_click');
      expect(tool.description, contains('s1'));
    });

    test('riskLevel 由风险表声明', () {
      expect(tool.riskLevel, ToolRisk.medium);
      expect(BrowserActionTool(browser, 'browser_evaluate').riskLevel, ToolRisk.high);
      expect(BrowserActionTool(browser, 'browser_snapshot').riskLevel, ToolRisk.low);
    });

    test('call 转发参数并返回浏览器结果', () async {
      final ToolResult result = await tool.call(const ToolContext(
        ToolCall(name: 'browser_click', arguments: <String, Object?>{'x': 1}),
      ));

      expect(result.isError, isFalse);
      expect(result.content, 'ok');
      expect(browser.calls, hasLength(1));
      expect(browser.calls.single.$1, 'browser_click');
      expect(browser.calls.single.$2, <String, Object?>{'x': 1});
    });

    test('浏览器失败结果原样返回', () async {
      browser.result = ToolResult.failure('boom',
          error: const ToolError('E', 'boom'));
      final ToolResult result = await tool.call(const ToolContext(
        ToolCall(name: 'browser_click'),
      ));

      expect(result.isError, isTrue);
      expect(result.error?.code, 'E');
    });

    test('浏览器抛异常时向上传播', () async {
      browser.callError = StateError('engine crashed');
      await expectLater(
        tool.call(const ToolContext(ToolCall(name: 'browser_click'))),
        throwsStateError,
      );
    });
  });
}

import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('browserToolRisk', () {
    test('只读操作是 low', () {
      for (final String name in <String>[
        'browser_navigate',
        'browser_snapshot',
        'browser_wait_for',
        'browser_take_screenshot',
      ]) {
        expect(browserToolRisk(name), ToolRisk.low, reason: name);
      }
    });

    test('交互操作是 medium', () {
      for (final String name in <String>[
        'browser_click',
        'browser_type',
        'browser_select_option',
        'browser_press_key',
      ]) {
        expect(browserToolRisk(name), ToolRisk.medium, reason: name);
      }
    });

    test('敏感操作是 high', () {
      for (final String name in <String>[
        'browser_evaluate',
        'browser_file_upload',
        'browser_download',
      ]) {
        expect(browserToolRisk(name), ToolRisk.high, reason: name);
      }
    });

    test('未列出的工具一律 medium', () {
      expect(browserToolRisk('browser_unknown_tool'), ToolRisk.medium);
    });
  });
}

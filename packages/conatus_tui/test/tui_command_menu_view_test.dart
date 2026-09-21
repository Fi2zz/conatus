/// `/` 命令菜单浮层的渲染：限行滚动 + 计数。
library;

import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  test('长列表只渲染可见窗口并带计数', () async {
    final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/');
    expect(menu.matches.length, greaterThan(kTuiCommandMenuVisible));

    final NoctermTester tester =
        await NoctermTester.create(size: const Size(100, 40));
    try {
      await tester.pumpComponent(TuiCommandMenuView(
        matches: menu.matches,
        selected: menu.index,
        windowStart: menu.windowStart,
      ));
      await tester.pump();

      expect(tester.terminalState, containsText('(1/${menu.matches.length})'));
      expect(tester.terminalState, containsText(menu.matches.first.usage));
      // 窗口外的命令不渲染。
      expect(
        tester.terminalState,
        isNot(containsText(menu.matches.last.usage)),
      );
    } finally {
      tester.dispose();
    }
  });

  test('滚动到末尾时窗口贴住底部', () async {
    final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/');
    menu.move(menu.matches.length);
    expect(menu.windowStart, menu.matches.length - kTuiCommandMenuVisible);

    final NoctermTester tester =
        await NoctermTester.create(size: const Size(100, 40));
    try {
      await tester.pumpComponent(TuiCommandMenuView(
        matches: menu.matches,
        selected: menu.index,
        windowStart: menu.windowStart,
      ));
      await tester.pump();

      expect(
        tester.terminalState,
        containsText('(${menu.matches.length}/${menu.matches.length})'),
      );
      expect(tester.terminalState, containsText(menu.matches.last.usage));
      expect(
        tester.terminalState,
        isNot(containsText(menu.matches.first.usage)),
      );
    } finally {
      tester.dispose();
    }
  });
}

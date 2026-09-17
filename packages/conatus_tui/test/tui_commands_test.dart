/// `/` 命令菜单与帮助文案。
library;

import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  test('输入 / 打开全部命令，前缀过滤收窄', () {
    final TuiCommandMenu menu = TuiCommandMenu();

    menu.syncInput('/');
    expect(menu.open, isTrue);
    expect(menu.matches.length, tuiCommands.length);

    menu.syncInput('/se');
    expect(menu.open, isTrue);
    expect(
      menu.matches.map((TuiCommand c) => c.name),
      <String>['session', 'sessions'],
    );
  });

  test('命令词带参或非斜杠开头时关闭', () {
    final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/se');
    expect(menu.open, isTrue);

    menu.syncInput('/session ');
    expect(menu.open, isFalse);

    menu.syncInput('/se');
    menu.syncInput('hello');
    expect(menu.open, isFalse);
  });

  test('无匹配不显示面板', () {
    final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/nope');
    expect(menu.open, isFalse);
    expect(menu.matches, isEmpty);
  });

  test('移动光标钳制边界，选中项随之变化', () {
    final TuiCommandMenu menu = TuiCommandMenu()..syncInput('/');
    expect(menu.selected?.name, 'help');

    menu.move(-1);
    expect(menu.selected?.name, 'help');

    menu.move(1);
    expect(menu.selected?.name, 'new');

    for (int i = 0; i < 99; i++) {
      menu.move(1);
    }
    expect(menu.selected?.name, tuiCommands.last.name);
  });

  test('过滤变化后光标回到首项', () {
    final TuiCommandMenu menu = TuiCommandMenu()
      ..syncInput('/')
      ..move(3);
    expect(menu.index, 3);

    menu.syncInput('/s');
    expect(menu.index, 0);
    expect(menu.selected?.name, 'session');
  });

  test('帮助文案由命令表生成', () {
    expect(tuiHelpText, contains('/session <id>'));
    expect(tuiHelpText, contains('/tools'));
    expect(tuiHelpText, contains('/exit'));
    expect(tuiHelpText, contains('/team <子命令>'));
    expect(tuiHelpText, contains('/task <子命令>'));
    expect(tuiHelpText, contains('其他输入直接进入 Agent 对话链路。'));
  });
}

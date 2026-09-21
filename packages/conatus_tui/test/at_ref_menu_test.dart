/// @ 文件补全菜单状态。
library;

import 'dart:io';

import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late AtRefMenu menu;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('at-ref-menu-test-');
    Directory('${dir.path}/lib').createSync();
    Directory('${dir.path}/demo').createSync();
    Directory('${dir.path}/.hidden').createSync();
    File('${dir.path}/LICENSE').writeAsStringSync('license');
    File('${dir.path}/lib/main.dart').writeAsStringSync('main');
    File('${dir.path}/lib/menu.dart').writeAsStringSync('menu');
    File('${dir.path}/.env').writeAsStringSync('x');
    menu = AtRefMenu(cwd: () => dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('输入 @ 打开并列举顶层（目录在前，跳过隐藏项）', () {
    menu.syncInput('@', cursor: 1);
    expect(menu.open, isTrue);
    expect(
      menu.matches.map((AtRefCandidate c) => c.path).toList(),
      <String>['demo/', 'lib/', 'LICENSE'],
    );
  });

  test('前缀过滤与路径补全', () {
    menu.syncInput('@li', cursor: 3);
    expect(menu.matches.map((AtRefCandidate c) => c.path).toList(),
        <String>['lib/']);
    expect(menu.selected!.name, 'lib');
  });

  test('目录前缀列举子项', () {
    menu.syncInput('@lib/', cursor: 5);
    expect(menu.matches.map((AtRefCandidate c) => c.path).toList(),
        <String>['lib/main.dart', 'lib/menu.dart']);
  });

  test('目录前缀 + 子项过滤', () {
    menu.syncInput('@lib/me', cursor: 7);
    expect(menu.matches.map((AtRefCandidate c) => c.path).toList(),
        <String>['lib/menu.dart']);
  });

  test('补全目录：停在路径末尾，菜单继续打开', () {
    menu.syncInput('@li', cursor: 3);
    final (String text, int cursor) = menu.complete('@li', cursor: 3)!;
    expect(text, '@lib/');
    expect(cursor, 5);
    menu.syncInput(text, cursor: cursor);
    expect(menu.matches.map((AtRefCandidate c) => c.path).toList(),
        <String>['lib/main.dart', 'lib/menu.dart']);
  });

  test('补全文件：追加空格并关闭', () {
    menu.syncInput('@lib/me', cursor: 7);
    final (String text, int cursor) = menu.complete('@lib/me', cursor: 7)!;
    expect(text, '@lib/menu.dart ');
    expect(cursor, 15);
    menu.syncInput(text, cursor: cursor);
    expect(menu.open, isFalse);
  });

  test('句中 @ 前是空白也触发，词中 @ 不触发', () {
    menu.syncInput('看看 @li', cursor: 6);
    expect(menu.open, isTrue);
    menu.syncInput('a@b', cursor: 3);
    expect(menu.open, isFalse);
  });

  test('@ 之后出现空白关闭', () {
    menu.syncInput('@li 再看看', cursor: 7);
    expect(menu.open, isFalse);
  });

  test('光标不在 @ token 内时关闭', () {
    menu.syncInput('@li 看看', cursor: 6);
    expect(menu.open, isFalse);
  });

  test('光标越界按文本末尾处理', () {
    menu.syncInput('@li', cursor: 99);
    expect(menu.matches.map((AtRefCandidate c) => c.path).toList(),
        <String>['lib/']);
  });

  test('移动与越界钳制', () {
    menu.syncInput('@', cursor: 1);
    menu.move(-1);
    expect(menu.index, 0);
    menu.move(99);
    expect(menu.index, menu.matches.length - 1);
  });

  test('候选数量受 maxMatches 限制', () {
    final AtRefMenu limited = AtRefMenu(cwd: () => dir.path, maxMatches: 2);
    limited.syncInput('@', cursor: 1);
    expect(limited.matches, hasLength(2));
  });

  test('不存在的目录前缀无候选且不打开', () {
    menu.syncInput('@nope/', cursor: 6);
    expect(menu.open, isFalse);
    expect(menu.matches, isEmpty);
  });
}

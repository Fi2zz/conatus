/// 选项浮层状态机：选择 / 取消 / 超时 / 被取代。
library;

import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

TuiChoiceRequest _request({bool withCurrent = false}) => TuiChoiceRequest(
      title: '选一个',
      choices: <TuiChoice>[
        const TuiChoice(id: 'a', label: '甲', description: '第一个'),
        TuiChoice(id: 'b', label: '乙', current: withCurrent),
        const TuiChoice(id: 'c', label: '丙'),
      ],
    );

void main() {
  test('ask 打开浮层并返回选中项 id', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    final Future<String?> pending = prompt.ask(_request());

    expect(prompt.open, isTrue);
    expect(prompt.index, 0);

    prompt.move(1);
    expect(prompt.index, 1);
    prompt.confirm();

    expect(await pending, 'b');
    expect(prompt.open, isFalse);
  });

  test('current 项作为初始光标，取消返回 null', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    final Future<String?> pending = prompt.ask(_request(withCurrent: true));

    expect(prompt.index, 1);

    prompt.cancel();
    expect(await pending, isNull);
    expect(prompt.open, isFalse);
  });

  test('光标钳制边界', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    final Future<String?> pending = prompt.ask(_request());

    prompt.move(-1);
    expect(prompt.index, 0);
    for (int i = 0; i < 9; i++) {
      prompt.move(1);
    }
    expect(prompt.index, 2);

    prompt.cancel();
    await pending;
  });

  test('超时收口为 null 并关闭浮层', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    final String? picked = await prompt.ask(
      _request(),
      timeout: const Duration(milliseconds: 20),
    );

    expect(picked, isNull);
    expect(prompt.open, isFalse);
  });

  test('新提问取代未收口的旧提问', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    final Future<String?> first = prompt.ask(_request());
    final Future<String?> second = prompt.ask(_request());

    expect(await first, isNull);
    prompt.confirm();
    expect(await second, 'a');
  });

  test('onChanged 在开关与移动时回调', () async {
    final TuiChoicePrompt prompt = TuiChoicePrompt();
    int calls = 0;
    prompt.onChanged = () => calls++;

    final Future<String?> pending = prompt.ask(_request());
    prompt.move(1);
    prompt.confirm();
    await pending;

    expect(calls, 3);
  });
}

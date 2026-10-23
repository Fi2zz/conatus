/// 写入策略的表驱动契约：什么该写、什么不该写、写进去长什么样。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_memory/conatus_memory.dart';
import 'package:test/test.dart';

MemoryEntry _entry(String text) => MemoryEntry(
      id: 'm1',
      text: text,
      tags: const <String>{'conversation'},
      createdAt: DateTime(2026),
    );

MemoryWriteDecision _review(
  String userInput,
  String reply, {
  List<MemoryEntry> existing = const <MemoryEntry>[],
}) =>
    const PolicyMemoryWritePolicy().review(
      userInput: userInput,
      reply: reply,
      existing: existing,
    );

void main() {
  test('空回复不写', () {
    expect(_review('在吗', '   ').store, isFalse);
    expect(_review('在吗', '').verdict, MemoryWriteVerdict.emptyReply);
  });

  test('短回复不写，达到阈值才写', () {
    expect(_review('解释一下', 'a' * 11).verdict, MemoryWriteVerdict.shortReply);
    expect(_review('解释一下', 'a' * 12).store, isTrue);
  });

  test('寒暄不写', () {
    for (final String input in <String>['你好', 'hello', 'Hi!', '谢谢', '在吗？']) {
      expect(
        _review(input, '你好，有什么可以帮你？').verdict,
        MemoryWriteVerdict.greeting,
        reason: input,
      );
    }
  });

  test('正常内容写为「用户 / 助手」两行', () {
    final MemoryWriteDecision decision =
        _review('帮我记住项目用 Dart', '已记录：项目语言是 Dart。');
    expect(decision.store, isTrue);
    expect(decision.text, '用户：帮我记住项目用 Dart\n助手：已记录：项目语言是 Dart。');
  });

  test('与已有记忆近重复时不写', () {
    final MemoryWriteDecision decision = _review(
      '帮我记住项目用 Dart',
      '已记录：项目语言是 Dart。',
      existing: <MemoryEntry>[
        _entry('用户：帮我记住项目用 Dart\n助手：已记录：项目语言是 Dart。'),
      ],
    );
    expect(decision.verdict, MemoryWriteVerdict.duplicate);
  });

  test('大小写与空白变体仍判为重复', () {
    final MemoryWriteDecision decision = _review(
      '帮我记住项目用 Dart',
      '已记录：项目语言是 Dart。',
      existing: <MemoryEntry>[
        _entry('用户：帮我记住项目用   DART\n助手：已记录：项目语言是 dart。'),
      ],
    );
    expect(decision.verdict, MemoryWriteVerdict.duplicate);
  });

  test('超长内容截断到上限', () {
    final MemoryWriteDecision decision = _review('写一段说明', 'x' * 900);
    expect(decision.store, isTrue);
    expect(decision.text!.length, 600);
  });
}

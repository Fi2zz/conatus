import 'dart:convert';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

Stream<List<int>> _bytes(List<String> chunks) =>
    Stream<List<int>>.fromIterable(chunks.map(utf8.encode));

void main() {
  test('data: 多行用换行拼接，空行派发', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['data: 第一行\ndata: 第二行\n\n']),
    ).toList();

    expect(events.length, 1);
    expect(events.single.data, '第一行\n第二行');
    expect(events.single.event, isNull);
    expect(events.single.id, isNull);
  });

  test('event: / id: 字段随事件带出', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['event: endpoint\nid: 42\ndata: /messages\n\n']),
    ).toList();

    expect(events.single.event, 'endpoint');
    expect(events.single.id, '42');
    expect(events.single.data, '/messages');
  });

  test('注释行忽略；空块不派发', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>[': keep-alive\n\n', 'data: real\n\n']),
    ).toList();

    expect(events.length, 1);
    expect(events.single.data, 'real');
  });

  test('冒号后单个空格被剥掉，其余保留', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['data:  两个空格\n\n']),
    ).toList();

    expect(events.single.data, ' 两个空格');
  });

  test('无冒号的 data 字段视为空值，空 data 不派发', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['data\n\n']),
    ).toList();

    expect(events, isEmpty);
  });

  test('跨 chunk 切分：半行、半字段都能重组', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>[
        'even',
        't: mess',
        'age\ndata: {"a"',
        ':1,"b":2}',
        '\ndata: tail\n',
        '\n',
      ]),
    ).toList();

    expect(events.length, 1);
    expect(events.single.event, 'message');
    expect(events.single.data, '{"a":1,"b":2}\ntail');
  });

  test('EOF 时未派发的 data 也派发', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['data: 没有空行结尾']),
    ).toList();

    expect(events.single.data, '没有空行结尾');
  });

  test('多字节字符被 chunk 切断也不乱码', () async {
    final List<int> raw = utf8.encode('data: 你好\n\n');
    final List<List<int>> cut = <List<int>>[raw.sublist(0, 8), raw.sublist(8)];
    final List<SseEvent> events =
        await parseSseEvents(Stream<List<int>>.fromIterable(cut)).toList();

    expect(events.single.data, '你好');
  });

  test('多个事件按顺序派发', () async {
    final List<SseEvent> events = await parseSseEvents(
      _bytes(<String>['data: one\n\ndata: two\n\ndata: three\n\n']),
    ).toList();

    expect(
      events.map((SseEvent event) => event.data),
      <String>['one', 'two', 'three'],
    );
  });
}

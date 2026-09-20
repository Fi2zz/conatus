/// 入口命令行选项解析。
library;

import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

void main() {
  test('缺省：会话 tui，无首轮，不请求帮助', () {
    final TuiOptions options = TuiOptions.parse(const <String>[]);

    expect(options.session, kTuiDefaultSession);
    expect(options.first, isNull);
    expect(options.helpRequested, isFalse);
  });

  test('解析 --session 与 --first', () {
    final TuiOptions options = TuiOptions.parse(
      const <String>['--session', 'demo', '--first', '现在几点？'],
    );

    expect(options.session, 'demo');
    expect(options.first, '现在几点？');
  });

  test('--help 与 -h 都置 helpRequested，且不打断其余解析', () {
    expect(TuiOptions.parse(const <String>['--help']).helpRequested, isTrue);
    expect(TuiOptions.parse(const <String>['-h']).helpRequested, isTrue);

    final TuiOptions options =
        TuiOptions.parse(const <String>['--session', 'a', '--help']);

    expect(options.helpRequested, isTrue);
    expect(options.session, 'a');
  });

  test('尾值缺失时保持缺省', () {
    final TuiOptions options = TuiOptions.parse(const <String>['--session']);

    expect(options.session, kTuiDefaultSession);
    expect(options.first, isNull);
  });

  test('未知参数忽略', () {
    final TuiOptions options =
        TuiOptions.parse(const <String>['--unknown', 'x']);

    expect(options.session, kTuiDefaultSession);
    expect(options.first, isNull);
  });

  test('取值只按越界判断：后一个开关会被当成前一个的值', () {
    final TuiOptions options =
        TuiOptions.parse(const <String>['--session', '--first', 'hello']);

    expect(options.session, '--first');
    // `--first` 已被 --session 消费，'hello' 成了孤立参数。
    expect(options.first, isNull);
  });

  test('用法文案列出两个开关', () {
    expect(TuiOptions.usage, contains('--session <id>'));
    expect(TuiOptions.usage, contains('--first <文本>'));
  });
}

import 'dart:convert';

import 'package:conatus_msp/src/msp_signal.dart';
import 'package:test/test.dart';

void main() {
  test('Signal 按八字段编码并保留原始 UTF-8 中文', () {
    final MspSignal signal = MspSignal(
      type: 'signal',
      source: 'node_a',
      options: MspSignalOptions(path: 'notify.file.changed')
        ..payload = <String, Object?>{'text': '文件已变化'}
        ..timestamp = 123.5,
    );

    final String encoded = jsonEncode(signal.toJson());
    expect(encoded, contains('文件已变化'));
    expect(encoded, isNot(contains(r'\u')));
    expect(
        signal.toJson().keys,
        containsAll(<String>[
          'type',
          'source',
          'pattern',
          'target',
          'path',
          'reqid',
          'payload',
          'timestamp',
        ]));
  });

  test('Signal 忽略未知字段并为缺省字段填默认值', () {
    final MspSignal signal = MspSignal.fromJson(<String, Object?>{
      'type': 'ping',
      'source': 'node_a',
      'future_field': 'ignored',
    });

    expect(signal.payload, isEmpty);
    expect(signal.pattern, isNull);
    expect(signal.target, isNull);
    expect(signal.reqid, isNull);
    expect(signal.timestamp, greaterThan(0));
  });

  test('Signal 缺少必填字段时拒绝解码', () {
    expect(
      () => MspSignal.fromJson(<String, Object?>{'source': 'node_a'}),
      throwsFormatException,
    );
  });

  test('Signal 拒绝非对象 payload', () {
    expect(
      () => MspSignal.fromJson(<String, Object?>{
        'type': 'signal',
        'source': 'node_a',
        'payload': <Object?>[],
      }),
      throwsFormatException,
    );
  });
}

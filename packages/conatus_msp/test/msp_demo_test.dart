import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Demo 展示发现调用事件和清理并正常退出', () async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'example/msp_demo.dart'],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final String output = '${result.stdout}';
    expect(output, contains('[1/4] 自动发现'));
    expect(output, contains('[2/4] 工具调用'));
    expect(output, contains('[3/4] 主动事件'));
    expect(output, contains('[4/4] 清理完成'));
    expect(result.stderr, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

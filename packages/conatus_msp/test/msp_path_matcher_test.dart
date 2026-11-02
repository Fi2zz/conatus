import 'package:conatus_msp/src/msp_path_matcher.dart';
import 'package:test/test.dart';

void main() {
  test('路径匹配遵循官方通配符边界', () {
    final List<({String pattern, String path, bool expected})> cases =
        <({String pattern, String path, bool expected})>[
      (pattern: 'ai.state', path: 'ai.state', expected: true),
      (pattern: 'ai.state', path: 'ai.state.x', expected: false),
      (pattern: 'ai.*', path: 'ai.state', expected: true),
      (pattern: 'ai.*', path: 'ai', expected: false),
      (pattern: 'ai.*', path: 'ai.state.x', expected: false),
      (pattern: 'system.**', path: 'system', expected: true),
      (pattern: 'system.**', path: 'system.cpu.load', expected: true),
      (pattern: 'system.**', path: 'systematic', expected: false),
      (pattern: '*', path: 'ai.state', expected: false),
      (pattern: '**', path: 'ai.state', expected: false),
      (pattern: 'ai.*.state', path: 'ai.cpu.state', expected: false),
      (pattern: '*.state', path: '*.state', expected: true),
    ];

    for (final ({String pattern, String path, bool expected}) item in cases) {
      expect(
        matchesMspPath(item.pattern, item.path),
        item.expected,
        reason: '${item.pattern} vs ${item.path}',
      );
    }
  });
}

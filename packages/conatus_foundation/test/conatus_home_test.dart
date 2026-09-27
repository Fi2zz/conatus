import 'dart:io';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('resolveConatusHome', () {
    test('CONATUS_HOME 非空时优先于 HOME', () {
      final String home = resolveConatusHome(env: <String, String>{
        kConatusHomeEnv: '/data/conatus',
        'HOME': '/home/u',
      });
      expect(home, '/data/conatus');
    });

    test('CONATUS_HOME 空白视为未设置，回退用户目录下的 .conatus', () {
      final String home = resolveConatusHome(env: <String, String>{
        kConatusHomeEnv: '   ',
        'HOME': '/home/u',
      });
      expect(home, '/home/u${Platform.pathSeparator}.conatus');
    });
  });

  group('resolveHomeDir', () {
    test('HOME 优先于 USERPROFILE', () {
      final String home = resolveHomeDir(env: <String, String>{
        'HOME': '/home/u',
        'USERPROFILE': r'C:\Users\u',
      });
      expect(home, '/home/u');
    });

    test('无 HOME 时用 USERPROFILE', () {
      final String home =
          resolveHomeDir(env: <String, String>{'USERPROFILE': r'C:\Users\u'});
      expect(home, r'C:\Users\u');
    });

    test('全部缺失时抛 StateError，绝不回退 cwd', () {
      expect(() => resolveHomeDir(env: <String, String>{}), throwsStateError);
      expect(
          () => resolveConatusHome(env: <String, String>{}), throwsStateError);
    });
  });
}

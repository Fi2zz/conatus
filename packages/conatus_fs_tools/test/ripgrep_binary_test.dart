import 'dart:io';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

void main() {
  group('RipgrepBinary.discover', () {
    test('系统 rg 可用 → system 来源', () {
      final RipgrepBinary? binary =
          RipgrepBinary.discover(probeRg: () => true);

      expect(binary, isNotNull);
      expect(binary!.path, 'rg');
      expect(binary.source, RipgrepSource.system);
    });

    test('系统不可用且打包二进制存在 → bundled 来源', () {
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-rgbin-');
      final String platform = Platform.operatingSystem;
      final String exe = Platform.isWindows ? 'rg.exe' : 'rg';
      final File bundled = File(
          '${dir.path}${Platform.pathSeparator}vendor${Platform.pathSeparator}'
          'ripgrep${Platform.pathSeparator}$platform${Platform.pathSeparator}$exe')
        ..createSync(recursive: true);

      final RipgrepBinary? binary = RipgrepBinary.discover(
        packageRoot: dir.path,
        probeRg: () => false,
      );

      expect(binary, isNotNull);
      expect(binary!.path, bundled.path);
      expect(binary.source, RipgrepSource.bundled);
      dir.deleteSync(recursive: true);
    });

    test('系统与打包都不可用 → null', () {
      final RipgrepBinary? binary =
          RipgrepBinary.discover(probeRg: () => false);

      expect(binary, isNull);
    });
  });
}

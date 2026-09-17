import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserConfig', () {
    test('缺省配置：launch 模式、无头、无 profile/视口/UA', () {
      const BrowserConfig config = BrowserConfig();
      expect(config.mode, BrowserLaunchMode.launch);
      expect(config.headless, isTrue);
      expect(config.profile, isNull);
      expect(config.viewport, isNull);
      expect(config.userAgent, isNull);
    });

    test('copyWith 覆盖部分字段，未传字段保留', () {
      const BrowserConfig config = BrowserConfig();
      final BrowserConfig updated = config.copyWith(
        mode: BrowserLaunchMode.attach,
        headless: false,
      );
      expect(updated.mode, BrowserLaunchMode.attach);
      expect(updated.headless, isFalse);
      expect(updated.profile, isNull);
    });
  });

  group('BrowserLaunchMode', () {
    test('枚举值：launch 与 attach', () {
      expect(BrowserLaunchMode.values, hasLength(2));
      expect(BrowserLaunchMode.launch.name, 'launch');
      expect(BrowserLaunchMode.attach.name, 'attach');
    });
  });
}

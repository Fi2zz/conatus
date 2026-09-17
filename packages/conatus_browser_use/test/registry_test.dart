import 'package:conatus_browser_use/conatus_browser_use.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserUseRegistry', () {
    test('注册后 currentProvider 可见', () async {
      final BrowserUseRegistryImpl registry = BrowserUseRegistryImpl();
      expect(registry.currentProvider, isNull);

      await registry.register('playwright');
      expect(registry.currentProvider, 'playwright');
    });

    test('第二个注册失败，即使同名', () async {
      final BrowserUseRegistryImpl registry = BrowserUseRegistryImpl();
      await registry.register('playwright');

      await expectLater(
        registry.register('playwright'),
        throwsStateError,
        reason: '同名重复注册必须失败',
      );
      await expectLater(
        registry.register('chrome-devtools'),
        throwsStateError,
        reason: '异名第二个注册必须失败',
      );
    });

    test('释放后可重新注册', () async {
      final BrowserUseRegistryImpl registry = BrowserUseRegistryImpl();
      final void Function() release = await registry.register('playwright');
      expect(registry.currentProvider, 'playwright');

      release();
      expect(registry.currentProvider, isNull);

      await registry.register('chrome-devtools');
      expect(registry.currentProvider, 'chrome-devtools');
    });

    test('释放 disposer 幂等', () async {
      final BrowserUseRegistryImpl registry = BrowserUseRegistryImpl();
      final void Function() release = await registry.register('playwright');
      release();
      release();
      expect(registry.currentProvider, isNull);
      await registry.register('stagehand');
    });

    test('claim 与 register 语义一致（装配路径）', () async {
      final BrowserUseRegistryImpl registry = BrowserUseRegistryImpl();
      final void Function() release = registry.claim('playwright');
      expect(registry.currentProvider, 'playwright');
      expect(() => registry.claim('chrome-devtools'), throwsStateError);
      release();
      expect(registry.currentProvider, isNull);
    });
  });
}

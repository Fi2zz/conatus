import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:test/test.dart';

void main() {
  group('ComputerUseRegistry', () {
    test('注册后 currentProvider 可见', () async {
      final ComputerUseRegistryImpl registry = ComputerUseRegistryImpl();
      expect(registry.currentProvider, isNull);

      await registry.register('cua-driver-mcp');
      expect(registry.currentProvider, 'cua-driver-mcp');
    });

    test('第二个注册失败，即使同名', () async {
      final ComputerUseRegistryImpl registry = ComputerUseRegistryImpl();
      await registry.register('cua-driver-mcp');

      await expectLater(
        registry.register('cua-driver-mcp'),
        throwsStateError,
        reason: '同名重复注册必须失败',
      );
      await expectLater(
        registry.register('cua-driver-native'),
        throwsStateError,
        reason: '异名第二个注册必须失败',
      );
    });

    test('释放后可重新注册', () async {
      final ComputerUseRegistryImpl registry = ComputerUseRegistryImpl();
      final void Function() release = await registry.register('cua-driver-mcp');
      release();
      expect(registry.currentProvider, isNull);

      await registry.register('cua-driver-native');
      expect(registry.currentProvider, 'cua-driver-native');
    });

    test('claim 与 register 语义一致（装配路径）', () async {
      final ComputerUseRegistryImpl registry = ComputerUseRegistryImpl();
      final void Function() release = registry.claim('cua-driver-mcp');
      expect(() => registry.claim('cua-driver-native'), throwsStateError);
      release();
      expect(registry.currentProvider, isNull);
    });
  });
}

/// 真实 provider 的可逆性配对检查：验证各 `provide*` 真的登记了逆。
///
/// 合成效果（`reversibility_world.dart`）只能证明「机制正确」；本文件用**真实**
/// provider 装配一个插件再卸载，确认真实代码路径上的逆都被登记。
///
/// 一个已知的对偶事实：`ToolRegistry.register` / `fn` 只返回 `Disposer`，
/// **不会**自动登记进任何作用域——忘了 `ctx.effect(...)` / `ctx.track(...)`
/// 的工具会在上下文释放后仍留在注册表里。这是调用方的义务，本文件的「残影」
/// 断言钉住的正是「换了新的注册表才不会带上旧工具」。
library;

import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('真实 provider 的逆是否真的登记', () {
    test('装配 tools + database + sessionLog + sessions，卸载后全部还原', () {
      final Context root = Context.root();
      addTearDown(root.dispose);
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-verify-');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      late ToolRegistry registry;
      late InMemorySessionLog log;
      final Context plugin = root.plugin('real', (Context c) {
        registry = provideTools(c);
        provideDatabase(c);
        provideDatabaseJson(c, dir: dir.path);
        log = InMemorySessionLog();
        provideSessionLog(c, log: log);
        provideSessions(c);
      });

      expect(
        plugin.localServiceKeys.toSet(),
        containsAll(
          <String>{'tools', 'database', 'sessionLog', 'sessions'},
        ),
      );
      expect(registry.length, 0);
      expect(log.closed, isFalse);

      plugin.dispose();

      expect(plugin.localServiceKeys, isEmpty);
      expect(plugin.disposed, isTrue);
      expect(log.closed, isTrue);
    });

    test('卸载后重新装配同一插件，得到全新状态而非残影', () {
      final Context root = Context.root();
      addTearDown(root.dispose);

      root.plugin('real', (Context c) {
        provideTools(c).fn(
          'noop',
          handler: (ToolContext _) async => ToolResult.success('ok'),
        );
      }).dispose();

      late ToolRegistry againRegistry;
      final Context again = root.plugin('real', (Context c) {
        againRegistry = provideTools(c);
      });

      expect(again.disposed, isFalse);
      expect(again.localServiceKeys, contains('tools'));
      expect(againRegistry.length, 0);
    });
  });
}

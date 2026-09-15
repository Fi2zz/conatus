import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('Loader — 注册与加载', () {
    test('加载的插件在子上下文生效，卸载时撤销', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (Context child, Object? config) {
          log.add('a:$config');
          child.onDispose(() => log.add('a:off'));
        },
      });

      final id = loader.load(
        const LoaderEntry(id: 'a1', name: 'a', config: 'x'),
      );

      expect(id, 'a1');
      expect(log, <String>['a:x']);
      expect(loader.ids, <String>['a1']);
      expect(loader.contextOf('a1'), isNotNull);

      loader.remove('a1');

      expect(log, <String>['a:x', 'a:off']);
      expect(loader.ids, isEmpty);
      expect(loader.contextOf('a1'), isNull);
    });

    test('未注册的插件抛 LoaderException 且不残留 entry', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final loader = provideLoader(ctx);

      expect(
        () => loader.load(const LoaderEntry(id: 'x', name: 'nope')),
        throwsA(isA<LoaderException>()),
      );
      expect(loader.ids, isEmpty);
    });

    test('重复 id 抛 LoaderException', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (_, __) {},
      });

      loader.load(const LoaderEntry(id: 'a1', name: 'a'));
      expect(
        () => loader.load(const LoaderEntry(id: 'a1', name: 'a')),
        throwsA(isA<LoaderException>()),
      );
    });

    test('disabled 的 entry 登记但不加载', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      var loaded = false;
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (_, __) => loaded = true,
      });

      loader.load(const LoaderEntry(id: 'a1', name: 'a', disabled: true));

      expect(loaded, isFalse);
      expect(loader.entryOf('a1'), isNotNull);
      expect(loader.contextOf('a1'), isNull);
    });

    test('未注册名注册校验', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final loader = provideLoader(ctx);

      expect(loader.has('a'), isFalse);
      loader.register('a', (_, __) {});
      expect(loader.has('a'), isTrue);
      expect(loader.names, <String>['a']);
      expect(loader.unregister('a'), isTrue);
      expect(loader.has('a'), isFalse);
    });
  });

  group('Loader — 配置树', () {
    test('分组递归加载 children', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (_, __) => log.add('a'),
        'b': (_, __) => log.add('b'),
      });

      loader.load(
        const LoaderEntry(
          id: 'g',
          children: <LoaderEntry>[
            LoaderEntry(id: 'g:a', name: 'a'),
            LoaderEntry(id: 'g:b', name: 'b'),
          ],
        ),
      );

      expect(loader.ids, <String>['g', 'g:a', 'g:b']);
      expect(log, <String>['a', 'b']);
    });

    test('remove 分组级联卸载后代', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (Context child, Object? config) {
          log.add('a');
          child.onDispose(() => log.add('a:off'));
        },
        'b': (Context child, Object? config) {
          log.add('b');
          child.onDispose(() => log.add('b:off'));
        },
      });

      loader.load(
        const LoaderEntry(
          id: 'g',
          children: <LoaderEntry>[
            LoaderEntry(id: 'g:a', name: 'a'),
            LoaderEntry(id: 'g:b', name: 'b'),
          ],
        ),
      );
      loader.remove('g');

      expect(loader.ids, isEmpty);
      expect(log, <String>['a', 'b', 'b:off', 'a:off']);
    });

    test('reload 重启插件', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (Context child, Object? config) {
          log.add('a');
          child.onDispose(() => log.add('a:off'));
        },
      });

      loader.load(const LoaderEntry(id: 'a1', name: 'a'));
      loader.reload('a1');

      expect(log, <String>['a', 'a:off', 'a']);
      expect(loader.contextOf('a1'), isNotNull);
    });

    test('apply 全量替换配置树', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (Context child, Object? config) {
          log.add('a');
          child.onDispose(() => log.add('a:off'));
        },
      });

      loader.load(const LoaderEntry(id: 'old', name: 'a'));
      loader.apply(<LoaderEntry>[const LoaderEntry(id: 'new', name: 'a')]);

      expect(log, <String>['a', 'a:off', 'a']);
      expect(loader.ids, <String>['new']);
      expect(loader.contextOf('old'), isNull);
    });

    test('自动生成 id（分组子节点带父前缀）', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (_, __) {},
      });

      final String groupId = loader.load(
        const LoaderEntry(
          children: <LoaderEntry>[LoaderEntry(name: 'a')],
        ),
      );
      loader.load(const LoaderEntry(name: 'a'));

      expect(groupId, startsWith('entry-'));
      expect(
        loader.ids.where((String id) => id.startsWith('$groupId:')),
        hasLength(1),
      );
    });

    test('JSON 往返与 applyJson', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);
      final log = <String>[];
      final loader = provideLoader(ctx, plugins: <String, PluginFactory>{
        'a': (_, Object? config) => log.add('$config'),
      });

      const LoaderEntry entry = LoaderEntry(
        id: 'g',
        children: <LoaderEntry>[
          LoaderEntry(id: 'g:a', name: 'a', config: 'v', disabled: true),
        ],
      );
      final LoaderEntry restored = LoaderEntry.fromJson(entry.toJson());

      expect(restored.id, 'g');
      expect(restored.children.single.name, 'a');
      expect(restored.children.single.disabled, isTrue);
      expect(restored.children.single.config, 'v');

      loader.applyJson(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'live',
          'name': 'a',
          'config': 'x',
        },
      ]);
      expect(log, <String>['x']);
    });
  });

  group('provideLoader', () {
    test('提供 loader 服务，随上下文释放卸载所有 entry', () {
      final ctx = Context.root();
      final log = <String>[];
      provideLoader(
        ctx,
        plugins: <String, PluginFactory>{
          'a': (Context child, Object? config) {
            log.add('on');
            child.onDispose(() => log.add('off'));
          },
        },
        config: <LoaderEntry>[const LoaderEntry(id: 'a1', name: 'a')],
      );

      expect(ctx.has('loader'), isTrue);
      expect(ctx.require<Loader>('loader').ids, <String>['a1']);
      expect(log, <String>['on']);

      ctx.dispose();
      expect(log, <String>['on', 'off']);
    });
  });
}

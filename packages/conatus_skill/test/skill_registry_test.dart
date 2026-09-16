import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

SkillSummary _summary(
  String name, {
  required String provider,
  String source = kSkillSourceProjectConatus,
  bool modelInvocable = true,
}) =>
    SkillSummary(
      name: name,
      description: '$name 的说明',
      source: source,
      provider: provider,
      modelInvocable: modelInvocable,
    );

/// 手写的 provider 替身：技能名可运行时增删，rank 与失败开关可控。
class _FakeProvider implements SkillProvider {
  _FakeProvider(
    this.name, {
    List<String> skills = const <String>[],
    this.rank = 0,
    this.source = kSkillSourceProjectConatus,
    this.modelInvocable = true,
    this.fails = false,
  }) : skills = List<String>.of(skills);

  @override
  final String name;

  /// 当前可见的技能名；测试直接改动它来模拟技能的增删。
  final List<String> skills;

  final int rank;
  final String source;
  final bool modelInvocable;
  final bool fails;

  /// `list()` 被调用的次数，用于验证合并窗口。
  int listCalls = 0;

  /// `load()` 请求过的技能名。
  final List<String> loadedNames = <String>[];

  @override
  Future<List<SkillCandidate>> list() async {
    listCalls++;
    if (fails) throw const SkillProviderException('boom', '列举失败');
    return <SkillCandidate>[
      for (final String skill in skills)
        SkillCandidate(
          rank: rank,
          summary: _summary(
            skill,
            provider: name,
            source: source,
            modelInvocable: modelInvocable,
          ),
        ),
    ];
  }

  @override
  Future<SkillDefinition?> load(SkillSummary summary) async {
    loadedNames.add(summary.name);
    if (!skills.contains(summary.name)) return null;
    return SkillDefinition(
      summary: summary,
      content: '${summary.name} 的正文',
      resourceBase: SkillDirectoryResource('/skills/${summary.name}'),
    );
  }
}

/// 建一个自带 `dispose` 清理的注册表；合并窗口缺省长到测试期间不会触发。
SkillRegistry _registry({
  void Function(String message)? onWarning,
  Duration debounce = const Duration(hours: 1),
}) {
  final SkillRegistry registry = SkillRegistry(
    refreshDebounce: debounce,
    onWarning: onWarning,
  );
  addTearDown(registry.dispose);
  return registry;
}

List<String> _namesOf(List<SkillSummary> summaries) => <String>[
      for (final SkillSummary summary in summaries) summary.name,
    ];

void main() {
  group('提供服务键', () {
    test('提供后 ctx.skillRegistry 取到同一实例并完成首次收集', () async {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['alpha']);

      final SkillRegistry registry =
          await provideSkillRegistry(ctx, providers: <SkillProvider>[provider]);

      expect(ctx.has('skillRegistry'), isTrue);
      expect(ctx.localServiceKeys, contains('skillRegistry'));
      expect(identical(ctx.skillRegistry, registry), isTrue);
      expect(_namesOf(registry.available), <String>['alpha']);
    });

    test('未提供时取注册表抛 StateError', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      expect(() => ctx.skillRegistry, throwsStateError);
    });

    test('释放后服务键与注册表一起回收', () async {
      final Context ctx = Context.root();
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['alpha']);
      final SkillRegistry registry =
          await provideSkillRegistry(ctx, providers: <SkillProvider>[provider]);
      int notifications = 0;
      final Disposer off = registry.onChange(() => notifications++);
      addTearDown(off);

      ctx.dispose();

      expect(ctx.localServiceKeys, isNot(contains('skillRegistry')));
      expect(registry.disposed, isTrue);
      expect(registry.available, isEmpty);
      expect(registry.providers, isEmpty);
      expect(() => registry.registerProvider(provider), throwsStateError);
      expect(
        () => registry
            .register(const SkillRegistration(name: 'beta', description: '说明')),
        throwsStateError,
      );

      await registry.refresh();

      expect(notifications, 0);
      expect(registry.available, isEmpty);
    });
  });

  group('provider 注册与撤销', () {
    test('注册后候选出现在 available，撤销后消失', () async {
      final SkillRegistry registry = _registry();
      expect(registry.available, isEmpty);
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['beta', 'alpha']);

      final Disposer off = registry.registerProvider(provider);

      expect(registry.providers.map((SkillProvider p) => p.name),
          <String>['filesystem']);
      await registry.refresh();
      expect(_namesOf(registry.available), <String>['alpha', 'beta']);

      off();
      off();
      await registry.refresh();

      expect(registry.available, isEmpty);
      expect(registry.providers, isEmpty);
    });

    test('重复注册同名 provider 抛 StateError', () {
      final SkillRegistry registry = _registry();
      registry.registerProvider(_FakeProvider('filesystem'));

      expect(() => registry.registerProvider(_FakeProvider('filesystem')),
          throwsStateError);
      expect(registry.providers, hasLength(1));
    });

    test('provider 名不是 kebab-case 时抛 ArgumentError', () {
      final SkillRegistry registry = _registry();

      for (final String bad in <String>['FileSystem', 'file_system', '']) {
        expect(() => registry.registerProvider(_FakeProvider(bad)),
            throwsArgumentError,
            reason: bad);
      }
      expect(registry.providers, isEmpty);
    });
  });

  group('运行时技能', () {
    test('注册后出现在 available 且可直接 load', () async {
      final SkillRegistry registry = _registry();
      final Disposer off = registry.register(const SkillRegistration(
        name: 'team-notes',
        description: '团队笔记流程',
        whenToUse: '整理会议记录时',
        content: '先读 docs/notes.md。',
      ));

      await registry.refresh();

      final SkillSummary summary = registry.available.single;
      expect(summary.source, kSkillSourceRuntime);
      expect(summary.provider, kSkillRuntimeProvider);
      expect(summary.whenToUse, '整理会议记录时');
      expect(summary.modelInvocable, isTrue);
      expect(_namesOf(registry.modelInvocable), <String>['team-notes']);
      final SkillDefinition? definition = await registry.load('team-notes');
      expect(definition?.content, '先读 docs/notes.md。');
      expect(definition?.summary.name, 'team-notes');

      off();
      await registry.refresh();

      expect(registry.available, isEmpty);
      expect(await registry.load('team-notes'), isNull);
    });

    test('与用户级发现根同名时运行时技能赢', () async {
      final List<String> warnings = <String>[];
      final SkillRegistry registry = _registry(onWarning: warnings.add);
      // rank 400 对应 defaultSkillRoots 里的 user-conatus 根。
      final _FakeProvider provider = _FakeProvider(
        'filesystem',
        skills: <String>['team-notes'],
        rank: 400,
        source: kSkillSourceUserConatus,
      );
      registry.registerProvider(provider);
      registry.register(const SkillRegistration(
        name: 'team-notes',
        description: '宿主内建流程',
        content: '运行时正文',
      ));

      await registry.refresh();

      expect(registry.available.single.provider, kSkillRuntimeProvider);
      expect(registry.available.single.source, kSkillSourceRuntime);
      expect((await registry.load('team-notes'))?.content, '运行时正文');
      expect(provider.loadedNames, isEmpty);
      expect(warnings.single, contains('team-notes'));
    });

    test('名字非法或描述为空时抛 ArgumentError', () async {
      final SkillRegistry registry = _registry();

      expect(
        () => registry.register(
            const SkillRegistration(name: 'Bad Name', description: '说明')),
        throwsArgumentError,
      );
      expect(
        () => registry.register(
            const SkillRegistration(name: 'team-notes', description: '   ')),
        throwsArgumentError,
      );

      await registry.refresh();

      expect(registry.available, isEmpty);
    });

    test('重复注册同名运行时技能抛 StateError', () async {
      final SkillRegistry registry = _registry();
      final Disposer off = registry.register(
          const SkillRegistration(name: 'team-notes', description: '第一份'));

      expect(
        () => registry.register(
            const SkillRegistration(name: 'team-notes', description: '第二份')),
        throwsStateError,
      );
      await registry.refresh();
      expect(registry.available.single.description, '第一份');

      off();
      await registry.refresh();

      expect(registry.available, isEmpty);
    });
  });

  group('快照与通知', () {
    test('快照变化时通知一次，同一份输出刷新两次只通知一次', () async {
      final SkillRegistry registry =
          _registry(debounce: const Duration(milliseconds: 50));
      int notifications = 0;
      final Disposer off = registry.onChange(() => notifications++);
      addTearDown(off);
      registry.registerProvider(
          _FakeProvider('filesystem', skills: <String>['alpha']));

      await registry.refresh();
      expect(notifications, 1);
      expect(_namesOf(registry.available), <String>['alpha']);

      await registry.refresh();
      expect(notifications, 1);

      registry.register(
          const SkillRegistration(name: 'beta', description: '运行时技能'));
      await registry.refresh();
      expect(notifications, 2);
      expect(_namesOf(registry.available), <String>['alpha', 'beta']);

      // 让 invalidate 的合并窗口彻底过去：内容不变则不应再通知。
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(notifications, 2);
      expect(_namesOf(registry.available), <String>['alpha', 'beta']);
    });

    test('监听器可撤销，撤销后不再收到通知', () async {
      final SkillRegistry registry = _registry();
      int first = 0;
      int second = 0;
      final Disposer offFirst = registry.onChange(() => first++);
      final Disposer offSecond = registry.onChange(() => second++);
      addTearDown(offFirst);
      addTearDown(offSecond);
      registry.registerProvider(
          _FakeProvider('filesystem', skills: <String>['alpha']));

      await registry.refresh();
      expect(first, 1);
      expect(second, 1);

      offFirst();
      registry.register(
          const SkillRegistration(name: 'beta', description: '运行时技能'));
      await registry.refresh();

      expect(first, 1);
      expect(second, 2);
    });

    test('密集的失效请求在合并窗口内只收集一次', () async {
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['alpha']);
      final SkillRegistry registry =
          _registry(debounce: const Duration(milliseconds: 20));
      registry.registerProvider(provider);
      for (int index = 0; index < 5; index++) {
        registry.register(
            SkillRegistration(name: 'runtime-$index', description: '运行时技能'));
      }

      expect(provider.listCalls, 0);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(provider.listCalls, 1);
      expect(_namesOf(registry.available), <String>[
        'alpha',
        'runtime-0',
        'runtime-1',
        'runtime-2',
        'runtime-3',
        'runtime-4',
      ]);
    });

    test('modelInvocable 为假的候选只出现在 available', () async {
      final SkillRegistry registry = _registry();
      registry.registerProvider(
          _FakeProvider('filesystem', skills: <String>['alpha']));
      registry.registerProvider(_FakeProvider(
        'user-skills',
        skills: <String>['beta'],
        rank: 500,
        source: kSkillSourceUserAgents,
        modelInvocable: false,
      ));

      await registry.refresh();

      expect(_namesOf(registry.available), <String>['alpha', 'beta']);
      expect(_namesOf(registry.modelInvocable), <String>['alpha']);
    });

    test('释放后清空快照与监听并拒绝再注册', () async {
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['alpha']);
      final SkillRegistry registry = SkillRegistry();
      registry.registerProvider(provider);
      int notifications = 0;
      final Disposer off = registry.onChange(() => notifications++);
      addTearDown(off);

      await registry.refresh();
      expect(registry.available, hasLength(1));

      registry.dispose();

      expect(registry.disposed, isTrue);
      expect(registry.available, isEmpty);
      expect(registry.providers, isEmpty);
      expect(() => registry.registerProvider(provider), throwsStateError);
      expect(
        () => registry
            .register(const SkillRegistration(name: 'beta', description: '说明')),
        throwsStateError,
      );

      await registry.refresh();

      expect(notifications, 1);
      expect(registry.available, isEmpty);
    });
  });

  group('加载', () {
    test('未知或非法名字返回 null 且不打扰 provider', () async {
      final SkillRegistry registry = _registry();
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['alpha']);
      registry.registerProvider(provider);
      await registry.refresh();

      expect(await registry.load('missing'), isNull);
      expect(await registry.load('Bad Name'), isNull);
      expect(await registry.load(''), isNull);
      expect(provider.loadedNames, isEmpty);
    });

    test('provider 返回 null 时注册表返回 null', () async {
      final _FakeProvider provider =
          _FakeProvider('filesystem', skills: <String>['ghost']);
      final SkillRegistry registry = _registry();
      registry.registerProvider(provider);
      await registry.refresh();

      provider.skills.clear();

      expect(await registry.load('ghost'), isNull);
      expect(provider.loadedNames, <String>['ghost']);
    });

    test('provider 的定义连正文与资源基址一起返回', () async {
      final SkillRegistry registry = _registry();
      registry.registerProvider(
          _FakeProvider('filesystem', skills: <String>['alpha']));
      await registry.refresh();

      final SkillDefinition? definition = await registry.load('alpha');

      expect(definition?.content, 'alpha 的正文');
      expect(definition?.summary.provider, 'filesystem');
      expect(
        definition?.resourceBase,
        isA<SkillDirectoryResource>().having(
            (SkillDirectoryResource resource) => resource.path,
            'path',
            '/skills/alpha'),
      );
    });

    test('provider 列举失败只降级它自己', () async {
      final List<String> warnings = <String>[];
      final SkillRegistry registry = _registry(onWarning: warnings.add);
      registry.registerProvider(_FakeProvider(
        'broken-source',
        skills: <String>['ghost'],
        fails: true,
      ));
      registry.registerProvider(
          _FakeProvider('filesystem', skills: <String>['alpha']));

      await registry.refresh();

      expect(_namesOf(registry.available), <String>['alpha']);
      expect(warnings.single, contains('broken-source'));
      expect(await registry.load('ghost'), isNull);
    });
  });
}

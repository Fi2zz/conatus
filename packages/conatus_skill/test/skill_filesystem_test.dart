import 'dart:async';
import 'dart:io';

import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

Directory _createTemp(String prefix) {
  final Directory directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

String _path(Directory root, String relative) =>
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

void _writeSkillDocument(
  String path,
  String name, {
  String description = '一件用于测试的技能。',
  String body = '正文',
}) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '---\nname: $name\ndescription: $description\n---\n$body\n',
  );
}

SkillRoot _root(
  Directory path, {
  int rank = 100,
  String source = kSkillSourceCustom,
}) =>
    SkillRoot(path: path.path, source: source, rank: rank);

/// 目录监听的建立与首次投递之间存在竞态，故持续写入新文件直到出现信号。
Future<bool> _writeUntilSignalled(Future<void> signal, Directory root) async {
  for (int index = 0; index < 50; index++) {
    _writeSkillDocument(_path(root, 'probe-$index.md'), 'probe-$index');
    final bool delivered = await Future.any<bool>(<Future<bool>>[
      signal.then((void _) => true),
      Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
    ]);
    if (delivered) return true;
  }
  return false;
}

void main() {
  group('SkillFilesystemProvider 发现', () {
    test('目录束与平铺文件按路径发现，其余条目被忽略并上报', () async {
      final Directory root = _createTemp('conatus-skill-fs-');
      _writeSkillDocument(_path(root, 'aardvark.md'), 'aardvark');
      _writeSkillDocument(_path(root, 'zeta/SKILL.md'), 'zeta');
      File(_path(root, 'notes.txt')).writeAsStringSync('不是 Markdown');
      Directory(_path(root, 'gamma')).createSync(recursive: true);
      File(_path(root, 'gamma/README.md')).writeAsStringSync('# 没有 SKILL.md');
      File(_path(root, 'broken.md')).writeAsStringSync('# 没有 frontmatter\n');

      final List<String> warnings = <String>[];
      final SkillFilesystemProvider provider = SkillFilesystemProvider(
        roots: <SkillRoot>[_root(root)],
        onWarning: warnings.add,
      );

      final List<SkillCandidate> candidates = await provider.list();

      expect(
        candidates.map((SkillCandidate c) => c.summary.name),
        <String>['aardvark', 'zeta'],
      );
      expect(
        candidates.map((SkillCandidate c) => c.rank),
        <int>[100, 100],
      );
      expect(
        candidates.map((SkillCandidate c) => c.summary.provider),
        <String>[kSkillFilesystemProvider, kSkillFilesystemProvider],
      );
      final List<String> paths = <String>[
        for (final SkillCandidate c in candidates) c.summary.path!,
      ];
      expect(paths, List<String>.of(paths)..sort());
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('broken.md'));
      expect(warnings.single, contains('缺少 frontmatter'));
    });

    test('根目录不存在时返回空候选且不抛', () async {
      final Directory root = _createTemp('conatus-skill-fs-');
      final SkillFilesystemProvider provider = SkillFilesystemProvider(
        roots: <SkillRoot>[
          _root(Directory(_path(root, 'missing'))),
        ],
      );

      expect(await provider.list(), isEmpty);
    });

    test('两个根同名时 rank 小者胜出，被遮蔽者上报', () async {
      final Directory strong = _createTemp('conatus-skill-strong-');
      final Directory weak = _createTemp('conatus-skill-weak-');
      _writeSkillDocument(_path(strong, 'shared/SKILL.md'), 'shared',
          description: '强根版本');
      _writeSkillDocument(_path(weak, 'shared.md'), 'shared',
          description: '弱根版本');

      final List<String> warnings = <String>[];
      final SkillRegistry registry = SkillRegistry(onWarning: warnings.add);
      addTearDown(registry.dispose);
      registry.registerProvider(SkillFilesystemProvider(
        roots: <SkillRoot>[
          SkillRoot(
            path: weak.path,
            source: kSkillSourceUserAgents,
            rank: 500,
          ),
          SkillRoot(
            path: strong.path,
            source: kSkillSourceProjectConatus,
            rank: 100,
          ),
        ],
      ));

      await registry.refresh();

      expect(registry.available, hasLength(1));
      expect(registry.available.single.name, 'shared');
      expect(registry.available.single.source, kSkillSourceProjectConatus);
      expect(registry.available.single.description, '强根版本');
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('shared'));
      expect(warnings.single, contains(kSkillSourceUserAgents));
    });
  });

  group('SkillFilesystemProvider 加载', () {
    test('返回去 frontmatter 的正文与资源基址', () async {
      final Directory root = _createTemp('conatus-skill-fs-');
      _writeSkillDocument(_path(root, 'alpha/SKILL.md'), 'alpha',
          body: '  按步骤执行  ');
      _writeSkillDocument(_path(root, 'beta.md'), 'beta', body: '平铺正文');
      final SkillFilesystemProvider provider =
          SkillFilesystemProvider(roots: <SkillRoot>[_root(root)]);
      final Map<String, SkillSummary> summaries = <String, SkillSummary>{
        for (final SkillCandidate c in await provider.list())
          c.summary.name: c.summary,
      };

      final SkillDefinition bundled =
          (await provider.load(summaries['alpha']!))!;
      expect(bundled.content, '按步骤执行');
      expect(bundled.summary.path, _path(root, 'alpha/SKILL.md'));
      expect(
        (bundled.resourceBase! as SkillDirectoryResource).path,
        _path(root, 'alpha'),
      );

      final SkillDefinition flat = (await provider.load(summaries['beta']!))!;
      expect(flat.content, '平铺正文');
      expect(
        (flat.resourceBase! as SkillDirectoryResource).path,
        root.path,
      );
    });

    test('文件消失或摘要没有路径时返回 null', () async {
      final Directory root = _createTemp('conatus-skill-fs-');
      _writeSkillDocument(_path(root, 'beta.md'), 'beta');
      final SkillFilesystemProvider provider =
          SkillFilesystemProvider(roots: <SkillRoot>[_root(root)]);
      final SkillSummary summary = (await provider.list()).single.summary;

      File(summary.path!).deleteSync();
      expect(await provider.load(summary), isNull);

      const SkillSummary orphan = SkillSummary(
        name: 'orphan',
        description: '没有路径的摘要',
        source: kSkillSourceCustom,
        provider: kSkillFilesystemProvider,
      );
      expect(await provider.load(orphan), isNull);
    });
  });

  group('defaultSkillRoots', () {
    test('不含用户根时只给出两个项目根', () {
      final Directory project = _createTemp('conatus-skill-project-');
      final List<SkillRoot> roots = defaultSkillRoots(
        projectRoot: project.path,
        includeUserRoots: false,
      );

      expect(roots, hasLength(2));
      expect(roots.map((SkillRoot r) => r.rank), <int>[100, 200]);
      expect(
        roots.map((SkillRoot r) => r.source),
        <String>[kSkillSourceProjectConatus, kSkillSourceProjectAgents],
      );
      expect(
        roots.every((SkillRoot r) => r.path.startsWith(project.path)),
        isTrue,
      );
      expect(
          roots[0].path, endsWith('.conatus${Platform.pathSeparator}skills'));
      expect(roots[1].path, endsWith('.agents${Platform.pathSeparator}skills'));
    });

    test('含用户根时追加两条 rank 400/500 的根', () {
      final Directory project = _createTemp('conatus-skill-project-');
      final List<SkillRoot> roots =
          defaultSkillRoots(projectRoot: project.path);

      expect(roots, hasLength(4));
      expect(roots.map((SkillRoot r) => r.rank), <int>[100, 200, 400, 500]);
      expect(roots[2].source, kSkillSourceUserConatus);
      expect(roots[3].source, kSkillSourceUserAgents);
      expect(
        roots.every((SkillRoot r) => r.path.endsWith('skills')),
        isTrue,
      );
    });
  });

  group('findProjectRoot', () {
    test('没有 .git 的目录树下返回传入的起点', () {
      final Directory root = _createTemp('conatus-skill-root-');
      final Directory nested = Directory(_path(root, 'a/b'))
        ..createSync(recursive: true);

      expect(findProjectRoot(from: nested.path), nested.path);
    });
  });

  group('SkillRootWatcher', () {
    test('已存在的根下新增技能文件后收到 onInvalidate', () async {
      final Directory root = _createTemp('conatus-skill-watch-');
      final Completer<void> signal = Completer<void>();
      final SkillRootWatcher watcher = SkillRootWatcher(
        roots: <SkillRoot>[_root(root)],
        onInvalidate: () {
          if (!signal.isCompleted) signal.complete();
        },
        debounce: const Duration(milliseconds: 50),
      );
      addTearDown(watcher.stop);

      watcher.start();

      expect(
        await _writeUntilSignalled(signal.future, root),
        isTrue,
        reason: '5 秒内应收到一次 onInvalidate',
      );
    });

    test('stop() 之后不再收到 onInvalidate', () async {
      final Directory root = _createTemp('conatus-skill-watch-');
      final List<int> signals = <int>[];
      final Completer<void> first = Completer<void>();
      final SkillRootWatcher watcher = SkillRootWatcher(
        roots: <SkillRoot>[_root(root)],
        onInvalidate: () {
          signals.add(signals.length);
          if (!first.isCompleted) first.complete();
        },
        debounce: const Duration(milliseconds: 50),
      );
      addTearDown(watcher.stop);

      watcher.start();
      expect(
        await _writeUntilSignalled(first.future, root),
        isTrue,
        reason: '监听未在 5 秒内建立',
      );

      watcher.stop();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      signals.clear();
      _writeSkillDocument(_path(root, 'after-stop.md'), 'after-stop');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(signals, isEmpty);
    });

    test('不存在的根不报错也不产出信号', () async {
      final Directory root = _createTemp('conatus-skill-watch-');
      final List<int> signals = <int>[];
      final SkillRootWatcher watcher = SkillRootWatcher(
        roots: <SkillRoot>[
          _root(Directory(_path(root, 'missing'))),
        ],
        onInvalidate: () => signals.add(signals.length),
        debounce: const Duration(milliseconds: 50),
      );
      addTearDown(watcher.stop);

      watcher.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(signals, isEmpty);
    });
  });
}

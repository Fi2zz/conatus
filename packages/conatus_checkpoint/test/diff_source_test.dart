/// `/diff` 数据源：checkpoint 两轮差异与工作区 git 差异。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:conatus_diff/conatus_diff.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

/// 临时工作区 + archive 检查点管理器（注入产品只读策略）。
(CheckpointManager, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-cp-diff');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  final CheckpointManager manager = CheckpointManager(
    store: ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      policy: kProductPolicy,
    ),
    options: const CheckpointOptions(),
  );
  return (manager, root);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<void> _git(String root, List<String> args) async {
  final ProcessResult result = await Process.run(
    'git',
    args,
    workingDirectory: root,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

Future<void> _initRepo(String root) async {
  await _git(root, <String>['init', '-q']);
  await _git(root, <String>['config', 'user.email', 't@example.com']);
  await _git(root, <String>['config', 'user.name', 'T']);
}

Future<void> _commitAll(String root, String message) async {
  await _git(root, <String>['add', '.']);
  await _git(root, <String>['commit', '-qm', message]);
}

void main() {
  test('turn compares the target turn with the previous one', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    _write(root, 'b.txt', 'new\n');
    await manager.recordTurn(); // turn 1

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.turn);

    expect(diffs.map((FileDiff d) => d.path), <String>['a.txt', 'b.txt']);
    final FileDiff modified = diffs.first;
    expect(modified.status, 'modified');
    expect(modified.additions, 1);
    expect(modified.deletions, 1);
    expect(modified.hunks, isNotEmpty);
    final FileDiff added = diffs.last;
    expect(added.status, 'added');
    expect(added.additions, 1);
  });

  test('turn waits for the in-flight snapshot', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    final Future<String?> turn = manager.recordTurn(); // 不 await：模拟刚收口

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.turn);
    await turn;

    expect(diffs.single.path, 'a.txt');
    expect(diffs.single.status, 'modified');
    expect(diffs.single.additions, 1);
  });

  test('negative turn yields no comparable turn', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');

    final DiffSource source = DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: -1,
    );
    final List<FileDiff> diffs = await source.load(DiffScope.turn);

    expect(diffs, isEmpty);
    expect(source.notice, contains('还没有可比较的轮次'));
  });

  test('missing checkpoints yield an empty diff', () async {
    final (CheckpointManager manager, String root) = _workspace();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 'never-bound',
      turn: 1,
    ).load(DiffScope.turn);

    expect(diffs, isEmpty);
  });

  test('turn omits explicit target: uses the turn after flush', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    final Future<String?> turn = manager.recordTurn(); // 不 await：刚收口

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
    ).load(DiffScope.turn);
    await turn;

    expect(diffs.single.path, 'a.txt');
    expect(diffs.single.status, 'modified');
  });

  test('turn 0 has no comparable turn', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'hello\n');
    await manager.bind('s1');

    final DiffSource source = DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    );
    final List<FileDiff> diffs = await source.load(DiffScope.turn);

    expect(diffs, isEmpty);
    expect(source.notice, contains('还没有可比较的轮次'));
  });

  test('turn excludes .opencode paths captured by the filter', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, '.opencode/config.json', 'v0\n');
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, '.opencode/config.json', 'v1\n');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.turn);

    expect(diffs.map((FileDiff d) => d.path), <String>['a.txt']);
    expect(diffs.single.additions, 1);
    expect(diffs.single.status, 'modified');
    expect(manager.list(), hasLength(2));
    expect(diffs.any((FileDiff d) => d.path.startsWith('.opencode')), isFalse);
  });

  test('working reports tracked changes and untracked files', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(root, 'tracked.txt', 'one\n');
    await _commitAll(root, 'init');
    _write(root, 'tracked.txt', 'two\n');
    _write(root, 'untracked.txt', 'fresh\n');

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.working);

    final Map<String, FileDiff> byPath = <String, FileDiff>{
      for (final FileDiff diff in diffs) diff.path: diff,
    };
    expect(byPath['tracked.txt']?.status, 'modified');
    expect(byPath['tracked.txt']?.additions, 1);
    expect(byPath['untracked.txt']?.status, 'added');
    expect(byPath['untracked.txt']?.additions, 1);
  });

  test('working falls back to turn outside a git repository', () async {
    final (CheckpointManager manager, String root) = _workspace();
    _write(root, 'a.txt', 'v0\n');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    ).load(DiffScope.working);

    expect(diffs.single.path, 'a.txt');
    expect(diffs.single.status, 'modified');
  });

  test('working surfaces git failures instead of falling back', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(root, 'a.txt', 'v0\n');
    await _commitAll(root, 'init');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();
    // 索引损坏：rev-parse 仍是仓库，git diff 失败——不得回落成 turn 差异。
    File(
      '$root${Platform.pathSeparator}.git${Platform.pathSeparator}index',
    ).writeAsStringSync('garbage');

    final DiffSource source = DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    );
    final List<FileDiff> diffs = await source.load(DiffScope.working);

    expect(diffs, isEmpty);
    expect(source.notice, contains('git diff 失败'));

    // 之后的 turn 读取不得沿用上一次 working 的 notice。
    final List<FileDiff> turnDiffs = await source.load(DiffScope.turn);
    expect(turnDiffs.single.path, 'a.txt');
    expect(source.notice, isNull);
  });

  test('bare repositories surface a notice instead of falling back', () async {
    final (CheckpointManager manager, _) = _workspace();
    final Directory bare = Directory.systemTemp.createTempSync('conatus-bare');
    addTearDown(() => bare.deleteSync(recursive: true));
    await _git(bare.path, <String>['init', '--bare', '-q']);

    final DiffSource source = DiffSource(
      workdir: bare.path,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    );
    final List<FileDiff> diffs = await source.load(DiffScope.working);

    expect(diffs, isEmpty);
    expect(source.notice, contains('裸仓库'));
  });

  test('unusable workdir surfaces a git-unavailable notice', () async {
    final (CheckpointManager manager, String root) = _workspace();
    final DiffSource source = DiffSource(
      workdir: '$root${Platform.pathSeparator}missing',
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    );

    final List<FileDiff> diffs = await source.load(DiffScope.working);

    expect(diffs, isEmpty);
    expect(source.notice, contains('git 不可用'));
  });

  test('credentials and build paths are hidden in both scopes', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(root, '.env', 'v0\n');
    _write(root, 'build/out.txt', 'v0\n');
    _write(root, 'a.txt', 'v0\n');
    await _commitAll(root, 'init');
    await manager.bind('s1');
    _write(root, '.env', 'v1\n');
    _write(root, 'build/out.txt', 'v1\n');
    _write(root, 'a.txt', 'v1\n');
    await manager.recordTurn();

    final DiffSource source = DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 1,
    );
    final List<FileDiff> working = await source.load(DiffScope.working);
    final List<FileDiff> turn = await source.load(DiffScope.turn);

    expect(working.map((FileDiff d) => d.path), <String>['a.txt']);
    expect(turn.map((FileDiff d) => d.path), <String>['a.txt']);
  });

  test(
    'a change whose both sides are unreadable keeps a file-level entry',
    () async {
      final (CheckpointManager _, String root) = _workspace();
      final CheckpointManager manager = _NullReadManager(
        store: ArchiveCheckpointStore(
          root: root,
          projectDir: '$root${Platform.pathSeparator}.conatus',
          policy: kProductPolicy,
        ),
        options: const CheckpointOptions(),
      );

      final List<FileDiff> diffs = await DiffSource(
        workdir: root,
        checkpoint: manager,
        sessionId: 's1',
        turn: 1,
      ).load(DiffScope.turn);

      expect(diffs.single.path, 'old.txt');
      expect(diffs.single.status, 'modified');
      expect(diffs.single.hunks, isEmpty);
    },
  );

  test('working marks deleted tracked files', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(root, 'gone.txt', 'one\ntwo\n');
    await _commitAll(root, 'init');
    File('$root${Platform.pathSeparator}gone.txt').deleteSync();

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.working);

    final FileDiff deleted = diffs.single;
    expect(deleted.path, 'gone.txt');
    expect(deleted.status, 'deleted');
    expect(deleted.deletions, 2);
    expect(deleted.hunks, isNotEmpty);
  });

  test('working keeps multiple hunks from git', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(
      root,
      'multi.txt',
      <String>[for (int i = 0; i < 20; i++) 'line $i'].join('\n'),
    );
    await _commitAll(root, 'init');
    final List<String> lines = <String>[for (int i = 0; i < 20; i++) 'line $i'];
    lines[1] = 'changed early';
    lines[18] = 'changed late';
    _write(root, 'multi.txt', lines.join('\n'));

    final FileDiff diff = (await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.working))
        .single;

    expect(diff.status, 'modified');
    expect(diff.additions, 2);
    expect(diff.deletions, 2);
    expect(diff.hunks, hasLength(2));
  });

  test('large and numerous untracked files are truncated', () async {
    final (CheckpointManager manager, String root) = _workspace();
    await _initRepo(root);
    _write(root, 'seed.txt', 'seed\n');
    await _commitAll(root, 'init');
    final String sep = Platform.pathSeparator;
    File(
      '$root${sep}big.bin',
    ).writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 65));
    for (int i = 0; i < 205; i++) {
      _write(root, 'many/f${i.toString().padLeft(3, '0')}.txt', 'x\n');
    }

    final List<FileDiff> diffs = await DiffSource(
      workdir: root,
      checkpoint: manager,
      sessionId: 's1',
      turn: 0,
    ).load(DiffScope.working);

    final FileDiff big = diffs.firstWhere(
      (FileDiff diff) => diff.path == 'big.bin',
    );
    expect(big.truncated, isTrue);
    expect(big.hunks, isEmpty);

    final List<FileDiff> many = <FileDiff>[
      for (final FileDiff diff in diffs)
        if (diff.path.startsWith('many/')) diff,
    ];
    expect(many, hasLength(205));
    expect(
      many.where((FileDiff diff) => diff.truncated).length,
      6,
      reason: 'big.bin 占掉一个预算名额；其余未读的只给文件级截断条目',
    );
  });
}

/// 两轮内容都读不出的管理器：验证旧格式检查点仍保留文件级变化。
class _NullReadManager extends CheckpointManager {
  _NullReadManager({required super.store, required super.options});

  @override
  Future<List<CheckpointFileChange>> changesBetween(
    String sessionId,
    int fromTurn,
    int toTurn,
  ) async =>
      const <CheckpointFileChange>[
        CheckpointFileChange(path: 'old.txt', status: 'modified'),
      ];

  @override
  Future<List<int>?> readFile(String sessionId, int turn, String path) async =>
      null;
}

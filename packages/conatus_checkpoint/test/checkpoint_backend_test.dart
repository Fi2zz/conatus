/// 后端选择：`auto` 按 git 可用性分流，`git` / `archive` 为显式固定。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

late Directory _ws;

void _setUp() {
  _ws = Directory.systemTemp.createTempSync('conatus-backend');
  addTearDown(() => _ws.deleteSync(recursive: true));
  Directory('${_ws.path}${Platform.pathSeparator}.conatus').createSync();
}

Future<CheckpointStore> _open(CheckpointOptions options, GitRunner git) =>
    openCheckpointStore(
      options: options,
      root: _ws.path,
      projectDir: '${_ws.path}${Platform.pathSeparator}.conatus',
      git: git,
    );

void main() {
  setUp(_setUp);

  test('auto：有 git 用影子仓库', () async {
    final CheckpointStore store = await _open(
      const CheckpointOptions(),
      const _FakeGit(hasGit: true),
    );
    expect(store, isA<GitShadowStore>());
  });

  test('auto：无 git 退回自研归档', () async {
    final CheckpointStore store = await _open(
      const CheckpointOptions(),
      const UnavailableGitRunner(),
    );
    expect(store, isA<ArchiveCheckpointStore>());
  });

  test('archive：固定归档，不探测 git', () async {
    // available 探针被调用就会抛——固定归档时根本不该问。
    final CheckpointStore store = await _open(
      const CheckpointOptions(backend: CheckpointBackend.archive),
      const _ExplodingGit(),
    );
    expect(store, isA<ArchiveCheckpointStore>());
  });

  test('git：固定影子，不因不可用而降级', () async {
    final CheckpointStore store = await _open(
      const CheckpointOptions(backend: CheckpointBackend.git),
      const UnavailableGitRunner(),
    );
    expect(
      store,
      isA<GitShadowStore>(),
      reason: '显式写了 git 就不静默换实现——不可用时每轮快照报错更易察觉',
    );
  });

  test('keep / policy 透传到选中的实现', () async {
    const CheckpointPolicy policy = CheckpointPolicy(
      ignore: <String>['dist'],
      readOnlyPrefixes: <String>['.opencode'],
    );
    final CheckpointStore store = await _open(
      const CheckpointOptions(
        keep: 3,
        backend: CheckpointBackend.archive,
        policy: policy,
      ),
      const _ExplodingGit(),
    );
    expect(store.keep, 3);
    expect(store.ignore, <String>['dist']);
    expect(store.policy.readOnlyPrefixes, <String>['.opencode']);
  });
}

class _FakeGit implements GitRunner {
  const _FakeGit({required this.hasGit});

  final bool hasGit;

  @override
  Future<bool> available() async => hasGit;

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async =>
      const GitResult(1, '', 'nope');

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      const GitResult(1, '', 'nope');
}

/// 固定归档时不该被问「git 能不能用」，问了即失败。
class _ExplodingGit implements GitRunner {
  const _ExplodingGit();

  @override
  Future<bool> available() async =>
      throw StateError('backend=archive 不该探测 git');

  @override
  Future<GitResult> run(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) async =>
      throw StateError('不该跑 git');

  @override
  GitResult runSync(
    List<String> args, {
    required String gitDir,
    required String workTree,
  }) =>
      throw StateError('不该跑 git');
}

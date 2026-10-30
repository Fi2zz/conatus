/// 影子 git 索引与时间线：prune、清空、多会话隔离、清单与对话切点。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_shadow_fixtures.dart';

late bool _gitOk;

void main() {
  setUpAll(() async {
    _gitOk = await const ProcessGitRunner().available();
  });

  test('prune 保留基线 + 最近 keep-1 轮', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture(keep: 3);
    for (int turn = 0; turn <= 4; turn++) {
      f.write('a.txt', 'v$turn');
      await f.store.snapshot('s1', turn);
    }
    expect(f.store.turnsOf('s1'), <int>[0, 3, 4]);
  });

  test('clearSession 清掉该会话的索引与 tag', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0);
    await f.store.snapshot('s1', 1);
    expect(f.store.turnsOf('s1'), <int>[0, 1]);

    await f.store.clearSession('s1');
    expect(f.store.turnsOf('s1'), isEmpty);
  });

  test('clearSession 不留下 refs/checkpoints 孤儿引用', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0);
    await f.store.snapshot('s1', 1);
    expect(f.refsOf('s1'), isNotEmpty);

    await f.store.clearSession('s1');
    expect(f.refsOf('s1'), isEmpty);
  });

  test('两个会话各自独立的时间线', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'shared');
    await f.store.snapshot('s1', 0);
    await f.store.snapshot('s2', 0);
    f.write('a.txt', 'from-s1');
    await f.store.snapshot('s1', 1);

    expect(f.store.turnsOf('s1'), <int>[0, 1]);
    expect(f.store.turnsOf('s2'), <int>[0]);
    // s2 的基线仍是 shared：对象共享但时间线不串。
    await f.store.restore('s2', 0);
    expect(f.read('a.txt'), 'shared');
  });

  test('恢复不存在的轮次抛 missing-checkpoint', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0);
    await expectLater(
      f.store.restore('s1', 7),
      throwsA(
        isA<CheckpointException>().having(
          (CheckpointException e) => e.code,
          'code',
          'missing-checkpoint',
        ),
      ),
    );
  });

  test('lastEventId 随轮次留存（rewind 的对话切点）', () async {
    if (!_gitOk) return;
    final ShadowFixture f = createShadowFixture();
    f.write('a.txt', 'v0');
    await f.store.snapshot('s1', 0, lastEventId: 'ev-0');
    f.write('a.txt', 'v1');
    await f.store.snapshot('s1', 1, lastEventId: 'ev-1');

    final CheckpointManifest m = await f.store.loadManifest('s1', 1);
    expect(m.lastEventId, 'ev-1');
    expect(m.kind, 'delta');
  });
}

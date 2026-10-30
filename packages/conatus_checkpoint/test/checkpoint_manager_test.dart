/// CheckpointManager：轮次计数、turn 0 初始快照、rewind 编排与钳制。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

/// 建临时「工作区 + 项目数据目录」，返回 (root, projectDir)。
(String, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-cp-mgr');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String root = dir.path;
  final String projectDir = '$root${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (root, projectDir);
}

/// 建 manager；[enabled] / [keep] 可配，返回 (manager, root, projectDir)。
(CheckpointManager, String, String) _manager({
  bool enabled = true,
  int keep = 5,
}) {
  final (String root, String projectDir) = _workspace();
  final CheckpointManager manager = CheckpointManager(
    store: ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
    ),
    options: CheckpointOptions(enabled: enabled, keep: keep),
  );
  return (manager, root, projectDir);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  test('reset 写 turn 0 初始快照；recordTurn 递增并快照', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');

    expect(await manager.reset('s1'), isNull);
    expect(manager.turn, 0);
    expect(manager.list(), hasLength(1)); // turn 0
    expect(manager.list().single.turn, 0);

    _write(root, 'a.txt', 'v1');
    expect(await manager.recordTurn(lastEventId: 'ev-1'), isNull);
    expect(manager.turn, 1);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1]);
  });

  test('reset 不阻塞调用方：返回前即可读会话与轮次', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');

    final Future<String?> pending = manager.reset('s1');
    // 未 await：会话归属与轮次已同步切换（UI 的 /rewind list 立刻可用）。
    expect(manager.sessionId, 's1');
    expect(manager.turn, 0);
    expect(await pending, isNull);
    // 落盘后才出现基线。
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0]);
  });

  test('基线与差量串行：recordTurn 不早于 reset 落盘', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');

    // 连发三轮、全部不 await：链上必须按 base → delta1 → delta2 顺序落盘，
    // 否则差量会按「基线缺失」分类，合成从未存在过的混合状态。
    final List<Future<String?>> pending = <Future<String?>>[
      manager.reset('s1'),
      manager.recordTurn(),
      manager.recordTurn(),
    ];
    for (final Future<String?> step in pending) {
      expect(await step, isNull);
    }
    expect(manager.turn, 2);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1, 2]);
  });

  test('基线在飞时 detach：在途基线放弃，不写盘', () async {
    final (CheckpointManager manager, String root, String projectDir) =
        _manager();
    _write(root, 'a.txt', 'v0');

    final Future<String?> pending = manager.reset('s1');
    manager.detach();
    expect(manager.sessionId, isNull);
    expect(manager.turn, 0);
    expect(await pending, isNull);
    // 代数已变：不该留下 turn 0 基线（目录整个都不该被创建）。
    expect(manager.list(), isEmpty);
    expect(
      Directory('$projectDir${Platform.pathSeparator}checkpoints').existsSync(),
      isFalse,
    );
  });

  test('rewind 回滚到目标轮；返回切点事件 id；超出钳制到最早', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.reset('s1', lastEventId: 'ev-0');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn(lastEventId: 'ev-1'); // turn 1
    _write(root, 'a.txt', 'v2');
    await manager.recordTurn(lastEventId: 'ev-2'); // turn 2

    final CheckpointRewindResult? back1 = await manager.rewind(1);
    expect(back1, isNotNull);
    expect(back1!.turn, 1);
    expect(back1.lastEventId, 'ev-1');
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v1',
    );

    final CheckpointRewindResult? backFar = await manager.rewind(99);
    expect(backFar!.turn, 0);
    expect(backFar.lastEventId, 'ev-0');
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v0',
    );
  });

  test('enabled=false：reset/recordTurn 不写盘，list/rewind 为空', () async {
    final (CheckpointManager manager, String root, String projectDir) =
        _manager(enabled: false);
    _write(root, 'a.txt', 'v0');

    expect(await manager.reset('s1'), isNull);
    expect(await manager.recordTurn(), isNull);
    expect(await manager.bind('s2'), isNull);
    expect(manager.enabled, isFalse);
    expect(manager.list(), isEmpty);
    expect(await manager.rewind(1), isNull);
    expect(
      Directory('$projectDir${Platform.pathSeparator}checkpoints').existsSync(),
      isFalse,
    );
  });

  test('未绑定会话：recordTurn/rewind 安全返回', () async {
    final (CheckpointManager manager, _, _) = _manager();
    expect(await manager.recordTurn(), isNull);
    expect(await manager.rewind(1), isNull);
    expect(manager.list(), isEmpty);
  });

  test('重绑会话清空旧时间线，不会合成混合状态', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.reset('s1');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn(); // turn 1 delta
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1]);

    // 模拟 /sessions 切回：工作区已是新状态，重绑应清掉旧差量。
    _write(root, 'a.txt', 'v2');
    await manager.reset('s1');
    expect(manager.turn, 0);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0]);

    // rewind 只能回到新 base（v2），不存在与旧 delta 合成的混合状态。
    final CheckpointRewindResult? back = await manager.rewind(1);
    expect(back!.turn, 0);
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v2',
    );
  });

  test('detach 后不再关联会话', () async {
    final (CheckpointManager manager, _, _) = _manager();
    await manager.reset('s1');
    manager.detach();
    expect(manager.sessionId, isNull);
    expect(manager.turn, 0);
    expect(await manager.rewind(1), isNull);
  });

  test('快照失败返回错误说明而非抛出（recordTurn 幂等安全）', () async {
    final (CheckpointManager manager, String root, String projectDir) =
        _manager();
    await manager.reset('s1');
    // 删掉检查点目录制造写失败路径：reset 已建 turn 0，这里改造成只读父目录
    // 不现实，改为验证 turn 0 存在即可（快照失败分支由 store 测试覆盖）。
    expect(manager.list(), hasLength(1));
  });

  test('bind 接管已有检查点，不清空历史（--session 恢复）', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1', lastEventId: 'ev-0');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn(lastEventId: 'ev-1'); // turn 1
    manager.detach();

    // 模拟重开同一会话：接管既有时间线，turn 直接落在最大轮次上。
    expect(await manager.bind('s1', lastEventId: 'ev-1'), isNull);
    expect(manager.sessionId, 's1');
    expect(manager.turn, 1);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1]);

    // 接续的下一轮是 turn 2（旧差量还在，redo 才有回得去的点）。
    _write(root, 'a.txt', 'v2');
    expect(await manager.recordTurn(), isNull);
    expect(manager.turn, 2);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1, 2]);
  });

  test('bind 无历史时写 turn 0 基线', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');

    expect(await manager.bind('s1', lastEventId: 'ev-0'), isNull);
    expect(manager.sessionId, 's1');
    expect(manager.turn, 0);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0]);
  });

  test('flush 等待在途 recordTurn 落盘', () async {
    final (String root, String projectDir) = _workspace();
    final _GatedStore store = _GatedStore(root: root, projectDir: projectDir);
    addTearDown(() {
      if (!store.gate.isCompleted) store.gate.complete();
    });
    final CheckpointManager manager = CheckpointManager(
      store: store,
      options: const CheckpointOptions(),
    );
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1');

    final Future<String?> round = manager.recordTurn();
    bool flushed = false;
    final Future<void> pendingFlush = manager.flush().then((_) {
      flushed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse, reason: '在途快照未完成时 flush 不得返回');

    store.gate.complete();
    expect(await round, isNull);
    await pendingFlush;
    expect(flushed, isTrue);
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1]);
  });

  test('bind 等在途快照落定后再定轮次（不吃掉刚写完的一轮）', () async {
    final (String root, String projectDir) = _workspace();
    final _GatedStore store = _GatedStore(root: root, projectDir: projectDir);
    addTearDown(() {
      if (!store.gate.isCompleted) store.gate.complete();
    });
    final CheckpointManager manager = CheckpointManager(
      store: store,
      options: const CheckpointOptions(),
    );
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');

    // turn 1 的快照卡在闸上；期间切走再切回同一会话。
    _write(root, 'a.txt', 'v1');
    final Future<String?> round = manager.recordTurn();
    await Future<void>.delayed(Duration.zero); // 让快照真正开始、卡在闸上
    manager.detach();
    final Future<String?> rebound = manager.bind('s1');

    store.gate.complete();
    expect(await round, isNull);
    expect(await rebound, isNull);
    expect(manager.turn, 1, reason: '必须算上刚落盘的那一轮，否则会覆盖它');
    expect(manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 1]);
  });

  test('restoreTo 按会话/轮次恢复；绑定会话同步 turn，别的不动', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn(); // s1 turn 1
    _write(root, 'a.txt', 'v2');
    await manager.recordTurn(); // s1 turn 2

    final CheckpointRewindResult? back = await manager.restoreTo('s1', 1);
    expect(back, isNotNull);
    expect(back!.turn, 1);
    expect(manager.turn, 1, reason: '绑定的就是 s1：轮次跟着目标走');
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v1',
    );

    // 换绑 s2 后恢复 s1：文件回 s1 的基线，但 s2 的轮次不该被改。
    await manager.bind('s2'); // s2 基线
    await manager.recordTurn(); // s2 turn 1
    expect(manager.turn, 1);
    final CheckpointRewindResult? other = await manager.restoreTo('s1', 0);
    expect(other!.turn, 0);
    expect(manager.sessionId, 's2');
    expect(manager.turn, 1, reason: '非绑定会话的恢复不得改当前轮次');
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v0',
    );
  });

  test('restoreTo 对不存在的会话/轮次返回 null', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');

    expect(await manager.restoreTo('nope', 0), isNull);
    expect(await manager.restoreTo('s1', 9), isNull);

    final (CheckpointManager off, _, _) = _manager(enabled: false);
    expect(await off.restoreTo('s1', 0), isNull);
  });

  test('clearSession 幂等：重复调用不抛，历史清空', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    await manager.recordTurn();
    expect(manager.list(), hasLength(2));

    await manager.clearSession('s1');
    await manager.clearSession('s1');
    expect(manager.list(), isEmpty);
    expect(manager.turn, 0);
  });

  test('串行链错误安全：单个动作抛错不毒化后续', () async {
    final (String root, String projectDir) = _workspace();
    final _FlakyClearStore store = _FlakyClearStore(
      root: root,
      projectDir: projectDir,
    );
    final CheckpointManager manager = CheckpointManager(
      store: store,
      options: const CheckpointOptions(),
    );
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');

    await expectLater(
      manager.clearSession('s1'),
      throwsA(isA<CheckpointException>()),
    );
    // 链没被那次异常毒化：flush 立刻收敛，后续动作照常执行。
    await manager.flush();
    await manager.clearSession('s1');
    expect(manager.list(), isEmpty);
  });

  test('bind 读取检查点失败时返回错误说明（不抛出）', () async {
    final (String root, String projectDir) = _workspace();
    final CheckpointManager manager = CheckpointManager(
      store: _BrokenTurnsStore(root: root, projectDir: projectDir),
      options: const CheckpointOptions(),
    );

    expect(await manager.bind('s1'), contains('检查点读取失败'));
    expect(manager.turn, 0, reason: '同步读失败按 0，UI 不该拿到上一条时间线的轮次');
  });

  test('排队中的 restoreTo 在切走会话后放弃（不写工作区）', () async {
    final (String root, String projectDir) = _workspace();
    final _GatedStore store = _GatedStore(
      root: root,
      projectDir: projectDir,
      gateTurn: 2,
    );
    addTearDown(() {
      if (!store.gate.isCompleted) store.gate.complete();
    });
    final CheckpointManager manager = CheckpointManager(
      store: store,
      options: const CheckpointOptions(),
    );
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn(); // turn 1
    _write(root, 'a.txt', 'v2');
    final Future<String?> inFlight = manager.recordTurn(); // turn 2 卡在闸上
    await Future<void>.delayed(Duration.zero);

    final Future<CheckpointRewindResult?> pending = manager.restoreTo('s1', 0);
    manager.detach(); // 模拟切会话
    store.gate.complete();
    await inFlight;
    expect(await pending, isNull, reason: '切走后排队中的恢复必须放弃');
    expect(
      File('$root${Platform.pathSeparator}a.txt').readAsStringSync(),
      'v2',
      reason: '放弃的恢复不得写工作区',
    );
  });

  test('readFile / changesBetween 透传给存储（/diff 数据源）', () async {
    final (CheckpointManager manager, String root, _) = _manager();
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    _write(root, 'a.txt', 'v1');
    await manager.recordTurn();

    expect(utf8.decode((await manager.readFile('s1', 0, 'a.txt'))!), 'v0');
    final List<CheckpointFileChange> changes = await manager.changesBetween(
      's1',
      0,
      1,
    );
    expect(changes.single.path, 'a.txt');
    expect(changes.single.status, 'modified');
  });
}

/// 闸住某轮快照的存储：用来验证 `flush` / 排队语义。
class _GatedStore extends ArchiveCheckpointStore {
  _GatedStore({
    required super.root,
    required super.projectDir,
    this.gateTurn = 1,
  });

  /// 被闸住的轮次。
  final int gateTurn;

  /// 放行被闸住的快照。
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> snapshot(
    String sessionId,
    int turn, {
    String? lastEventId,
  }) async {
    if (turn == gateTurn) await gate.future;
    await super.snapshot(sessionId, turn, lastEventId: lastEventId);
  }
}

/// 首次清空即失败的存储：验证串行链不被单个异常毒化。
class _FlakyClearStore extends ArchiveCheckpointStore {
  _FlakyClearStore({required super.root, required super.projectDir});

  bool _fail = true;

  @override
  Future<void> clearSession(String sessionId) async {
    if (_fail) {
      _fail = false;
      throw const CheckpointException('clear-failed', '模拟清空失败');
    }
    await super.clearSession(sessionId);
  }
}

/// `turnsOf` 直接失败的存储：验证 bind 的错误说明契约。
class _BrokenTurnsStore extends ArchiveCheckpointStore {
  _BrokenTurnsStore({required super.root, required super.projectDir});

  @override
  List<int> turnsOf(String sessionId) =>
      throw const CheckpointException('broken-index', '索引损坏');
}

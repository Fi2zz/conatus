/// RevertService：撤销 / 重做的文件恢复、对话分叉与 prompt 暂存。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:conatus_checkpoint/revert.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 建临时「工作区 + 项目数据目录」。
(String, String) _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('conatus-revert');
  addTearDown(() => dir.deleteSync(recursive: true));
  final String projectDir = '${dir.path}${Platform.pathSeparator}.conatus';
  Directory(projectDir).createSync();
  return (dir.path, projectDir);
}

void _write(String root, String rel, String content) {
  final File file = File('$root${Platform.pathSeparator}$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root${Platform.pathSeparator}$rel').readAsStringSync();

/// 按包内选项造检查点管理器（缺省策略即可，本测试不涉及产品目录）。
CheckpointManager _checkpointManager(
  String root,
  String projectDir, {
  bool enabled = true,
  int keep = 5,
}) {
  final CheckpointOptions options = CheckpointOptions(
    enabled: enabled,
    keep: keep,
  );
  return CheckpointManager(
    store: ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
      policy: options.policy,
    ),
    options: options,
  );
}

/// 一次用例的装配：两轮会话 + 两轮检查点。
class _Env {
  _Env({
    required this.root,
    required this.manager,
    required this.sessions,
    required this.session,
    required this.service,
  });

  final String root;
  final CheckpointManager manager;
  final SessionStore sessions;
  final Session session;
  final RevertService service;
}

/// 摆两轮：a.txt v0 → v1（第一轮）→ v2（第二轮）。
///
/// [touchesFiles] 为 false 时两轮都不改文件（用于制造「撤销区间内没有文件变化」
/// 却存在外部改动的情形）。
Future<_Env> _twoTurns({
  bool enabled = true,
  int keep = 5,
  bool touchesFiles = true,
}) async {
  final (String root, String projectDir) = _workspace();
  final CheckpointManager manager = _checkpointManager(
    root,
    projectDir,
    enabled: enabled,
    keep: keep,
  );
  final SessionStore sessions = SessionStore();
  final Session session = sessions.create(id: 's1');
  _write(root, 'a.txt', 'v0');
  await manager.bind('s1');
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '第一轮'});
  if (touchesFiles) _write(root, 'a.txt', 'v1');
  await manager.recordTurn(lastEventId: session.lastEventId);
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '第二轮'});
  if (touchesFiles) _write(root, 'a.txt', 'v2');
  await manager.recordTurn(lastEventId: session.lastEventId);
  return _Env(
    root: root,
    manager: manager,
    sessions: sessions,
    session: session,
    service: RevertService(checkpoint: manager, sessions: sessions),
  );
}

List<String> _prompts(Session session) => <String>[
      for (final SessionEvent event in session.events)
        if (event.type == kUserMessageEvent) '${(event.data as Map)['text']}',
    ];

void main() {
  test('undo 恢复文件、分叉对话并暂存最新 prompt', () async {
    final _Env env = await _twoTurns();

    final UndoResult result = await env.service.undo(env.session, 1);

    expect(result.stage.toTurn, 1);
    expect(result.stage.fromTurn, 2);
    expect(result.stage.originalSessionId, 's1');
    expect(result.stage.prompt, contains('第二轮'));
    expect(result.restore.restored, greaterThan(0));
    expect(_read(env.root, 'a.txt'), 'v1');

    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(fork.id, isNot('s1'));
    expect(_prompts(fork), <String>['第一轮'], reason: '被撤回的那轮 prompt 不在新会话里');
  });

  test('redo 恢复撤销前的文件（回到 fromTurn）', () async {
    final _Env env = await _twoTurns();
    final UndoResult undone = await env.service.undo(env.session, 1);

    final RedoResult redone = await env.service.redo(undone.stage);

    expect(redone.restored, isTrue);
    expect(_read(env.root, 'a.txt'), 'v2');
  });

  test('checkpoint 关闭：只分叉对话，不动文件', () async {
    final _Env env = await _twoTurns(enabled: false);

    final UndoResult result = await env.service.undo(env.session, 1);

    expect(result.restore.restored, 0);
    expect(result.restore.deleted, 0);
    expect(_read(env.root, 'a.txt'), 'v2', reason: '关闭检查点时不碰工作区');
    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(_prompts(fork), <String>['第一轮']);
    expect(result.stage.prompt, contains('第二轮'));

    // redo 无从恢复文件：只报告 restored:false，切回原会话由控制器做。
    final RedoResult redone = await env.service.redo(result.stage);
    expect(redone.restored, isFalse);
    expect(_read(env.root, 'a.txt'), 'v2');
  });

  test('checkpoint 关闭且没有用户消息：报错且不建会话', () async {
    final (String root, String projectDir) = _workspace();
    final CheckpointManager manager = _checkpointManager(
      root,
      projectDir,
      enabled: false,
    );
    final SessionStore sessions = SessionStore();
    final Session session = sessions.create(id: 's1');
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    final RevertService service = RevertService(
      checkpoint: manager,
      sessions: sessions,
    );

    await expectLater(
      service.undo(session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('没有可撤销'),
        ),
      ),
    );
    expect(sessions.length, 1, reason: '无历史时不建新会话');
    expect(_read(root, 'a.txt'), 'v0');
  });

  test('撤销区间无文件变化也确认：外部改动不被静默覆盖', () async {
    final _Env env = await _twoTurns(touchesFiles: false);
    _write(env.root, 'a.txt', 'external');
    final List<String> asked = <String>[];
    final RevertService service = RevertService(
      checkpoint: env.manager,
      sessions: env.sessions,
      confirm: (String message) async {
        asked.add(message);
        return false;
      },
    );

    await expectLater(
      service.undo(env.session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('已取消'),
        ),
      ),
    );

    expect(asked, hasLength(1), reason: '没有快照差异也必须问一次');
    expect(asked.single, contains('尚未快照的外部改动'));
    expect(_read(env.root, 'a.txt'), 'external');
  });

  test('确认通过后快照状态覆盖外部改动', () async {
    final _Env env = await _twoTurns(touchesFiles: false);
    _write(env.root, 'a.txt', 'external');
    final RevertService service = RevertService(
      checkpoint: env.manager,
      sessions: env.sessions,
      confirm: (String _) async => true,
    );

    final UndoResult result = await service.undo(env.session, 1);

    expect(result.stage.toTurn, 1);
    expect(_read(env.root, 'a.txt'), 'v0', reason: 'turn 1 快照里是 v0');
  });

  test('没有可撤销的轮次：报错且不改会话与文件', () async {
    final (String root, String projectDir) = _workspace();
    final CheckpointManager manager = _checkpointManager(root, projectDir);
    final SessionStore sessions = SessionStore();
    final Session session = sessions.create(id: 's1');
    _write(root, 'a.txt', 'v0');
    await manager.bind('s1');
    final RevertService service = RevertService(
      checkpoint: manager,
      sessions: sessions,
    );

    await expectLater(
      service.undo(session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('没有可撤销'),
        ),
      ),
    );
    expect(sessions.length, 1, reason: '失败时不新建会话');
    expect(_read(root, 'a.txt'), 'v0');
  });

  test('目标轮次已被裁剪：报错且不动文件', () async {
    final _Env env = await _twoTurns(keep: 2);
    expect(env.manager.list().map((CheckpointInfo i) => i.turn), <int>[0, 2]);

    await expectLater(
      env.service.undo(env.session, 1),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('找不到'),
        ),
      ),
    );
    expect(_read(env.root, 'a.txt'), 'v2');
    expect(env.manager.sessionId, 's1');
  });

  test('undo 多轮：回填最近一条 prompt，对话回到更早切点', () async {
    final _Env env = await _twoTurns();

    final UndoResult result = await env.service.undo(env.session, 2);

    expect(result.stage.toTurn, 0);
    expect(result.stage.prompt, contains('第二轮'), reason: '回填最新一条被撤回的 prompt');
    expect(_read(env.root, 'a.txt'), 'v0');
    final Session fork = env.sessions.get(result.stage.forkSessionId)!;
    expect(_prompts(fork), isEmpty);
  });

  test('undo N 超过轮次：报错且不改状态（checkpoint 开启）', () async {
    final _Env env = await _twoTurns();

    await expectLater(
      env.service.undo(env.session, 3),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('没有可撤销的 3 轮'),
        ),
      ),
    );

    expect(env.manager.turn, 2);
    expect(env.manager.sessionId, 's1');
    expect(_read(env.root, 'a.txt'), 'v2');
    expect(env.sessions.length, 1, reason: '失败时不新建会话');
  });

  test('undo N 超过 prompt 数：报错且不切会话（checkpoint 关闭）', () async {
    final _Env env = await _twoTurns(enabled: false);

    await expectLater(
      env.service.undo(env.session, 3),
      throwsA(
        isA<RevertException>().having(
          (RevertException e) => e.message,
          'message',
          contains('只有 2 条用户消息'),
        ),
      ),
    );

    expect(env.sessions.length, 1);
    expect(_read(env.root, 'a.txt'), 'v2');
  });
}

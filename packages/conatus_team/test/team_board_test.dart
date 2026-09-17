import 'package:conatus_team/conatus_team.dart';
import 'package:test/test.dart';

/// 断言抛出 [TeamException] 且 code 为 [expected]。
Matcher _throwsTeamError(String expected) => throwsA(
    isA<TeamException>().having((TeamException e) => e.code, 'code', expected));

void main() {
  group('TeamBoard — create / get / claimableBy', () {
    test('create 生成 pending 任务，version 0', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: '审查代码');
      expect(t.status, TeamTaskStatus.pending);
      expect(t.version, 0);
      expect(t.dependsOn, isEmpty);
      expect(board.all, <TeamTask>[t]);
      expect(board.get(t.id), same(t));
      expect(board.get('ghost'), isNull);
    });

    test('claimableBy 返回 pending + 依赖全 done + assignee 兼容', () {
      final TeamBoard board = TeamBoard();
      final TeamTask a = board.create(description: 'A');
      final TeamTask b =
          board.create(description: 'B', dependsOn: <String>[a.id]);
      final TeamTask c = board.create(description: 'C', assigneeId: 'm1');
      expect(b.dependsOn, <String>[a.id]);
      expect(board.claimableBy('m1').map((TeamTask t) => t.id),
          <String>[a.id, c.id]);
      expect(board.claimableBy('m2').map((TeamTask t) => t.id), <String>[a.id]);
    });
  });

  group('TeamBoard — claim / complete / release', () {
    test('claim 标记 claimed 并锁定 assignee', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      final TeamTask claimed = board.claim(t.id, 'm1');
      expect(claimed.status, TeamTaskStatus.claimed);
      expect(claimed.assigneeId, 'm1');
      expect(claimed.version, 1);
    });

    test('complete 标记 done 并存结果', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      board.claim(t.id, 'm1');
      final TeamTask done = board.complete(t.id, 'm1', result: '结论 X');
      expect(done.status, TeamTaskStatus.done);
      expect(done.result, '结论 X');
      expect(done.version, 2);
    });

    test('release 回到 pending，清空 assignee', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      board.claim(t.id, 'm1');
      final TeamTask released = board.release(t.id, 'm1');
      expect(released.status, TeamTaskStatus.pending);
      expect(released.assigneeId, isNull);
      expect(released.version, 2);
    });

    test('依赖未完成时 claim 抛 deps-not-met', () {
      final TeamBoard board = TeamBoard();
      final TeamTask a = board.create(description: 'A');
      board.create(description: 'B', dependsOn: <String>[a.id]);
      expect(() => board.claim('team-task-2', 'm1'),
          _throwsTeamError('deps-not-met'));
    });

    test('CAS 版本不匹配抛 version-mismatch', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      expect(() => board.claim(t.id, 'm1', version: 99),
          _throwsTeamError('version-mismatch'));
    });

    test('assignee 不匹配抛 assignee-mismatch', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      board.claim(t.id, 'm1');
      expect(() => board.complete(t.id, 'm2'),
          _throwsTeamError('assignee-mismatch'));
    });

    test('终态任务不可再 claim / complete / release', () {
      final TeamBoard board = TeamBoard();
      final TeamTask t = board.create(description: 'A');
      board.claim(t.id, 'm1');
      board.complete(t.id, 'm1');
      expect(() => board.claim(t.id, 'm1'), _throwsTeamError('bad-state'));
      expect(() => board.complete(t.id, 'm1'), _throwsTeamError('bad-state'));
      expect(() => board.release(t.id, 'm1'), _throwsTeamError('bad-state'));
    });

    test('不存在任务抛 not-found', () {
      final TeamBoard board = TeamBoard();
      expect(() => board.claim('ghost', 'm1'), _throwsTeamError('not-found'));
    });
  });
}

import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

DocPatch patch(String id, List<PatchOp> ops, {String? supersedes}) => DocPatch(
      id: id,
      author: PatchAuthor.ai,
      ops: ops,
      supersedes: supersedes,
    );

void main() {
  group('PatchLog', () {
    test('只追加：id 重复抛 ArgumentError', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]));
      expect(() => log.append(patch('p1', const <PatchOp>[])),
          throwsArgumentError);
      expect(log.length, 1);
    });

    test('supersede：新补丁生效，旧补丁退出生效集', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]))
        ..append(patch('p2', const <PatchOp>[], supersedes: 'p1'));
      expect(log.effective().map((DocPatch p) => p.id), <String>['p2']);
      // 序列本身不改写：历史里两条都在
      expect(log.patches, hasLength(2));
    });

    test('supersede 不追溯：upto 早于 supersede 补丁时旧补丁仍生效', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]))
        ..append(patch('p2', const <PatchOp>[], supersedes: 'p1'));
      expect(log.effective(upto: 1).map((DocPatch p) => p.id),
          <String>['p1']);
    });

    test('作废的 supersede 补丁不再压制旧补丁', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]))
        ..append(patch('p2', const <PatchOp>[], supersedes: 'p1'))
        ..voidPatch('p2');
      expect(log.effective().map((DocPatch p) => p.id), <String>['p1']);
    });

    test('truncateAfter 作废后续补丁，历史保留', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]))
        ..append(patch('p2', const <PatchOp>[]))
        ..truncateAfter(0);
      expect(log.voided('p2'), isTrue);
      expect(log.effective().map((DocPatch p) => p.id), <String>['p1']);
      expect(log.patches, hasLength(2));
    });

    test('forkAt 复制前缀与作废标记，旧线不受影响', () {
      final PatchLog log = PatchLog()
        ..append(patch('p1', const <PatchOp>[]))
        ..append(patch('p2', const <PatchOp>[]))
        ..truncateAfter(0);
      final PatchLog branch = log.forkAt(1);
      expect(branch.length, 1);
      log.append(patch('p3', const <PatchOp>[]));
      expect(branch.length, 1);
      expect(log.length, 3);
    });

    test('批注只追加进 annotations', () {
      final PatchLog log = PatchLog()
        ..annotate(const DocAnnotation(
          id: 'a1',
          blockId: 'b1',
          author: PatchAuthor.human,
          text: '这里想表达什么？',
        ));
      expect(log.annotations, hasLength(1));
    });
  });
}

import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

void main() {
  group('splitPending（编辑即裁剪）', () {
    const DocPatch pending = DocPatch(
      id: 'ai-1',
      author: PatchAuthor.ai,
      ops: <PatchOp>[
        InsertBlockOp(blockId: 'b1', text: 'AI 写的第一段'),
        InsertBlockOp(blockId: 'b2', text: 'AI 写的第二段', afterId: 'b1'),
      ],
    );

    test('人改的块脱离 AI 补丁，余下保留', () {
      final PendingSplit split = splitPending(
        pending,
        const <PatchOp>[ReplaceBlockOp(blockId: 'b2', text: '人改的第二段')],
        'h-1',
      );
      expect(split.aiRemainder!.ops, hasLength(1));
      expect(split.aiRemainder!.ops.single.blockId, 'b1');
      expect(split.humanPatch.author, PatchAuthor.human);
      // 人改的是 AI 待定新建的块：人补丁直接携带建块 op，不自锚失锚
      expect(split.humanPatch.ops.single, isA<InsertBlockOp>());
    });

    test('人改完全部块时 AI 补丁无需再接受', () {
      final PendingSplit split = splitPending(
        pending,
        const <PatchOp>[
          ReplaceBlockOp(blockId: 'b1', text: '改一'),
          ReplaceBlockOp(blockId: 'b2', text: '改二'),
        ],
        'h-1',
      );
      expect(split.aiRemainder, isNull);
    });

    test('拆分后提交：AI 余下块与人的修改都生效', () {
      final PendingSplit split = splitPending(
        pending,
        const <PatchOp>[ReplaceBlockOp(blockId: 'b2', text: '人改的第二段')],
        'h-1',
      );
      final PatchLog log = PatchLog()
        ..append(split.aiRemainder!)
        ..append(split.humanPatch);
      final DocumentState state = foldPatches(log.effective());
      expect(state.text, 'AI 写的第一段\n人改的第二段');
    });

    test('落点锚在被带走块上的余下 op 传递改锚', () {
      // 人带走 b2 后，AI 补丁里 afterId=b2 的 b3 应改锚到 b2 的落点 b1
      final PendingSplit split = splitPending(
        const DocPatch(
          id: 'ai-2',
          author: PatchAuthor.ai,
          ops: <PatchOp>[
            InsertBlockOp(blockId: 'b1', text: '一'),
            InsertBlockOp(blockId: 'b2', text: '二', afterId: 'b1'),
            InsertBlockOp(blockId: 'b3', text: '三', afterId: 'b2'),
          ],
        ),
        const <PatchOp>[ReplaceBlockOp(blockId: 'b2', text: '二人')],
        'h-2',
      );
      final PatchLog log = PatchLog()
        ..append(split.aiRemainder!)
        ..append(split.humanPatch);
      final DocumentState state = foldPatches(log.effective());
      expect(
          state.blocks.map((DocBlock b) => b.id), <String>['b1', 'b2', 'b3']);
      expect(state.text, '一\n二人\n三');
    });
  });
}

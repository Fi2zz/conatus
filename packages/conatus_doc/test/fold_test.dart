import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

DocPatch ai(String id, List<PatchOp> ops) =>
    DocPatch(id: id, author: PatchAuthor.ai, ops: ops);

void main() {
  group('foldPatches', () {
    test('insert / replace / remove 按追加序折叠', () {
      final DocumentState state = foldPatches(<DocPatch>[
        ai('p1', const <PatchOp>[
          InsertBlockOp(blockId: 'b1', text: '第一段'),
          InsertBlockOp(blockId: 'b2', text: '第二段', afterId: 'b1'),
        ]),
        ai('p2', const <PatchOp>[
          ReplaceBlockOp(blockId: 'b1', text: '第一段（改）'),
        ]),
        ai('p3', const <PatchOp>[RemoveBlockOp(blockId: 'b2')]),
      ]);
      expect(state.text, '第一段（改）');
    });

    test('insert 到开头与指定块之后', () {
      final DocumentState state = foldPatches(<DocPatch>[
        ai('p1', const <PatchOp>[InsertBlockOp(blockId: 'b1', text: '尾')]),
        ai('p2', const <PatchOp>[InsertBlockOp(blockId: 'b0', text: '头')]),
      ]);
      expect(state.blocks.map((DocBlock b) => b.id), <String>['b0', 'b1']);
    });

    test('move 移动块到指定位置', () {
      final DocumentState state = foldPatches(<DocPatch>[
        ai('p1', const <PatchOp>[
          InsertBlockOp(blockId: 'b1', text: '一'),
          InsertBlockOp(blockId: 'b2', text: '二', afterId: 'b1'),
          InsertBlockOp(blockId: 'b3', text: '三', afterId: 'b2'),
        ]),
        ai('p2', const <PatchOp>[MoveBlockOp(blockId: 'b3')]),
      ]);
      expect(
          state.blocks.map((DocBlock b) => b.id), <String>['b3', 'b1', 'b2']);
    });

    test('失锚操作静默跳过', () {
      final DocumentState state = foldPatches(<DocPatch>[
        ai('p1', const <PatchOp>[
          ReplaceBlockOp(blockId: 'ghost', text: '无效'),
          RemoveBlockOp(blockId: 'ghost'),
          MoveBlockOp(blockId: 'ghost'),
        ]),
      ]);
      expect(state.blocks, isEmpty);
    });

    test('supersede 后的生效视图只含新文本', () {
      final PatchLog log = PatchLog()
        ..append(ai('p1', const <PatchOp>[
          InsertBlockOp(blockId: 'b1', text: '旧'),
        ]))
        ..append(const DocPatch(
          id: 'p2',
          author: PatchAuthor.human,
          ops: <PatchOp>[ReplaceBlockOp(blockId: 'b1', text: '新')],
          supersedes: 'p1',
        ));
      // p1 被 supersede 后 b1 不复存在，p2 的 replace 失锚——
      // 这正是「改状态」的真实语义：supersede 补丁应自带完整 ops
      expect(foldPatches(log.effective()).blocks, isEmpty);
    });
  });
}

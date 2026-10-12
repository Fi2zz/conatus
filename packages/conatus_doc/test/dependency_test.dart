import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyIndex', () {
    final List<DocPatch> patches = <DocPatch>[
      const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '一')],
      ),
      const DocPatch(
        id: 'p2',
        author: PatchAuthor.ai,
        ops: <PatchOp>[ReplaceBlockOp(blockId: 'b1', text: '一改')],
      ),
      const DocPatch(
        id: 'p3',
        author: PatchAuthor.human,
        ops: <PatchOp>[ReplaceBlockOp(blockId: 'b1', text: '再改')],
      ),
    ];

    test('隐式依赖：触及他补丁创建的块即依赖', () {
      final DependencyIndex index = DependencyIndex.fromPatches(patches);
      expect(index.depsOf('p2'), <String>{'p1'});
      expect(index.depsOf('p3'), <String>{'p1'});
      expect(index.depsOf('p1'), isEmpty);
    });

    test('显式 deps 与隐式依赖取并集', () {
      final DependencyIndex index = DependencyIndex.fromPatches(<DocPatch>[
        patches[0],
        patches[1].copyWith(deps: <String>{'external'}),
      ]);
      expect(index.depsOf('p2'), <String>{'p1', 'external'});
    });

    test('collectOrphaned 传递闭包', () {
      final DependencyIndex index = DependencyIndex.fromPatches(<DocPatch>[
        patches[0],
        patches[1],
        patches[2].copyWith(deps: <String>{'p2'}),
      ]);
      expect(index.collectOrphaned('p1'), <String>{'p2', 'p3'});
      expect(index.collectOrphaned('p2'), <String>{'p3'});
      expect(index.collectOrphaned('p3'), isEmpty);
    });
  });

  group('floatingAnnotations', () {
    test('锚定块消失的批注被检出', () {
      final PatchLog log = PatchLog()
        ..append(const DocPatch(
          id: 'p1',
          author: PatchAuthor.ai,
          ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '一')],
        ))
        ..annotate(const DocAnnotation(
          id: 'a1',
          blockId: 'b1',
          author: PatchAuthor.human,
          text: '什么意思？',
        ))
        ..annotate(const DocAnnotation(
          id: 'a2',
          blockId: 'ghost',
          author: PatchAuthor.human,
          text: '悬浮',
        ));
      final List<DocAnnotation> floating =
          floatingAnnotations(log.annotations, foldPatches(log.effective()));
      expect(floating.map((DocAnnotation a) => a.id), <String>['a2']);
    });
  });
}

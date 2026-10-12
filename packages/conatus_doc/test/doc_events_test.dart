import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('SessionLog 桥', () {
    test('commit / annotate / discard / truncate 落事件并可重建', () async {
      final SessionLog store = InMemorySessionLog();
      final DocEngine engine = DocEngine(
        PatchLog(),
        sessionLog: store,
        sessionId: 's1',
      );

      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '初稿')],
      ));
      await engine.annotate(const DocAnnotation(
        id: 'a1',
        blockId: 'b1',
        author: PatchAuthor.human,
        text: '这里呢？',
      ));
      await engine.commit(const DocPatch(
        id: 'p2',
        author: PatchAuthor.human,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b2', text: '二', afterId: 'b1')],
      ));
      await engine.discard('p2');
      await engine.truncateAfter(0);

      final PatchLog rebuilt = await rebuildPatchLog(store, 's1');
      expect(rebuilt.length, 2);
      expect(rebuilt.annotations, hasLength(1));
      expect(rebuilt.voided('p2'), isTrue);
      expect(foldPatches(rebuilt.effective()).text, '初稿');
    });

    test('非 doc 事件不影响重建', () async {
      final SessionLog store = InMemorySessionLog();
      await store.append(SessionEvent.create(
        sessionId: 's1',
        type: kUserMessageEvent,
        seq: 0,
        data: '无关事件',
      ));
      final PatchLog rebuilt = await rebuildPatchLog(store, 's1');
      expect(rebuilt.length, 0);
    });

    test('未装配 SessionLog 时为纯内存引擎', () async {
      final DocEngine engine = DocEngine(PatchLog());
      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '内存')],
      ));
      expect(engine.state.text, '内存');
    });

    test('provideDoc 注册服务并可经 ctx.doc 取用', () async {
      final Context ctx = Context.root();
      final DocEngine engine = provideDoc(ctx);
      expect(identical(ctx.doc, engine), isTrue);
      ctx.dispose();
    });

    test('provideDoc 缺省桥接上下文中的 sessionLog 服务', () async {
      final Context ctx = Context.root();
      final SessionLog store = provideSessionLog(ctx);
      final DocEngine engine = provideDoc(ctx, sessionId: 's1');
      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '桥接')],
      ));
      final PatchLog rebuilt = await rebuildPatchLog(store, 's1');
      expect(rebuilt.length, 1);
      ctx.dispose();
    });
  });
}

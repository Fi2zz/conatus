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

    test('forkAt 做会话层 fork：切点事件之前的历史进新会话', () async {
      final SessionLog store = InMemorySessionLog();
      final DocEngine engine = DocEngine(
        PatchLog(),
        sessionLog: store,
        sessionId: 's1',
      );
      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '一')],
      ));
      await engine.commit(const DocPatch(
        id: 'p2',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b2', text: '二', afterId: 'b1')],
      ));

      final DocEngine branch = await engine.forkAt(1, newSessionId: 's2');
      await branch.commit(const DocPatch(
        id: 'p3',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b3', text: '支线', afterId: 'b1')],
      ));

      // 新会话只含切点前历史 + 支线补丁；源会话不受影响
      final PatchLog forked = await rebuildPatchLog(store, 's2');
      expect(
          forked.effective().map((DocPatch p) => p.id), <String>['p1', 'p3']);
      final PatchLog origin = await rebuildPatchLog(store, 's1');
      expect(origin.length, 2);
    });

    test('rebuildDocEngine 重建后 fork 切点映射仍可用', () async {
      final SessionLog store = InMemorySessionLog();
      final DocEngine engine = DocEngine(
        PatchLog(),
        sessionLog: store,
        sessionId: 's1',
      );
      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '一')],
      ));
      await engine.commit(const DocPatch(
        id: 'p2',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b2', text: '二', afterId: 'b1')],
      ));

      final DocEngine rebuilt = await rebuildDocEngine(store, 's1');
      final DocEngine branch = await rebuilt.forkAt(1, newSessionId: 's2');
      expect(foldPatches(branch.log.effective()).text, '一');
      expect(await store.list(), contains('s2'));
    });

    test('纯内存引擎的 forkAt 退化为文档层分叉', () async {
      final DocEngine engine = DocEngine(PatchLog());
      await engine.commit(const DocPatch(
        id: 'p1',
        author: PatchAuthor.ai,
        ops: <PatchOp>[InsertBlockOp(blockId: 'b1', text: '一')],
      ));
      final DocEngine branch = await engine.forkAt(1);
      expect(branch.log.length, 1);
    });
  });
}

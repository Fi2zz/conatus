// 人机双写离线 Demo：无需任何 API Key。
//
// 用 conatus_doc 补丁引擎演示一轮完整协同：AI 产出待定补丁 → 人直接改
// （按块收缩）→ 接受 → 锚点批注 → supersede → 游标预览 / 分叉 →
// 失锚级联标记。
//
// 运行：
//   dart run example/cowrite_demo.dart

import 'package:conatus/conatus.dart';

Future<void> main() async {
  final Context app = Context.root(name: 'cowrite-demo');
  final DocEngine doc = provideDoc(app);

  _section('1. AI 流式产出 → 待定补丁');
  const DocPatch aiDraft = DocPatch(
    id: 'ai-1',
    author: PatchAuthor.ai,
    ops: <PatchOp>[
      InsertBlockOp(blockId: 'b1', text: '从前有座山。'),
      InsertBlockOp(blockId: 'b2', text: '山里有座庙。', afterId: 'b1'),
      InsertBlockOp(blockId: 'b3', text: '庙里有个老和尚。', afterId: 'b2'),
    ],
  );
  print('待定补丁 ai-1：3 个块（尚未进故事）');

  _section('2. 人直接改 AI 的待定产出（编辑即裁剪）');
  final PendingSplit split = splitPending(aiDraft, const <PatchOp>[
    ReplaceBlockOp(blockId: 'b2', text: '山里有座破庙。'),
  ], 'h-1');
  print(
    '人改了 b2 → AI 补丁收缩为 ${split.aiRemainder!.ops.length} 个块，'
    '人的改动独立成补丁 h-1',
  );
  await doc.commit(split.aiRemainder!);
  await doc.commit(split.humanPatch);
  _printState(doc);

  _section('3. 锚点批注（带位置的提问）');
  await doc.annotate(
    const DocAnnotation(
      id: 'a1',
      blockId: 'b3',
      author: PatchAuthor.human,
      text: '「老和尚」要不要换成「小和尚」？',
    ),
  );
  print('批注 a1 锚在 b3 上');

  _section('4. AI 接受建议 → supersede 自己的上一补丁');
  await doc.commit(
    const DocPatch(
      id: 'ai-2',
      author: PatchAuthor.ai,
      ops: <PatchOp>[ReplaceBlockOp(blockId: 'b3', text: '庙里有个小和尚。')],
    ),
  );
  _printState(doc);

  _section('5. traveling：预览过去 / 分叉支线');
  print('预览前 2 个补丁时刻：「${doc.previewAt(2).text}」');
  final DocEngine branch = doc.forkAt(2);
  await branch.commit(
    const DocPatch(
      id: 'ai-branch',
      author: PatchAuthor.ai,
      ops: <PatchOp>[
        InsertBlockOp(blockId: 'b4', text: '支线：庙里空无一人。', afterId: 'b2'),
      ],
    ),
  );
  print('支线：${branch.state.text}');
  print('主线：${doc.state.text}（旧线保留）');

  _section('6. 依赖图与级联失锚');
  final DependencyIndex index = DependencyIndex.fromPatches(
    doc.log.effective(),
  );
  print('ai-2 依赖：${index.depsOf('ai-2')}（隐式：触及 ai-1 创建的 b3）');
  print('若作废 ai-1，失锚补丁：${index.collectOrphaned('ai-1')}');

  app.dispose();
  print(
    '\n故事完整保留在补丁序列里：共 ${doc.log.length} 个补丁、'
    '${doc.log.annotations.length} 条批注，序列只追加、可随时 replay。',
  );
}

void _section(String title) => print('\n== $title ==');

void _printState(DocEngine doc) {
  print('当前文档：');
  for (final DocBlock block in doc.state.blocks) {
    print('  [${block.id}] ${block.text}');
  }
}

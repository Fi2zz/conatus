# conatus_doc（实验性）

人机双写范式的**文档补丁引擎**：故事层的数据内核。设计文档见仓库根
`docs/人机双写范式设计文档.md`。

> 实验性包：API 可能破坏性变更，生产慎用。

## 核心模型

补丁是一等公民，状态是派生物：

```
state(t) = fold(截至 t 生效的补丁集)
```

- `DocBlock`：稳定块 id 的文档块；补丁与批注只锚块 id，不锚偏移量。
- `DocPatch`：一组 `PatchOp`（insert / replace / remove / move）+ 作者
  （`PatchAuthor.human` / `ai`）+ 可逆性（`PatchReversibility`）+ 依赖集
  （`deps`）+ supersede 指针。
- `PatchLog`：只追加序列。「修改补丁」= 追加 supersede 它的新补丁；「截断 /
  丢弃」= 作废标记。序列永不改写，生效视图由 `effective({upto})` 给出——
  supersede 不追溯：supersede 补丁在 `upto` 之后时，旧补丁在该刻仍生效。
- `foldPatches`：生效补丁集 → `DocumentState`；失锚操作静默跳过。
- 游标三操作：`previewAt`（只读预览）/ `forkLog`（分叉，旧线保留）/
  `truncateLog`（截断，作废后续补丁）。
- `splitPending`：待定补丁按块收缩——人直接改 AI 待定产出时，人碰过的块
  脱离 AI 补丁，余下部分仍可整体接受 / 拒绝。
- `DocAnnotation`：锚在块上的批注（带位置的提问）；`floatingAnnotations`
  检出锚点块已消失的悬浮批注。
- `DependencyIndex`：显式 deps ∪ 隐式块依赖（触及他补丁创建的块即依赖）；
  `collectOrphaned` 级联找出失锚补丁，交人处置，不自动猜。
- `OpStreamCompiler`：token 流 → op 流编译管道——模型在 ops 围栏块内
  输出 `PatchOp` JSON 数组，逐段喂入、闭合即产出（`compileOpsBlock`
  处理完整文本）。

## 用法

```dart
import 'package:conatus_doc/conatus_doc.dart';

final engine = DocEngine(PatchLog());

// AI 流式产出 → 待定补丁；人接受后提交
await engine.commit(const DocPatch(
  id: 'p1',
  author: PatchAuthor.ai,
  ops: [InsertBlockOp(blockId: 'b1', text: '初稿')],
));

print(engine.state.text); // 初稿

// 人直接改 → 补丁 supersede
await engine.commit(const DocPatch(
  id: 'p2',
  author: PatchAuthor.human,
  ops: [ReplaceBlockOp(blockId: 'b1', text: '改后')],
  supersedes: 'p1',
));

// traveling：预览 / 分叉 / 截断
final before = engine.previewAt(1);   // 只看 p1 生效的时刻
final branch = engine.forkAt(1);      // 从该刻开支线
```

装配进上下文（`provideDoc`）后，提交 / 作废 / 截断 / 批注会同步落
`doc/patch`、`doc/void`、`doc/truncate`、`doc/annotation` 事件到
`SessionLog`（缺省取 `'sessionLog'` 服务）；`forkAt` 同时做会话层 fork
（切点 = 切线处补丁落定的事件 id，分支会话只含切点前历史），
`rebuildDocEngine` 可从事件流重建引擎（含切点映射）。

## 与设计文档的对应

| 设计文档 | 本包 |
|---|---|
| §2.1 补丁一等公民 / fold | `PatchLog` + `foldPatches` |
| §2.2 四种补丁操作 | `commit` / `discard` / `splitPending` / `annotate` |
| §4.4 supersede 只追加 | `PatchLog.effective` 生效规则 |
| §4.5 依赖图与失锚 | `DependencyIndex` / `floatingAnnotations` |
| §4.6 游标 | `previewAt` / `forkLog` / `truncateLog` |
| §2.4 人的编辑是一等事件 | `doc/patch` 事件（作者字段区分人机） |

不在本包：检查点（fold 重建通路在 compaction）、CRDT 并发、
prompt-as-patch。

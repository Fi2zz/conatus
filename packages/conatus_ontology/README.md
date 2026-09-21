# conatus_ontology

conatus 的自进化本体层：建立一层显式、版本化的语义本体（Term / Mapping /
Constraint / Evidence），让 Agent 查询而不是猜测，并从执行轨迹中持续进化
（EvoOntology，arXiv:2609.15779 的适配实现）。

## 设计要点

- **主动访问**：只检索当前步骤需要的语义（`browse_semantics` / `resolve_semantics`），
  不把整个本体注入上下文；`ontology_manifest` 提供紧凑会话清单。
- **接地构建**：本体对象对照底层数据验证后才能提交，不凭 LLM 想象。
- **局部进化**：只做 TypedEdits（9 种类型化编辑），不全量重写。
- **门控版本**：backbone-conditional 配对评估显示可复现改进 + 人类确认后才发布。
- **人类可回滚**：每个版本经 OntologyStore 存档。

## 用法

```dart
final ontology = provideOntology(ctx);

// 构建初始本体
await ontology.build(sources: <DataSource>[...]);

// 从轨迹进化
final variant = await ontology.evolve(trajectories: <SessionEvent>[...]);
final published = await ontology.publish(variant);

// 运行时查询
final nodes = await ontology.browse(type: 'term', query: '收入');
final resolved = await ontology.resolve('营业收入');
```

## 实验性

本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生破坏性改动。
请勿在生产环境依赖它。

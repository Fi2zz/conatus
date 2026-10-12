# Changelog

## 0.16.0

- 初始版本（实验性）：文档补丁引擎——`DocBlock` / `DocPatch` / `PatchLog`
  （只追加 + supersede 生效 + 作废标记）、`foldPatches`、游标三操作
  （`previewAt` / `forkLog` / `truncateLog`）、`splitPending` 按块收缩、
  `DocAnnotation` 锚点批注、`DependencyIndex` 依赖图与级联失锚、
  `SessionLog` 事件桥（`doc/patch` / `doc/void` / `doc/truncate` /
  `doc/annotation`）与 `provideDoc` 装配。

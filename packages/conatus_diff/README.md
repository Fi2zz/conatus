# conatus_diff

conatus 的**文本差异内核**：统一格式（unified）diff 的生成、解析与应用，
行级 LCS 编辑脚本，全部为**纯函数、零运行时依赖**（仅用 Dart 核心库）。

> ⚠️ **实验性**：API 可能在没有 major 版本变更的情况下破坏性调整，勿在生产依赖。

从 nava（`packages/conatus_code`）的 `/diff` 数据层迁出：hunk 游标解析、
git 扩展头（`diff --git` / `new file mode` / `rename from` / 二进制标记）与
引号路径还原等语义原样保留；文件 IO、工作区 / 检查点数据源、TUI 渲染不在
本包（由消费方完成）。

## 安装

```yaml
dependencies:
  conatus_diff:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: v0.17.0        # 建议 pin 到 tag 或 commit SHA，避免 master 漂移
      path: packages/conatus_diff
```

或经伞包 `import 'package:conatus/conatus.dart';`（随全部模块包一并导出）。

## API 速查

| 成员 | 说明 |
|------|------|
| `buildUnifiedDiff({required oldText, required newText, required path, context = 3, lcsLimit = kMaxDiffLines})` | 生成统一格式 diff；内容相同返回空串 |
| `splitLines(String text)` | 按 `\n` 切行；尾部换行不产生空行 |
| `diffLines(path, before, after, {maxLines = 5000})` | 内存两侧文本的文件级行差异（`null` 侧表示新增 / 删除） |
| `lineDiffOps(a, b, lcsLimit)` | 行级编辑脚本：裁公共前后缀后做 LCS |
| `lineDiffCoarse(a, b, lcsLimit)` | 行差异是否因超限退化为整段删 / 增 |
| `parseUnifiedDiff(String text)` | 解析统一 diff 文本为 `FileDiff` 列表（按出现顺序） |
| `applyDiffFile(String oldText, DiffFile file)` | 倒序应用全部 hunk；上下文失配抛 `PatchContextException` |
| `applyEditText(text, oldString, newString, replaceAll)` | 字面替换语义；不适用时返回 `null` |
| `DiffOpKind` / `DiffOp` / `DiffFile` / `DiffHunk` | 行操作类型、单行操作、文件块、hunk |
| `FileDiff` | 带状态词、增删统计与 `truncated` / `coarse` 标记的 `DiffFile` |
| `DiffScope` | diff 的比较范围（`working` / `turn`） |
| `kMaxDiffLines` | 参与 LCS 的单侧默认行数上限（2000，超过退化为整体替换） |
| `PatchContextException` | patch 上下文与现有内容不匹配 |

## 零依赖

包本体只依赖 Dart 核心库（`dart:convert` 用于 git 八进制转义路径的 UTF-8
解码）。`pubspec.yaml` 的 `dependencies` 为空，可安全嵌入任何层。

## 用法示例

```dart
import 'package:conatus_diff/conatus_diff.dart';

// 生成 → 解析 → 应用，内容保证往返一致
final String patch = buildUnifiedDiff(
  oldText: 'a\nb\n',
  newText: 'a\nc\n',
  path: 'lib/main.dart',
);
final DiffFile file = parseUnifiedDiff(patch).single;
assert(applyDiffFile('a\nb\n', file) == 'a\nc\n');
```

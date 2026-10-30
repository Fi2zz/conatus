/// conatus 的文本差异内核：统一 diff 生成 / 解析、行级 LCS 与 hunk 应用。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整。
library;

export 'src/apply.dart'
    show PatchContextException, applyDiffFile, applyEditText;
export 'src/diff_model.dart' show DiffScope, FileDiff;
export 'src/diff_parser.dart' show diffLines, parseUnifiedDiff;
export 'src/diff_types.dart' show DiffFile, DiffHunk, DiffOp, DiffOpKind;
export 'src/line_ops.dart' show lineDiffCoarse, lineDiffOps;
export 'src/unified_diff.dart' show buildUnifiedDiff, kMaxDiffLines, splitLines;

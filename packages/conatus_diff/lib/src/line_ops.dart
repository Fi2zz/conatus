/// 行级编辑脚本：公共前后缀裁剪 + LCS 动态规划（`unified_diff` 的内部算法）。
///
/// 与 hunk 渲染分开只为守住单文件行数约束；对外经 `diffLines` 暴露。
library;

import 'diff_types.dart';

/// LCS 动态规划矩阵的单元预算（`n × m`）；超预算退化为整体替换，
/// 避免大文件把内存打满。退化仍是**正确**的整段删/增，不是错误计数。
const int _kMaxLcsCells = 4 * 1000 * 1000;

/// 行级差异：先裁掉公共前后缀，再对中段做 LCS。
///
/// 一边一行的本地修改不会因文件总行数超过 [lcsLimit] 而退化成整文件替换。
/// 中段超限或矩阵超预算时整段删/增（仍是正确 diff，只是不最小）。
List<DiffOp> lineDiffOps(List<String> a, List<String> b, int lcsLimit) {
  final int prefix = _commonPrefix(a, b);
  final int suffix = _commonSuffix(a, b, prefix);
  return <DiffOp>[
    for (int i = 0; i < prefix; i++) DiffOp(DiffOpKind.equal, a[i]),
    ..._middleOps(
      a.sublist(prefix, a.length - suffix),
      b.sublist(prefix, b.length - suffix),
      lcsLimit,
    ),
    for (int i = a.length - suffix; i < a.length; i++)
      DiffOp(DiffOpKind.equal, a[i]),
  ];
}

/// 行差异是否因中段超限 / 超预算而退化成整段删增（非最小 diff）。
///
/// 调用方据此标记 [FileDiff.coarse]；退化本身是正确 diff，只是计数不精确。
bool lineDiffCoarse(List<String> a, List<String> b, int lcsLimit) {
  final int prefix = _commonPrefix(a, b);
  final int suffix = _commonSuffix(a, b, prefix);
  final int n = a.length - prefix - suffix;
  final int m = b.length - prefix - suffix;
  return n > lcsLimit || m > lcsLimit || n * m > _kMaxLcsCells;
}

int _commonPrefix(List<String> a, List<String> b) {
  final int limit = a.length < b.length ? a.length : b.length;
  int index = 0;
  while (index < limit && a[index] == b[index]) {
    index++;
  }
  return index;
}

int _commonSuffix(List<String> a, List<String> b, int prefix) {
  final int limit = (a.length < b.length ? a.length : b.length) - prefix;
  int count = 0;
  while (count < limit && a[a.length - 1 - count] == b[b.length - 1 - count]) {
    count++;
  }
  return count;
}

/// 中段行差异；超限 / 超预算时整段删增。
// REASON: LCS 动态规划是既定算法实现，分支结构由 DP 转移本身决定。
List<DiffOp> _middleOps(List<String> a, List<String> b, int lcsLimit) {
  final int n = a.length;
  final int m = b.length;
  if (n == 0 && m == 0) return const <DiffOp>[];
  if (n > lcsLimit || m > lcsLimit || n * m > _kMaxLcsCells) {
    return <DiffOp>[
      for (final String line in a) DiffOp(DiffOpKind.delete, line),
      for (final String line in b) DiffOp(DiffOpKind.insert, line),
    ];
  }
  final List<List<int>> lcs = <List<int>>[
    for (int i = 0; i <= n; i++) List<int>.filled(m + 1, 0),
  ];
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      if (a[i] == b[j]) {
        lcs[i][j] = lcs[i + 1][j + 1] + 1;
      } else {
        final int down = lcs[i + 1][j];
        final int right = lcs[i][j + 1];
        lcs[i][j] = down > right ? down : right;
      }
    }
  }
  final List<DiffOp> ops = <DiffOp>[];
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(DiffOp(DiffOpKind.equal, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      ops.add(DiffOp(DiffOpKind.delete, a[i]));
      i++;
    } else {
      ops.add(DiffOp(DiffOpKind.insert, b[j]));
      j++;
    }
  }
  while (i < n) {
    ops.add(DiffOp(DiffOpKind.delete, a[i]));
    i++;
  }
  while (j < m) {
    ops.add(DiffOp(DiffOpKind.insert, b[j]));
    j++;
  }
  return ops;
}

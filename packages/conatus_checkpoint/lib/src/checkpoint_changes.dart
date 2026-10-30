/// 两轮检查点之间的文件级变化（`/diff turn` 与 undo/redo 的数据单元）。
///
/// 归档实现按清单 + 内容比对产出，影子实现解析 `git diff --name-status`——
/// 两者共用这里的 [CheckpointFileChange] 与状态词，避免各自拼字符串。
library;

/// 一个文件在两轮之间的变化。
class CheckpointFileChange {
  const CheckpointFileChange({required this.path, required this.status});

  /// 相对工作区根的路径；重命名时是**新**路径。
  final String path;

  /// `added` / `modified` / `deleted` / `renamed`。
  final String status;

  @override
  bool operator ==(Object other) =>
      other is CheckpointFileChange &&
      other.path == path &&
      other.status == status;

  @override
  int get hashCode => Object.hash(path, status);

  @override
  String toString() => '$status $path';
}

/// git 名字状态码 → 对外状态词（`T` 是类型变化，按修改处理；`C` 是拷贝，
/// 在目标侧等价于新增）。
///
/// REASON: 静态映射表，用查表替代 switch 以免堆分支。
const Map<String, String> _kStatusByCode = <String, String>{
  'A': 'added',
  'M': 'modified',
  'T': 'modified',
  'D': 'deleted',
  'R': 'renamed',
  'C': 'added',
};

/// 解析 `git diff --name-status -z` 的输出。
///
/// `-z` 让路径以 NUL 分隔、不做引号转义（路径里的制表符 / 换行不会撕裂
/// 记录）。记录形如 `M\0path\0`，重命名 / 拷贝是 `R100\0old\0new\0`。
List<CheckpointFileChange> parseCheckpointNameStatus(String output) {
  final List<String> tokens = output.split('\u0000')
    ..removeWhere((String token) => token.isEmpty);
  final List<CheckpointFileChange> changes = <CheckpointFileChange>[];
  int index = 0;
  while (index < tokens.length) {
    final (CheckpointFileChange? change, int next) = _parseRecord(
      tokens,
      index,
    );
    if (change != null) changes.add(change);
    index = next;
  }
  return changes;
}

/// 解析一条 `-z` 记录，返回 (变化, 下一条记录的起点)。
///
/// 单路径记录是 `M\0path\0`（占 2 个 token），重命名 / 拷贝是
/// `R100\0old\0new\0`（占 3 个，取新路径）。
(CheckpointFileChange?, int) _parseRecord(List<String> tokens, int index) {
  final String code = tokens[index];
  // 重命名 / 拷贝多带一个旧路径（`R100\0old\0new\0`），新路径在最后一格。
  final int extraPath = code[0] == 'R' || code[0] == 'C' ? 1 : 0;
  final int pathIndex = index + 1 + extraPath;
  final String? status = _kStatusByCode[code[0]];
  final String path = pathIndex < tokens.length ? tokens[pathIndex] : '';
  if (status == null || path.isEmpty) return (null, pathIndex + 1);
  return (CheckpointFileChange(path: path, status: status), pathIndex + 1);
}

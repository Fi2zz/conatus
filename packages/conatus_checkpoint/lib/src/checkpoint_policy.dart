/// 检查点的排除面策略：由宿主注入，包内不含任何产品目录。
///
/// 宿主各自的只读目录、应用数据目录与构建产物习惯不同，检查点内核只认这里
/// 声明的三张表；产品侧的目录策略留在产品。
library;

/// 检查点的排除与只读策略。
class CheckpointPolicy {
  const CheckpointPolicy({
    this.ignore = const <String>[],
    this.excludedPrefixes = const <String>[],
    this.readOnlyPrefixes = const <String>[],
  });

  /// 额外忽略的相对路径前缀（顶层匹配），与内置默认值取并集。
  final List<String> ignore;

  /// 整树排除的相对路径前缀（顶层匹配）：应用数据目录 / 生成物。
  final List<String> excludedPrefixes;

  /// 只读目录的相对路径前缀（顶层、大小写不敏感）：既不进快照，也不被恢复
  /// 写回或删除。
  final List<String> readOnlyPrefixes;
}

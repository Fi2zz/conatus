/// 流程定义与运行的存储端口。
///
/// [WorkflowStore] 是持久化端口，[InMemoryWorkflowStore] 为默认内存实现。
/// 流程定义按 `name` 索引，运行按 `runId` 索引，两者互不影响。
/// 可选 `DatabaseWorkflowStore`（复用 database 插件）在后续步骤引入。
library;

import 'definition.dart';
import 'run.dart';

/// 流程定义与运行的存储。
abstract class WorkflowStore {
  /// 保存（覆盖）流程定义。
  Future<void> saveDefinition(WorkflowDefinition definition);

  /// 加载流程定义；不存在返回 `null`。
  Future<WorkflowDefinition?> loadDefinition(String name);

  /// 列出所有流程定义。
  Future<List<WorkflowDefinition>> listDefinitions();

  /// 删除流程定义。
  Future<void> deleteDefinition(String name);

  /// 保存（覆盖）运行。
  Future<void> saveRun(WorkflowRun run);

  /// 加载运行；不存在返回 `null`。
  Future<WorkflowRun?> loadRun(String runId);

  /// 列出所有运行。
  Future<List<WorkflowRun>> listRuns();

  /// 删除运行。
  Future<void> deleteRun(String runId);
}

/// 内存实现。非线程安全，供单进程/测试使用。
class InMemoryWorkflowStore implements WorkflowStore {
  final Map<String, WorkflowDefinition> _definitions =
      <String, WorkflowDefinition>{};
  final Map<String, WorkflowRun> _runs = <String, WorkflowRun>{};

  @override
  Future<void> saveDefinition(WorkflowDefinition definition) async {
    _definitions[definition.name] = definition;
  }

  @override
  Future<WorkflowDefinition?> loadDefinition(String name) async =>
      _definitions[name];

  @override
  Future<List<WorkflowDefinition>> listDefinitions() async =>
      _definitions.values.toList(growable: false);

  @override
  Future<void> deleteDefinition(String name) async {
    _definitions.remove(name);
  }

  @override
  Future<void> saveRun(WorkflowRun run) async {
    _runs[run.id] = run;
  }

  @override
  Future<WorkflowRun?> loadRun(String runId) async => _runs[runId];

  @override
  Future<List<WorkflowRun>> listRuns() async =>
      _runs.values.toList(growable: false);

  @override
  Future<void> deleteRun(String runId) async {
    _runs.remove(runId);
  }
}

/// conatus 的 coding 场景包：代码读写 / 搜索定位复用 conatus_fs_tools，
/// 本包新增代码执行层（[CodeRuntime] 接缝 + 子进程后端）与绑定桥接。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/binding/tool_binding.dart' show toolsAsBindings;
export 'src/coding.dart' show provideCoding;
export 'src/runtime/code_run_request.dart'
    show CodeBindingFn, CodeBindingNamespace, CodeRunLimits, CodeRunRequest;
export 'src/runtime/code_run_result.dart'
    show CodeRunFailure, CodeRunFailureKind, CodeRunResult;
export 'src/runtime/code_runtime.dart' show CodeRuntime;
export 'src/runtime/subprocess_runtime.dart' show SubprocessCodeRuntime;

/// conatus_doc：人机双写范式的文档补丁引擎（实验性）。
///
/// 补丁是一等公民，状态是派生物：`state(t) = fold(截至 t 生效的补丁集)`。
/// 设计文档见仓库根 `docs/人机双写范式设计文档.md`。
library;

export 'src/annotation.dart';
export 'src/block.dart';
export 'src/cursor.dart';
export 'src/dependency.dart';
export 'src/doc_events.dart';
export 'src/doc_patch.dart';
export 'src/doc_provider.dart';
export 'src/fold.dart';
export 'src/op_compiler.dart';
export 'src/patch.dart';
export 'src/patch_log.dart';
export 'src/pending.dart';

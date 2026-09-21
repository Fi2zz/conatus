/// 代码执行接缝：后端可替换。
///
/// [isolation] 是给部署与诊断用的描述符，不构成任何安全承诺。
library;

import 'code_run_request.dart';
import 'code_run_result.dart';

/// 代码执行接缝。
abstract class CodeRuntime {
  /// 后端声明的语言。如 'dart' / 'python' / 'typescript'。
  String get language;

  /// 后端声明的隔离级别。仅供部署诊断，不构成安全声明。
  String get isolation;

  /// 执行一段代码。失败以 [CodeRunResult.error] 返回，不抛异常。
  Future<CodeRunResult> run(CodeRunRequest request);

  /// 终止当前执行中的程序（若后端支持）。缺省 no-op。幂等。
  Future<void> cancelCurrent() async {}

  /// 释放后端资源。幂等。
  void dispose();
}

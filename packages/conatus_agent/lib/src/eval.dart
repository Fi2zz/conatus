/// evaluation 插件：用固定 case 衡量 Agent 表现并对比基线。
///
/// 与具体 Agent 装配解耦：调用方注入一个 [EvalRunner]（通常是「跑一轮
/// `AgentLoop.run`」或子 Agent 委托），[Evaluator] 负责跑 case、判分、汇总
/// [EvalReport]，并可 [EvalReport.compareTo] 基线报告。
library;

import 'agent_types.dart';
import 'eval_types.dart';

export 'eval_types.dart';

/// 跑一条 case，返回该轮的 [AgentTurn]。
typedef EvalRunner = Future<AgentTurn> Function(String input);

/// 评估器：跑 case、判分、汇总。
class Evaluator {
  Evaluator({required this.run, this.judge = defaultEvalJudge});

  /// 执行一条 case 的运行器（注入以便测试与替换）。
  final EvalRunner run;

  /// 判分函数。
  final EvalJudge judge;

  /// 跑一条 case。
  Future<EvalResult> evaluate(EvalCase evalCase) async {
    final Stopwatch watch = Stopwatch()..start();
    final AgentTurn turn = await run(evalCase.input);
    watch.stop();
    final EvalResult result = EvalResult(
      caseId: evalCase.id,
      passed: false,
      actualTools: <String>[
        for (final AgentStep step in turn.steps) step.call.name,
      ],
      actualOutput: turn.reply,
      rounds: turn.steps.length,
      duration: watch.elapsed,
    );
    return EvalResult(
      caseId: result.caseId,
      passed: judge(evalCase, result),
      actualTools: result.actualTools,
      actualOutput: result.actualOutput,
      rounds: result.rounds,
      duration: result.duration,
    );
  }

  /// 跑一批 case，汇总为报告。
  Future<EvalReport> runAll(List<EvalCase> cases) async {
    final List<EvalResult> results = <EvalResult>[];
    for (final EvalCase evalCase in cases) {
      results.add(await evaluate(evalCase));
    }
    return EvalReport(results);
  }
}

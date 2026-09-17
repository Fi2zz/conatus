/// `exit_plan_mode` 工具：把计划提交 [PlanMode] 评审。
///
/// 批准后 [PlanMode.exit] 随调用自动发生（工具内完成，模型无需关心）；
/// 拒绝时保持 Plan Mode 激活，反馈由模型带回修订计划。与 `plan_write`
/// （写草稿）共存：先草稿迭代，后定稿提交。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'plan.dart';
import 'plan_mode.dart';

/// `exit_plan_mode` 工具名。
const String kExitPlanModeToolName = 'exit_plan_mode';

/// 提交计划供用户审批。在 plan mode 下使用。
class ExitPlanModeTool extends Tool {
  /// 提交目标 Plan Mode 服务。
  const ExitPlanModeTool({required this.planMode});

  /// 计划提交到的 Plan Mode 服务。
  final PlanMode planMode;

  @override
  String get name => kExitPlanModeToolName;

  @override
  String get description => '提交计划供用户审批。在 plan mode 下使用。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('goal', required: true, description: '计划目标'),
        ParamSpec.array(
          'steps',
          items: ParamSpec.string('item'),
          required: true,
          description: '有序步骤列表',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String goal = ctx.str('goal');
    final List<Object?> raw = ctx.array('steps') ?? const <Object?>[];
    final List<PlanStep> steps = <PlanStep>[];
    for (int i = 0; i < raw.length; i++) {
      final String text = '${raw[i]}'.trim();
      if (text.isNotEmpty) {
        steps.add(PlanStep(id: 's${steps.length + 1}', text: text));
      }
    }
    final bool approved =
        await planMode.submitPlan(Plan(goal: goal, steps: steps));
    if (approved) {
      planMode.exit();
      return ToolResult.success('Plan approved. Proceeding with execution.');
    }
    return ToolResult.success(
        'Plan rejected. Please revise based on user feedback.');
  }
}

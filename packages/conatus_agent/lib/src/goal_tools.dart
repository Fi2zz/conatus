/// goal 插件的模型侧工具。
///
/// 四个工具注册到 `ToolRegistry`：`create_goal` / `edit_goal` /
/// `complete_goal`（low）与 `clear_goal`（medium，走 approval 确认）。
/// 返回文本面向语音场景口语化确认。`pause` / `resume` / `block` 不暴露
/// 给模型，由用户命令或续行驱动器调用。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'goal.dart';
import 'goal_service.dart';

/// `create_goal` 工具名。
const String kCreateGoalToolName = 'create_goal';

/// `edit_goal` 工具名。
const String kEditGoalToolName = 'edit_goal';

/// `complete_goal` 工具名。
const String kCompleteGoalToolName = 'complete_goal';

/// `clear_goal` 工具名。
const String kClearGoalToolName = 'clear_goal';

/// 创建长期目标。
class CreateGoalTool extends Tool {
  /// 提交目标 [GoalService]。
  const CreateGoalTool({required this.goal});

  /// 目标服务。
  final GoalService goal;

  @override
  String get name => kCreateGoalToolName;

  @override
  String get description => '创建一个长期目标。每会话至多一个。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('text', required: true, description: '目标描述'),
        ParamSpec.integer('max_rounds', description: '轮次上限，默认 256'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final Goal created = await goal.create(ctx.str('text'),
          maxRounds: ctx.integer('max_rounds'));
      return ToolResult.success('好的，我会持续关注：${created.text}');
    } on GoalException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// 编辑目标文本。
class EditGoalTool extends Tool {
  /// 提交目标 [GoalService]。
  const EditGoalTool({required this.goal});

  /// 目标服务。
  final GoalService goal;

  @override
  String get name => kEditGoalToolName;

  @override
  String get description => '编辑当前长期目标的描述。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('text', required: true, description: '新的目标描述'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      final Goal edited = await goal.edit(ctx.str('text'));
      return ToolResult.success('好的，目标已更新：${edited.text}');
    } on GoalException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// 标记目标完成。
class CompleteGoalTool extends Tool {
  /// 提交目标 [GoalService]。
  const CompleteGoalTool({required this.goal});

  /// 目标服务。
  final GoalService goal;

  @override
  String get name => kCompleteGoalToolName;

  @override
  String get description => '标记当前长期目标为已完成。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => const <ParamSpec>[];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      await goal.complete();
      return ToolResult.success('目标已标记完成。');
    } on GoalException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

/// 清除目标（走 approval 确认，丢失全部进度）。
class ClearGoalTool extends Tool {
  /// 提交目标 [GoalService]。
  const ClearGoalTool({required this.goal});

  /// 目标服务。
  final GoalService goal;

  @override
  String get name => kClearGoalToolName;

  @override
  String get description => '清除当前长期目标（会丢失所有进度，需用户确认）。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => const <ParamSpec>[];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    try {
      await goal.clear();
      return ToolResult.success('好的，目标已清除。');
    } on GoalException catch (e) {
      return ToolResult.failure(e.message, error: ToolError(e.code, e.message));
    }
  }
}

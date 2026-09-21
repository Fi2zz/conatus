/// Plan Mode 面板视图：状态 + 计划步骤（goal / ✓☐ 步骤列表）。
///
/// 按键在根组件处理（见 `tui.dart`），本组件只渲染 [TuiPlanPrompt]。
library;

import 'package:conatus_agent/conatus_agent.dart';
import 'package:nocterm/nocterm.dart';

import 'tui_plan.dart';

/// Plan Mode 面板。
class TuiPlanView extends StatelessComponent {
  const TuiPlanView({super.key, required this.prompt});

  /// 面板状态。
  final TuiPlanPrompt prompt;

  @override
  Component build(BuildContext context) {
    final Plan? plan = prompt.plan;
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          const Text(
            'Plan Mode',
            style: TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Enter 进入/退出 · Esc 关闭',
            style: TextStyle(color: Colors.gray),
          ),
          const SizedBox(height: 1),
          Row(
            children: <Component>[
              const Text('状态：'),
              Text(
                prompt.active ? '● 已激活' : '○ 未激活',
                style: TextStyle(
                  color: prompt.active ? Colors.brightGreen : Colors.gray,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          if (plan == null)
            const Text(
              '尚未写入计划（激活后模型会经 plan_write 写入）。',
              style: TextStyle(color: Colors.gray),
            )
          else ...<Component>[
            Text(
              '计划：${plan.goal}',
              style: const TextStyle(color: Colors.white),
            ),
            for (int i = 0; i < plan.steps.length; i++)
              Text(
                '  ${plan.steps[i].done ? '✓' : '☐'} ${i + 1}. ${plan.steps[i].text}',
                style: TextStyle(
                  color: plan.steps[i].done ? Colors.gray : Colors.white,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

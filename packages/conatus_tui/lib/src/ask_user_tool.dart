/// `ask_user` 工具：让模型把若干选项交给用户，经 TUI 选项浮层选择后回传。
///
/// 除通用选项外，`purpose: permission_mode` 是一个内置选项集：渲染三档权限
/// 模式，选中即应用到当前会话（模型据此获知结果）。工具自身风险为 low，
/// 因此不会被审批拦截——否则「始终询问」档下会自我递归。
library;

import 'dart:async';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'tui_choice.dart';
import 'tui_permission.dart';

/// `ask_user` 工具名。
const String kAskUserToolName = 'ask_user';

/// 内置提问用途：询问权限模式。
const String kAskUserPurposePermissionMode = 'permission_mode';

/// 等待用户选择的时长（交互类工具，不受默认超时约束）。
const Duration kAskUserTimeout = Duration(minutes: 30);

/// 提问宿主：提供浮层与权限模式读写。由 TUI 控制器实现。
abstract class TuiUserPromptHost {
  /// 选项浮层。
  TuiChoicePrompt get choice;

  /// 当前权限模式。
  TuiPermissionMode get permissionMode;

  /// 应用权限模式。
  void applyPermissionMode(TuiPermissionMode mode);
}

/// 让模型向用户提问并拿到选择。
class AskUserTool extends Tool {
  AskUserTool({required this.host});

  /// 宿主解析器；TUI 未就绪时返回 `null`。
  final TuiUserPromptHost? Function() host;

  @override
  String get name => kAskUserToolName;

  @override
  String get description => '向用户提出一个问题并给出候选选项，返回用户选中的项。'
      'purpose 传 permission_mode 时改问权限模式（选项由界面内置）。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  Duration? get timeout => kAskUserTimeout;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('question', required: true, description: '要问用户的问题'),
        ParamSpec.array(
          'options',
          items: ParamSpec.string('item'),
          description: '候选选项（purpose 为 permission_mode 时可省略）',
        ),
        ParamSpec.enumeration(
          'purpose',
          const <String>[kAskUserPurposePermissionMode],
          description: '内置提问用途；留空表示使用自定义 options',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final TuiUserPromptHost? target = host();
    if (target == null) {
      return ToolResult.failure(
        '界面尚未就绪，无法询问用户。',
        error: const ToolError('ASK_USER_UNAVAILABLE', 'no tui host'),
      );
    }
    final bool permissionMode =
        ctx.string('purpose') == kAskUserPurposePermissionMode;
    final String question = ctx.str('question');
    final String? picked = permissionMode
        ? await _askPermissionMode(target, question)
        : await _askOptions(target, question, ctx.array('options'));
    if (picked == null) {
      return ToolResult.failure(
        '用户未在时限内选择（已取消或超时）。',
        error: const ToolError('ASK_USER_CANCELLED', 'no answer'),
      );
    }
    return ToolResult.success(picked);
  }

  Future<String?> _askPermissionMode(
    TuiUserPromptHost target,
    String question,
  ) async {
    final TuiPermissionMode current = target.permissionMode;
    final String? picked = await target.choice.ask(
      TuiChoiceRequest(
        title: question,
        choices: <TuiChoice>[
          for (final TuiPermissionMode mode in TuiPermissionMode.values)
            TuiChoice(
              id: mode.name,
              label: mode.label,
              description: mode.description,
              current: mode == current,
            ),
        ],
      ),
      timeout: kAskUserTimeout,
    );
    final TuiPermissionMode? mode =
        picked == null ? null : parsePermissionMode(picked);
    if (mode == null) return null;
    target.applyPermissionMode(mode);
    return '用户选择了权限模式「${mode.label}」（已生效）。';
  }

  Future<String?> _askOptions(
    TuiUserPromptHost target,
    String question,
    List<Object?>? raw,
  ) async {
    final List<String> options = <String>[
      for (final Object? item in raw ?? const <Object?>[])
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
    if (options.isEmpty) {
      return '未提供候选选项，请改用普通文本提问。';
    }
    final String? picked = await target.choice.ask(
      TuiChoiceRequest(
        title: question,
        choices: <TuiChoice>[
          for (int i = 0; i < options.length; i++)
            TuiChoice(id: '$i', label: options[i]),
        ],
      ),
      timeout: kAskUserTimeout,
    );
    if (picked == null) return null;
    return '用户选择了：「${options[int.parse(picked)]}」';
  }
}

/// TUI 渲染件：消息行、思考占位行与若干展示工具。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_message.dart';

/// 思考中动画帧。
const List<String> tuiSpinFrames = <String>[
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⠼',
  '⠴',
  '⠦',
  '⠧',
  '⠇',
  '⠏',
];

/// 当前动画帧。
String tuiSpinner(int tick) => tuiSpinFrames[tick % tuiSpinFrames.length];

/// 动态省略号（纯 ASCII，兼容不显示盲文点的终端）。
String tuiDots(int tick) => '.' * (tick % 4);

/// 相对时间描述（用于会话面板）。
String timeAgo(DateTime? time) {
  if (time == null) {
    return '未知';
  }
  final Duration diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}小时前';
  }
  return '${diff.inDays}天前';
}

/// 一条屏上消息：用户 / 助手带前缀，工具 / 阶段 / 系统 / 导航为缩进提示行。
class MessageView extends StatelessComponent {
  const MessageView({super.key, required this.message});

  /// 要渲染的消息。
  final TuiMessage message;

  @override
  Component build(BuildContext context) {
    switch (message.role) {
      case TuiRole.user:
        return _bubble(
          '你',
          Colors.brightGreen,
          Text(message.text, style: const TextStyle(color: Colors.white)),
        );
      case TuiRole.assistant:
        return _bubble(
          '助手',
          Colors.brightCyan,
          MarkdownText(message.text),
        );
      case TuiRole.tool:
        return _indent(message.text, Colors.cyan);
      case TuiRole.stage:
        return _indent(message.text, Colors.brightBlack);
      case TuiRole.system:
        return _indent(message.text, Colors.yellow);
      case TuiRole.nav:
        return _indent(message.text, Colors.magenta);
    }
  }

  Component _bubble(String label, Color color, Component body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Component>[
        Text(
          '$label：',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        Expanded(child: body),
      ],
    );
  }

  Component _indent(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

/// 思考占位行：等待模型回复期间显示在记录末尾。
class LoadingView extends StatelessComponent {
  const LoadingView({super.key, required this.tick});

  /// 动画帧计数。
  final int tick;

  @override
  Component build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Component>[
        const Text(
          '助手：',
          style:
              TextStyle(color: Colors.brightCyan, fontWeight: FontWeight.bold),
        ),
        Text(
          '${tuiSpinner(tick)} 思考中${tuiDots(tick)}',
          style: const TextStyle(color: Colors.brightYellow),
        ),
      ],
    );
  }
}

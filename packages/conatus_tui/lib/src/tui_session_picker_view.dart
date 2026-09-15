/// 会话选择面板：`↑↓` 选择、`Enter` 切换、`Esc` 关闭（按键在根组件处理）。
///
/// 列表随选中项滚动：会话数超过可视高度时，光标不会滚出画面。
library;

import 'package:nocterm/nocterm.dart';

import 'tui_session_picker.dart';
import 'tui_views.dart';

/// 会话选择面板视图。
class SessionPickerView extends StatefulComponent {
  const SessionPickerView({
    super.key,
    required this.sessions,
    required this.currentId,
    required this.selected,
  });

  /// 会话列表。
  final List<TuiSessionInfo> sessions;

  /// 当前会话 id。
  final String currentId;

  /// 当前选中下标。
  final int selected;

  @override
  State<SessionPickerView> createState() => _SessionPickerViewState();
}

class _SessionPickerViewState extends State<SessionPickerView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _ensureSelectedVisible();
  }

  @override
  void didUpdateComponent(SessionPickerView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.selected != component.selected ||
        oldComponent.sessions.length != component.sessions.length) {
      _ensureSelectedVisible();
    }
  }

  /// 帧后定位：首帧 render object 尚未 attach，需等布局完成再滚动。
  void _ensureSelectedVisible() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scroll.ensureIndexVisible(index: component.selected);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final List<TuiSessionInfo> sessions = component.sessions;
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: BoxBorder.all(color: Colors.brightBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Component>[
          const Text(
            '会话（↑↓ 选择，Enter 切换，Esc 关闭）',
            style: TextStyle(
              color: Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          if (sessions.isEmpty)
            const Text(
              '暂无会话；直接输入开始对话，或 /new 开一个。',
              style: TextStyle(color: Colors.gray),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemCount: sessions.length,
                itemBuilder: (BuildContext context, int index) =>
                    _row(sessions[index], index == component.selected),
              ),
            ),
        ],
      ),
    );
  }

  Component _row(TuiSessionInfo session, bool isSelected) {
    final String mark = session.id == component.currentId ? '*' : ' ';
    final String cursor = isSelected ? '>' : ' ';
    final String detail = session.active
        ? '${session.events} 条事件  ${timeAgo(session.updatedAt)}'
        : '已保存';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: isSelected ? const Color.fromRGB(30, 40, 60) : null,
      child: Text(
        '$cursor$mark ${session.id}  $detail',
        style: TextStyle(
          color: isSelected ? Colors.brightWhite : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

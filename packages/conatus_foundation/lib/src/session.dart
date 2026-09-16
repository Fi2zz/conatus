/// session 插件：append-only 的会话事件日志。
///
/// 一条会话是一串不可修改的 [SessionEvent]（seq 从 0 单调递增，事件带唯一
/// [SessionEvent.id]）。追加会同步通知 [onEvent] 监听器（SessionStore 借此
/// 落盘），关闭会通知 [onClose] 并拒绝后续追加。多会话的创建与持久化见
/// `session_store.dart`；多会话的只追加日志抽象见 `session_log.dart`。
///
/// 本类同时提供 [fork]（从某个事件点分叉出新的会话）与 [replay]（按序重放），
/// 它们与 Session Log 的不变式一致：日志不被改写，任何派生都是新事件 / 新会话。
library;

import 'package:conatus_core/conatus_core.dart';
import 'session_types.dart';

/// 一次会话：持有事件日志与监听器。
class Session {
  Session({
    required this.id,
    Iterable<SessionEvent> seed = const <SessionEvent>[],
    this.inheritedEventCount = 0,
  }) {
    final List<SessionEvent> inherited = List<SessionEvent>.of(seed);
    if (inheritedEventCount < 0 || inheritedEventCount > inherited.length) {
      throw ArgumentError('inheritedEventCount 必须落在 seed 范围内');
    }
    _events.addAll(inherited);
    _seq = _events.isEmpty ? 0 : _events.last.seq + 1;
    createdAt = _events.isEmpty ? DateTime.now() : _events.first.time;
  }

  /// 会话标识（也是持久化文件名）。
  final String id;

  /// 由 [seed] 继承的父会话事件条数（[fork] 时大于 0；重新打开会话时为 0）。
  ///
  /// [events] 的前若干条即继承前缀，本会话真正拥有的事件从该切点之后开始
  /// （见 [ownEvents]）。派生状态只折叠自身后缀，因此 fork 出的会话不会继承
  /// 父会话的活动状态。
  final int inheritedEventCount;

  /// 本会话自身拥有的事件（跳过继承前缀）。
  List<SessionEvent> get ownEvents =>
      List<SessionEvent>.unmodifiable(_events.skip(inheritedEventCount));

  /// 会话创建时间（取首条事件时间）。
  late final DateTime createdAt;

  final List<SessionEvent> _events = <SessionEvent>[];
  final List<void Function(SessionEvent)> _eventListeners =
      <void Function(SessionEvent)>[];
  final List<void Function()> _closeListeners = <void Function()>[];
  int _seq = 0;
  bool _closed = false;
  int _forks = 0;

  /// 事件日志的只读视图。
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  /// 事件条数。
  int get length => _events.length;

  /// 是否已关闭。
  bool get closed => _closed;

  /// 最后一条事件的 id；空日志为 `null`。
  String? get lastEventId => _events.isEmpty ? null : _events.last.id;

  /// 追加一条事件并返回它。会话关闭后抛 [StateError]。
  SessionEvent append(
    String type, {
    Object? data,
    String? parentEventId,
    DateTime? time,
    String? id,
  }) {
    if (_closed) throw StateError('会话 "${this.id}" 已关闭，无法追加事件');
    final SessionEvent event = SessionEvent.create(
      sessionId: this.id,
      type: type,
      seq: _seq++,
      data: data,
      parentEventId: parentEventId,
      time: time,
      id: id,
    );
    _appendEvent(event);
    return event;
  }

  /// 追加一条已构造的事件。
  ///
  /// 事件若不是本会话所有，会用本会话 id 与下一个 seq 重新盖章；返回落定后的
  /// 事件。这使 [SessionLog] / 反序列化路径可以安全回填事件。
  SessionEvent appendEvent(SessionEvent event) {
    if (_closed) throw StateError('会话 "$id" 已关闭，无法追加事件');
    final SessionEvent stamped = event.copyWith(
      sessionId: id,
      seq: _seq++,
      time: event.time,
      id: event.id ?? nextSessionEventId(),
    );
    _appendEvent(stamped);
    return stamped;
  }

  void _appendEvent(SessionEvent event) {
    _events.add(event);
    for (final void Function(SessionEvent) listener
        in List<void Function(SessionEvent)>.of(_eventListeners)) {
      listener(event);
    }
  }

  /// 按时间（seq）顺序读取事件；[from] / [to] 为闭区间的时间过滤。
  List<SessionEvent> read({DateTime? from, DateTime? to}) => <SessionEvent>[
        for (final SessionEvent event in _events)
          if ((from == null || !event.time.isBefore(from)) &&
              (to == null || !event.time.isAfter(to)))
            event,
      ];

  /// 从 [fromEventId] 处 fork 出新会话。
  ///
  /// 新会话以「截止该事件（含）」的事件为种子，拥有新 id（缺省自动生成）且
  /// 与原会话完全解耦；原会话不受影响。找不到该事件时抛 [StateError]。
  Session fork({String? fromEventId, String? id}) {
    final List<SessionEvent> seed;
    if (fromEventId == null) {
      seed = _events;
    } else {
      final int index =
          _events.indexWhere((SessionEvent event) => event.id == fromEventId);
      if (index < 0) {
        throw StateError('会话 "$id" 中不存在事件 "$fromEventId"');
      }
      seed = _events.sublist(0, index + 1);
    }
    _forks++;
    return Session(
      id: id ?? '$id-fork-$_forks',
      seed: seed,
      inheritedEventCount: seed.length,
    );
  }

  /// 重放：按事件顺序依次回调 [handler]。日志不被改写。
  void replay(void Function(SessionEvent event) handler) {
    for (final SessionEvent event in List<SessionEvent>.of(_events)) {
      handler(event);
    }
  }

  /// 监听后续追加。返回撤销函数（幂等）。
  Disposer onEvent(void Function(SessionEvent event) listener) {
    _eventListeners.add(listener);
    return () => _eventListeners.remove(listener);
  }

  /// 监听会话关闭；已关闭时立即回调。返回撤销函数（幂等）。
  Disposer onClose(void Function() listener) {
    if (_closed) {
      listener();
      return () {};
    }
    _closeListeners.add(listener);
    return () => _closeListeners.remove(listener);
  }

  /// 关闭会话：通知关闭监听器并拒绝后续追加。幂等。
  void close() {
    if (_closed) return;
    _closed = true;
    final List<void Function()> listeners =
        List<void Function()>.of(_closeListeners);
    _closeListeners.clear();
    _eventListeners.clear();
    for (final void Function() listener in listeners) {
      listener();
    }
  }

  @override
  String toString() => 'Session($id, $length events)';
}

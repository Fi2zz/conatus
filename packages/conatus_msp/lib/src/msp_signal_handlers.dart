import 'dart:io';

import 'package:conatus_core/conatus_core.dart';

import 'msp_path_matcher.dart';
import 'msp_signal.dart';

typedef MspSignalHandler = void Function(MspSignal signal);

class MspSignalHandlers {
  final Map<int, ({String? pattern, MspSignalHandler callback})> _entries =
      <int, ({String? pattern, MspSignalHandler callback})>{};
  int _nextId = 0;

  Disposer add(String? pattern, MspSignalHandler callback) {
    final int id = ++_nextId;
    _entries[id] = (pattern: pattern, callback: callback);
    return () => _entries.remove(id);
  }

  void dispatch(MspSignal signal) {
    final List<({String? pattern, MspSignalHandler callback})> entries =
        _entries.values.toList();
    for (final ({String? pattern, MspSignalHandler callback}) entry
        in entries) {
      if (entry.pattern != null &&
          !matchesMspPath(entry.pattern!, signal.path ?? '')) {
        continue;
      }
      _invoke(entry.callback, signal);
    }
  }

  void _invoke(MspSignalHandler callback, MspSignal signal) {
    try {
      callback(signal);
    } on Object catch (error) {
      stderr.writeln('[msp] 信号订阅回调失败：$error');
    }
  }
}

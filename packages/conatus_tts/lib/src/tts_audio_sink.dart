/// TTS 音频输出接口与几个通用实现。
///
/// [TtsAudioSink] 是宿主接入点：把合成音频送去扬声器 / 文件 / 网络。CLI / 桌面可
/// 写本地播放器或文件，Flutter 端写平台音频播放插件；本文件另附内存缓冲、流与
/// 回调三种开箱实现，便于保存到文件或测试。
library;

import 'dart:async';

/// 合成音频的输出接口：把音频字节送往哪里由宿主实现。
///
/// 框架只保证：按顺序调用 [write]，最后调用一次 [close]。
abstract class TtsAudioSink {
  /// 接收一段音频字节。
  void write(List<int> bytes);

  /// 输出结束（幂等）：宿主在此关闭播放器 / 刷新缓冲。
  Future<void> close();
}

/// 把音频累积到内存的 [TtsAudioSink]，便于保存为文件或做断言。
class BytesAudioSink implements TtsAudioSink {
  final List<int> _bytes = <int>[];

  /// 已累积的音频字节。
  List<int> get bytes => List<int>.unmodifiable(_bytes);

  @override
  void write(List<int> data) => _bytes.addAll(data);

  @override
  Future<void> close() async {}
}

/// 把音频作为字节流暴露的 [TtsAudioSink]，便于边合成边消费（如推给播放器）。
class StreamAudioSink implements TtsAudioSink {
  StreamAudioSink();

  final StreamController<List<int>> _controller = StreamController<List<int>>();

  /// 音频字节流。
  Stream<List<int>> get stream => _controller.stream;

  @override
  void write(List<int> data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

/// 用回调接收音频的 [TtsAudioSink]。
class CallbackAudioSink implements TtsAudioSink {
  CallbackAudioSink({required this.onData, this.onClose});

  /// 每段音频到达时回调。
  final void Function(List<int> bytes) onData;

  /// 输出结束时回调（可选）。
  final FutureOr<void> Function()? onClose;

  @override
  void write(List<int> data) => onData(data);

  @override
  Future<void> close() async {
    await onClose?.call();
  }
}

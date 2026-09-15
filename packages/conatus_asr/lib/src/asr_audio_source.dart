/// 音频源能力缝：把「原始音频字节从哪来」与 ASR provider 解耦。
///
/// CLI / 桌面用 ffmpeg 采集麦克风（见 `asr_audio_source_ffmpeg.dart`）；Flutter
/// 端用录音插件实现同一接口，把 PCM 字节推给 [AsrSession]。provider 与工具层
/// 不感知差异。
library;

import 'asr.dart';

/// 原始音频字节源。
abstract class AsrAudioSource {
  /// 该源产出的音频参数。
  AsrAudioFormat get format;

  /// 原始音频字节流（PCM s16le）；[stop] 后关闭。
  Stream<List<int>> get bytes;

  /// 启动采集。
  Future<void> start();

  /// 停止采集并释放（幂等）。
  Future<void> stop();
}

/// 把 [source] 接入一次流式识别，返回识别事件流（以 [AsrFinal] 收尾）。
///
/// 事件流结束后自动 [AsrAudioSource.stop]。
Stream<AsrEvent> transcribeSource(
  AsrService asr,
  AsrAudioSource source, {
  String? provider,
  String? language,
  List<String> hotwords = const <String>[],
}) async* {
  await source.start();
  try {
    yield* asr.transcribe(
      source.bytes,
      provider: provider,
      audioFormat: source.format,
      language: language,
      hotwords: hotwords,
    );
  } finally {
    await source.stop();
  }
}

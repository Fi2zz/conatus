/// tts 插件的词汇：音频格式、音色、provider/session 契约与错误。
///
/// 这一层是**纯能力描述**：只谈「一段文本如何变成音频字节」，音频写到哪由
/// [TtsAudioSink] 决定（扬声器 / 文件 / 网络由宿主实现），具体服务商由
/// [TtsProvider] 实现。
library;

import 'tts_audio_sink.dart';

/// 合成音频的格式。
///
/// 默认 MP3 24kHz 单声道；[format] 取值随 provider 而异，火山常见为
/// `mp3` / `pcm` / `wav` / `ogg_opus`。
class TtsAudioFormat {
  const TtsAudioFormat({
    this.format = 'mp3',
    this.rate = 24000,
    this.bits = 16,
    this.channel = 1,
  });

  /// 容器 / 编码格式。
  final String format;

  /// 采样率（Hz）。
  final int rate;

  /// 采样点位数。
  final int bits;

  /// 声道数。
  final int channel;

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'rate': rate,
        'bits': bits,
        'channel': channel,
      };

  @override
  String toString() =>
      'TtsAudioFormat($format, ${rate}Hz, ${bits}bit, ${channel}ch)';
}

/// 合成音色。
class TtsVoice {
  const TtsVoice(this.id, {this.language});

  /// 音色 ID（火山为 `voice_type` / `speaker`）。
  final String id;

  /// 语言提示（可选）。
  final String? language;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (language != null) 'language': language,
      };

  @override
  String toString() => 'TtsVoice($id)';
}

/// 一次可流式送入文本的合成会话。
///
/// 生命周期：`start` 后多次 [send] 送入文本片段，最后调用 [finish] 等待合成完成；
/// 合成的音频字节由 provider 写入创建会话时提供的 [TtsAudioSink]。会话可被
/// [close] 幂等释放。
abstract class TtsSession {
  /// 送入一段文本（流式合成时可为多个片段）。
  void send(String text);

  /// 结束输入并等待合成完成（音频已写入并关闭 sink）。
  Future<void> finish();

  /// 释放会话（幂等）。
  void close();
}

/// TTS provider 契约。
///
/// 实现负责把文本合成为音频字节并写入 [TtsAudioSink]，失败时抛 [TtsException]；
/// provider 的回退链由 [TtsService] 编排。
abstract class TtsProvider {
  /// provider 名（用于诊断与显式路由）。
  String get name;

  /// 默认音频格式。
  TtsAudioFormat get audioFormat;

  /// 默认音色；未配置时为 `null`。
  TtsVoice? get defaultVoice;

  /// 开启一次合成会话，音频写入 [sink]。
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  });
}

/// 合成失败。
class TtsException implements Exception {
  const TtsException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'TtsException: $message';
}

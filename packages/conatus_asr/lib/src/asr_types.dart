/// asr 插件的词汇：音频参数、识别结果、provider/session 契约与错误。
///
/// 这一层是**纯能力描述**：只谈「一段音频字节如何变成文本」，不涉及音频从哪来
/// （麦克风 / 文件 / 网络流由 [AsrAudioSource] 或调用方提供），也不涉及具体服务商
/// （由 [AsrProvider] 实现）。
library;

/// 送入识别服务的音频参数。
///
/// 默认值对应火山流式识别要求：PCM s16le、16kHz、单声道。
class AsrAudioFormat {
  const AsrAudioFormat({
    this.format = 'pcm',
    this.codec = 'raw',
    this.rate = 16000,
    this.bits = 16,
    this.channel = 1,
  });

  /// 容器格式：`pcm` / `wav` / `ogg` / `mp3`。
  final String format;

  /// 编码：`raw`（PCM）或 `opus`。
  final String codec;

  /// 采样率（Hz）；火山目前仅支持 16000。
  final int rate;

  /// 采样点位数；目前仅支持 16。
  final int bits;

  /// 声道数：1（单声道）或 2（立体声）。
  final int channel;

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'codec': codec,
        'rate': rate,
        'bits': bits,
        'channel': channel,
      };

  @override
  String toString() =>
      'AsrAudioFormat($format/$codec, ${rate}Hz, ${bits}bit, ${channel}ch)';
}

/// 识别结果中的分句信息（服务端开启分句时提供）。
class AsrUtterance {
  const AsrUtterance({
    required this.text,
    this.startMs,
    this.endMs,
    this.definite = false,
  });

  /// 分句文本。
  final String text;

  /// 起始时间（毫秒）。
  final int? startMs;

  /// 结束时间（毫秒）。
  final int? endMs;

  /// 该分句是否已定稿（二遍识别时由服务端标记）。
  final bool definite;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        if (startMs != null) 'start_ms': startMs,
        if (endMs != null) 'end_ms': endMs,
        'definite': definite,
      };

  @override
  String toString() => 'AsrUtterance($text, ${startMs ?? 0}-${endMs ?? 0}ms)';
}

/// 一次识别结果快照。
class AsrResult {
  const AsrResult({
    required this.text,
    this.utterances = const <AsrUtterance>[],
    this.isFinal = false,
  });

  /// 整个音频的识别文本（流式下为当前最佳文本）。
  final String text;

  /// 分句信息。
  final List<AsrUtterance> utterances;

  /// 是否为最终结果。
  final bool isFinal;

  Map<String, Object?> toJson() => <String, Object?>{
        'text': text,
        'is_final': isFinal,
        if (utterances.isNotEmpty)
          'utterances': <Map<String, Object?>>[
            for (final AsrUtterance utterance in utterances) utterance.toJson(),
          ],
      };

  @override
  String toString() => 'AsrResult($text${isFinal ? ', final' : ''})';
}

/// 流式识别事件。
sealed class AsrEvent {
  const AsrEvent();

  /// 该事件携带的结果快照。
  AsrResult get result;
}

/// 增量（未定稿）结果。
final class AsrPartial extends AsrEvent {
  const AsrPartial(this.result);

  @override
  final AsrResult result;

  @override
  String toString() => 'AsrPartial($result)';
}

/// 最终结果。
final class AsrFinal extends AsrEvent {
  const AsrFinal(this.result);

  @override
  final AsrResult result;

  @override
  String toString() => 'AsrFinal($result)';
}

/// 一次流式识别会话。
///
/// 生命周期：`start` 后多次 [send] 送入音频帧，最后一帧后调用 [finish] 请求
/// 最终结果；[events] 以 [AsrFinal] 收尾。会话可被 [close] 幂等释放。
abstract class AsrSession {
  /// 增量识别事件；以 [AsrFinal] 收尾，或在失败后以错误关闭。
  Stream<AsrEvent> get events;

  /// 送入一帧音频字节（格式须与 `start` 时的 [AsrAudioFormat] 一致）。
  void send(List<int> bytes);

  /// 送入最后一帧并请求最终结果。
  Future<void> finish();

  /// 释放会话（幂等）。
  void close();
}

/// ASR provider 契约。
///
/// 实现只负责开启一次流式会话，失败时抛 [AsrException]；provider 的回退链由
/// [AsrService] 编排。
abstract class AsrProvider {
  /// provider 名（用于诊断与显式路由）。
  String get name;

  /// 默认音频参数（如麦克风 PCM 16k 单声道）。
  AsrAudioFormat get audioFormat;

  /// 开启一次流式会话。
  ///
  /// [audio] 覆盖默认音频参数（如文件转写按扩展名推断格式）；[language] 为
  /// 语言提示；[hotwords] 为热词（provider 尽力支持）。
  Future<AsrSession> start({
    AsrAudioFormat? audio,
    String? language,
    List<String> hotwords = const <String>[],
  });
}

/// 识别失败。
class AsrException implements Exception {
  const AsrException(this.message);

  /// 人可读的失败说明。
  final String message;

  @override
  String toString() => 'AsrException: $message';
}

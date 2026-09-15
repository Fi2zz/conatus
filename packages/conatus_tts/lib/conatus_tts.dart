/// conatus 的 TTS 能力缝。
///
/// - [TtsService] + 可插拔 [TtsProvider]：默认豆包/火山语音合成；
/// - [TtsSession]：可流式送入文本的合成会话；
/// - [TtsAudioSink]：**音频输出接口**，音频写到哪（扬声器 / 文件 / 网络）由宿主实现；
/// - [DoubaoHttpTtsProvider]：火山 HTTP 语音合成 provider。
///
/// ```dart
/// import 'package:conatus_tts/conatus_tts.dart';
///
/// provideTts(app);   // 读 VOLC_TTS_APP_ID / VOLC_TTS_ACCESS_TOKEN
///
/// // 音频去自定义 sink（示例：内存缓冲）
/// final bytes = await ctx.tts.synthesize('你好，世界');
/// ```
library;

export 'src/tts.dart' show TtsContext, TtsService, provideTts;
export 'src/tts_audio_sink.dart'
    show BytesAudioSink, CallbackAudioSink, StreamAudioSink, TtsAudioSink;
export 'src/tts_doubao.dart'
    show
        DoubaoHttpTtsProvider,
        defaultDoubaoHttpTtsUrl,
        defaultDoubaoTtsCluster,
        defaultDoubaoTtsVoice;
export 'src/tts_types.dart'
    show TtsAudioFormat, TtsException, TtsProvider, TtsSession, TtsVoice;

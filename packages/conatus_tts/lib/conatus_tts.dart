/// conatus 的 TTS 能力缝。
///
/// - [TtsService] + 可插拔 [TtsProvider]：默认豆包/火山 v3 WebSocket 单向流式合成；
/// - [TtsSession]：可流式送入文本的合成会话；
/// - [TtsAudioSink]：**音频输出接口**，音频写到哪（扬声器 / 文件 / 网络）由宿主实现；
/// - [DoubaoStreamingTtsProvider]：火山 `wss://.../api/v3/tts/unidirectional/stream`。
///
/// ```dart
/// import 'package:conatus_tts/conatus_tts.dart';
///
/// provideTts(app);   // 读 VOLC_TTS_API_KEY，或 VOLC_TTS_APP_KEY + ACCESS_TOKEN
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
        DoubaoStreamingTtsProvider,
        TtsSocket,
        TtsSocketConnector,
        defaultDoubaoTtsResourceId,
        defaultDoubaoTtsStreamUrl,
        defaultDoubaoTtsVoice;
export 'src/tts_protocol.dart'
    show
        TtsFrame,
        buildTtsFrame,
        buildTtsRequest,
        decodeTtsFrame,
        ttsCompressionGzip,
        ttsCompressionNone,
        ttsEventConnectionFailed,
        ttsEventConnectionFinished,
        ttsEventConnectionStarted,
        ttsEventResponse,
        ttsEventSentenceEnd,
        ttsEventSentenceStart,
        ttsEventSessionFinished,
        ttsFlagNegativeSeq,
        ttsFlagNoSeq,
        ttsFlagPositiveSeq,
        ttsFlagWithEvent,
        ttsHeaderSize,
        ttsMsgAudioOnlyServer,
        ttsMsgError,
        ttsMsgFullClientRequest,
        ttsMsgFullServerResponse,
        ttsProtocolVersion,
        ttsSerializationJson,
        ttsSerializationRaw;
export 'src/tts_types.dart'
    show TtsAudioFormat, TtsException, TtsProvider, TtsSession, TtsVoice;

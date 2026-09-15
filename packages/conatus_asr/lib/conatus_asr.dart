/// conatus 的 ASR 能力缝。
///
/// - [AsrService] + 可插拔 [AsrProvider]：默认豆包/火山 SAUC 流式识别；
/// - [AsrSession] / [AsrEvent]：输入源无关的流式识别会话；
/// - [AsrAudioSource]：音频来源缝（CLI/桌面 ffmpeg 麦克风实现）；
/// - [TranscribeAudioTool] / [provideAsrTools]：`transcribe_audio` 文件转写工具；
/// - [asr_protocol.dart]：SAUC WebSocket 二进制协议编解码。
///
/// ```dart
/// import 'package:conatus_asr/conatus_asr.dart';
///
/// provideAsr(app);        // 读 VOLC_ASR_API_KEY / VOLC_ASR_APP_KEY + ACCESS_KEY
/// provideAsrTools(app);   // 注册 transcribe_audio
/// ```
library;

export 'src/asr.dart' show AsrContext, AsrService, provideAsr;
export 'src/asr_audio_source.dart' show AsrAudioSource, transcribeSource;
export 'src/asr_audio_source_ffmpeg.dart' show FfmpegInput, FfmpegMicSource;
export 'src/asr_doubao.dart'
    show
        AsrSocket,
        AsrSocketConnector,
        DoubaoAuthHeaders,
        DoubaoStreamingAsrProvider,
        defaultDoubaoAsrUrl,
        doubaoAsrResourceDuration,
        doubaoAsrResourceSeedDuration;
export 'src/asr_protocol.dart'
    show
        AsrFrame,
        asrCompressionGzip,
        asrCompressionNone,
        asrFlagLast,
        asrFlagLastSequence,
        asrFlagSequence,
        asrHeaderSize,
        asrMessageAudioOnly,
        asrMessageError,
        asrMessageFullClientRequest,
        asrMessageFullServerResponse,
        asrProtocolVersion,
        asrSerializationJson,
        asrSerializationNone,
        buildAsrFrame,
        buildAudioFrame,
        buildFullClientRequest,
        decodeAsrFrame,
        decodeAsrJson;
export 'src/asr_tools.dart'
    show TranscribeAudioTool, formatForPath, provideAsrTools;
export 'src/asr_types.dart'
    show
        AsrAudioFormat,
        AsrEvent,
        AsrException,
        AsrFinal,
        AsrPartial,
        AsrProvider,
        AsrResult,
        AsrSession,
        AsrUtterance;

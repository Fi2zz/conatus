/// asr 工具：把语音转文本能力暴露给模型。
///
/// [TranscribeAudioTool] 走 `ctx.asr`（provider 回退由 [AsrService] 负责），把本地
/// 音频文件按流式协议分片送入识别服务。它是 [ToolRisk.low] 的只读工具，用
/// [provideAsrTools] 注册到 `ctx.tools`。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'asr.dart';

/// 本地音频文件转写工具。
class TranscribeAudioTool extends Tool {
  TranscribeAudioTool({
    required AsrService asr,
    this.provider,
    this.chunkBytes = 3200,
    this.language,
  }) : _asr = asr;

  final AsrService _asr;

  /// 指定 ASR provider；缺省走回退链。
  final String? provider;

  /// 每帧字节数（默认约 100ms @16k/16bit/单声道）。
  final int chunkBytes;

  /// 默认语言提示。
  final String? language;

  @override
  String get name => 'transcribe_audio';

  @override
  String get description => '把本地音频文件（wav / mp3 / ogg / pcm）转写为文本。';

  @override
  ToolRisk get riskLevel => ToolRisk.low;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('path', required: true, description: '音频文件路径'),
        ParamSpec.string('language', description: '语言提示，如 zh-CN'),
        ParamSpec.string('provider', description: '指定 ASR provider'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String path = context.str('path');
    final File file = File(path);
    if (!await file.exists()) {
      return ToolResult.failure(
        '音频文件不存在："$path"',
        error: ToolError('FILE_NOT_FOUND', 'no such file "$path"'),
      );
    }
    try {
      final String text = await _asr.transcribeText(
        _chunks(file),
        provider: context.string('provider') ?? provider,
        audioFormat: formatForPath(path),
        language: context.string('language') ?? language,
      );
      return ToolResult.success(
        text.isEmpty ? '（未识别到语音）' : text,
        value: <String, Object?>{'path': path, 'text': text},
      );
    } on AsrException catch (error) {
      return ToolResult.failure(
        '转写失败：${error.message}',
        error: ToolError('ASR_FAILED', error.message),
      );
    }
  }

  Stream<List<int>> _chunks(File file) async* {
    final RandomAccessFile handle = await file.open();
    try {
      while (true) {
        final List<int> chunk = await handle.read(chunkBytes);
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await handle.close();
    }
  }
}

/// 按扩展名推断音频参数（默认 PCM 16k 单声道）。
AsrAudioFormat formatForPath(String path) {
  final int dot = path.lastIndexOf('.');
  final String ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'wav' => const AsrAudioFormat(format: 'wav'),
    'mp3' => const AsrAudioFormat(format: 'mp3'),
    'ogg' => const AsrAudioFormat(format: 'ogg', codec: 'opus'),
    _ => const AsrAudioFormat(),
  };
}

/// 把 ASR 工具注册到 `ctx.tools`，返回已注册的工具。
///
/// [asr] 缺省取上下文的 `'asr'` 服务。
List<Tool> provideAsrTools(
  Context ctx, {
  AsrService? asr,
  String? provider,
  int chunkBytes = 3200,
}) {
  final AsrService service = asr ?? ctx.asr;
  final List<Tool> registered = <Tool>[
    TranscribeAudioTool(
      asr: service,
      provider: provider,
      chunkBytes: chunkBytes,
    ),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => ctx.tools.register(tool));
  }
  return registered;
}

/// 基于 ffmpeg 子进程的麦克风音频源（CLI / 桌面）。
///
/// 需要系统已安装 `ffmpeg`。采集为单声道 16kHz s16le PCM，直接从 stdout 流出。
/// Flutter 移动端不适用（无 ffmpeg 二进制），应改用平台录音插件实现
/// [AsrAudioSource]，把 PCM 字节交给同一套 ASR 能力。
library;

import 'dart:async';
import 'dart:io';

import 'asr_audio_source.dart';
import 'asr_types.dart';

/// ffmpeg 的采集输入后端（与平台相关）。
enum FfmpegInput {
  /// macOS：avfoundation，设备形如 `:0`（音频设备索引）。
  avfoundation,

  /// Linux：alsa，设备形如 `default`。
  alsa,

  /// Windows：dshow，设备形如 `audio=...`。
  dshow,

  /// 自定义：由 [FfmpegMicSource.extraInputArgs] 完整给出。
  custom,
}

/// 用 ffmpeg 从默认麦克风采集 PCM 的 [AsrAudioSource] 实现。
class FfmpegMicSource implements AsrAudioSource {
  FfmpegMicSource({
    this.executable = 'ffmpeg',
    FfmpegInput? input,
    this.device,
    this.extraInputArgs = const <String>[],
    this.format = const AsrAudioFormat(),
  }) : input = input ?? _defaultInput();

  /// ffmpeg 可执行文件（或绝对路径）。
  final String executable;

  /// 采集输入后端。
  final FfmpegInput input;

  /// 输入设备；缺省按后端取平台默认。
  final String? device;

  /// 追加在输入参数前的自定义参数（[FfmpegInput.custom] 时必填）。
  final List<String> extraInputArgs;

  @override
  final AsrAudioFormat format;

  Process? _process;
  StreamController<List<int>>? _controller;
  bool _started = false;

  @override
  Stream<List<int>> get bytes =>
      _controller?.stream ?? const Stream<List<int>>.empty();

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final StreamController<List<int>> controller =
        StreamController<List<int>>();
    _controller = controller;

    final Process process;
    try {
      process = await Process.start(executable, _args());
    } on ProcessException catch (error) {
      _started = false;
      throw AsrException('无法启动 ffmpeg（$executable）：${error.message}');
    }
    _process = process;
    process.stdout.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        if (!controller.isClosed) unawaited(controller.close());
      },
    );
    // 丢弃 stderr，避免管道写满阻塞 ffmpeg。
    unawaited(process.stderr.drain<void>());
  }

  @override
  Future<void> stop() async {
    final Process? process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigint);
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
    final StreamController<List<int>>? controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _started = false;
  }

  List<String> _args() {
    final List<String> inputArgs = switch (input) {
      FfmpegInput.avfoundation => <String>[
          '-f',
          'avfoundation',
          '-i',
          device ?? ':0'
        ],
      FfmpegInput.alsa => <String>['-f', 'alsa', '-i', device ?? 'default'],
      FfmpegInput.dshow => <String>[
          '-f',
          'dshow',
          '-i',
          device ?? 'audio=default'
        ],
      FfmpegInput.custom => const <String>[],
    };
    return <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      ...extraInputArgs,
      ...inputArgs,
      '-ac',
      '${format.channel}',
      '-ar',
      '${format.rate}',
      '-f',
      's16le',
      'pipe:1',
    ];
  }

  static FfmpegInput _defaultInput() {
    if (Platform.isMacOS) return FfmpegInput.avfoundation;
    if (Platform.isWindows) return FfmpegInput.dshow;
    return FfmpegInput.alsa;
  }
}

/// asr 插件：语音识别能力缝（`ctx.asr`）+ provider 回退链。
///
/// 服务键 `'asr'`。多个 [AsrProvider] 并排注册；[AsrService.start] 按注册顺序
/// 尝试，第一个成功建连即返回。默认 provider 是豆包/火山流式识别（见
/// [provideAsr] 与 `asr_doubao.dart`）。
///
/// 输入源无关：任何 `Stream<List<int>>`（麦克风、文件、网络流）都能经
/// [AsrService.transcribe] 灌入识别，这正是把 ASR 作为「能力」而非「功能」的
/// 关键——CLI 用 ffmpeg 采集，Flutter 用录音插件，两者只替换字节来源。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';

import 'asr_doubao.dart';
import 'asr_types.dart';

export 'asr_types.dart';

/// ASR 服务：provider 注册表 + 顺序回退。
class AsrService {
  AsrService();

  final List<AsrProvider> _providers = <AsrProvider>[];

  /// 已注册的 provider（按注册顺序）。
  List<AsrProvider> get providers => List<AsrProvider>.unmodifiable(_providers);

  /// 注册一个 provider。返回撤销函数（幂等）。
  Disposer register(AsrProvider provider) {
    _providers.add(provider);
    return () => _providers.remove(provider);
  }

  /// 查找 provider；未注册返回 `null`。
  AsrProvider? get(String name) {
    for (final AsrProvider provider in _providers) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// 开启一次流式会话：默认顺序回退；给定 [provider] 时只走该 provider。
  Future<AsrSession> start({
    String? provider,
    AsrAudioFormat? audio,
    String? language,
    List<String> hotwords = const <String>[],
  }) async {
    final List<AsrProvider> candidates =
        provider == null ? List<AsrProvider>.of(_providers) : <AsrProvider>[];
    if (provider != null) {
      final AsrProvider? found = get(provider);
      if (found == null) {
        throw AsrException('未注册的 ASR provider "$provider"');
      }
      candidates.add(found);
    }
    if (candidates.isEmpty) {
      throw const AsrException('没有可用的 ASR provider');
    }
    final List<String> errors = <String>[];
    for (final AsrProvider candidate in candidates) {
      try {
        return await candidate.start(
          audio: audio,
          language: language,
          hotwords: hotwords,
        );
      } catch (error) {
        errors.add('${candidate.name}: $error');
      }
    }
    throw AsrException('所有 ASR provider 都失败：${errors.join('；')}');
  }

  /// 把一路音频字节流交给 ASR，返回识别事件流（以 [AsrFinal] 收尾）。
  ///
  /// 源结束时自动请求最终结果；事件流结束后会话自动释放。源出错时关闭会话。
  Stream<AsrEvent> transcribe(
    Stream<List<int>> audio, {
    String? provider,
    AsrAudioFormat? audioFormat,
    String? language,
    List<String> hotwords = const <String>[],
  }) async* {
    final AsrSession session = await start(
      provider: provider,
      audio: audioFormat,
      language: language,
      hotwords: hotwords,
    );
    final StreamSubscription<List<int>> subscription = audio.listen(
      session.send,
      onError: (Object _) => session.close(),
      onDone: () => unawaited(_finish(session)),
      cancelOnError: false,
    );
    try {
      yield* session.events;
    } finally {
      await subscription.cancel();
      session.close();
    }
  }

  /// [transcribe] 的便捷版：仅返回最终文本。
  Future<String> transcribeText(
    Stream<List<int>> audio, {
    String? provider,
    AsrAudioFormat? audioFormat,
    String? language,
    List<String> hotwords = const <String>[],
  }) async {
    String text = '';
    await for (final AsrEvent event in transcribe(
      audio,
      provider: provider,
      audioFormat: audioFormat,
      language: language,
      hotwords: hotwords,
    )) {
      text = event.result.text;
    }
    return text;
  }
}

/// 请求最终结果；失败由 [AsrSession.events] 上报，这里只避免悬挂 Future。
Future<void> _finish(AsrSession session) async {
  try {
    await session.finish();
  } on AsrException {
    // 已通过 events 上报。
  }
}

/// `ctx.asr`：当前上下文可见的 ASR 服务。
extension AsrContext on Context {
  /// 取当前上下文可见的 [AsrService]（未提供时抛 [StateError]）。
  AsrService get asr => require<AsrService>('asr');
}

/// 将 [AsrService] 作为 `'asr'` 服务提供到上下文。
///
/// [providers] 显式给出时按序注册；否则新建服务时默认注册豆包/火山流式
/// provider。凭据来源优先级：`auth` 动态头回调 > 显式参数 > 环境变量
/// （见 [DoubaoStreamingAsrProvider]）。传入现成的 [asr] 且未给 [providers]
/// 时不追加默认 provider。
AsrService provideAsr(
  Context ctx, {
  AsrService? asr,
  List<AsrProvider>? providers,
  String? apiKey,
  String? appKey,
  String? accessKey,
  String? resourceId,
  String url = defaultDoubaoAsrUrl,
  DoubaoAuthHeaders? auth,
}) {
  final AsrService service = asr ?? AsrService();
  ctx.provide('asr', service);
  final List<AsrProvider> resolved = providers ??
      (asr != null
          ? const <AsrProvider>[]
          : <AsrProvider>[
              DoubaoStreamingAsrProvider(
                apiKey: apiKey,
                appKey: appKey,
                accessKey: accessKey,
                resourceId: resourceId,
                url: url,
                auth: auth,
              ),
            ]);
  for (final AsrProvider provider in resolved) {
    ctx.effect(() => service.register(provider));
  }
  return service;
}

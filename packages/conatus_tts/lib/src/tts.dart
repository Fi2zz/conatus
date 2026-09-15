/// tts 插件：语音合成能力缝（`ctx.tts`）+ provider 回退链。
///
/// 服务键 `'tts'`。多个 [TtsProvider] 并排注册；[TtsService.start] 按注册顺序
/// 尝试，第一个成功建连即返回。默认 provider 是豆包/火山语音合成（见
/// [provideTts] 与 `tts_doubao.dart`）。
///
/// 输出目标无关：合成音频写入任意 [TtsAudioSink]（扬声器、文件、网络），这正是把
/// TTS 作为「能力」而非「功能」的关键——宿主只替换音频输出去向。
library;

import 'package:conatus_core/conatus_core.dart';

import 'tts_audio_sink.dart';
import 'tts_doubao.dart';
import 'tts_types.dart';

export 'tts_audio_sink.dart';
export 'tts_types.dart';

/// TTS 服务：provider 注册表 + 顺序回退。
class TtsService {
  TtsService();

  final List<TtsProvider> _providers = <TtsProvider>[];

  /// 已注册的 provider（按注册顺序）。
  List<TtsProvider> get providers => List<TtsProvider>.unmodifiable(_providers);

  /// 注册一个 provider。返回撤销函数（幂等）。
  Disposer register(TtsProvider provider) {
    _providers.add(provider);
    return () => _providers.remove(provider);
  }

  /// 查找 provider；未注册返回 `null`。
  TtsProvider? get(String name) {
    for (final TtsProvider provider in _providers) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// 开启一次合成会话，音频写入 [sink]：默认顺序回退；给定 [provider] 时只走它。
  Future<TtsSession> start(
    TtsAudioSink sink, {
    String? provider,
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    final List<TtsProvider> candidates =
        provider == null ? List<TtsProvider>.of(_providers) : <TtsProvider>[];
    if (provider != null) {
      final TtsProvider? found = get(provider);
      if (found == null) {
        throw TtsException('未注册的 TTS provider "$provider"');
      }
      candidates.add(found);
    }
    if (candidates.isEmpty) {
      throw const TtsException('没有可用的 TTS provider');
    }
    final List<String> errors = <String>[];
    for (final TtsProvider candidate in candidates) {
      try {
        return await candidate.start(
          sink,
          voice: voice,
          format: format,
          speed: speed,
          volume: volume,
          pitch: pitch,
        );
      } catch (error) {
        errors.add('${candidate.name}: $error');
      }
    }
    throw TtsException('所有 TTS provider 都失败：${errors.join('；')}');
  }

  /// 合成 [text] 并写入 [sink]，等待音频全部到达。
  Future<void> speak(
    String text,
    TtsAudioSink sink, {
    String? provider,
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    final TtsSession session = await start(
      sink,
      provider: provider,
      voice: voice,
      format: format,
      speed: speed,
      volume: volume,
      pitch: pitch,
    );
    session.send(text);
    await session.finish();
  }

  /// [speak] 的便捷版：把合成音频收进内存返回。
  Future<List<int>> synthesize(
    String text, {
    String? provider,
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    final BytesAudioSink sink = BytesAudioSink();
    await speak(
      text,
      sink,
      provider: provider,
      voice: voice,
      format: format,
      speed: speed,
      volume: volume,
      pitch: pitch,
    );
    return sink.bytes;
  }
}

/// `ctx.tts`：当前上下文可见的 TTS 服务。
extension TtsContext on Context {
  /// 取当前上下文可见的 [TtsService]（未提供时抛 [StateError]）。
  TtsService get tts => require<TtsService>('tts');
}

/// 将 [TtsService] 作为 `'tts'` 服务提供到上下文。
///
/// [providers] 显式给出时按序注册；否则新建服务时默认注册豆包/火山语音合成
/// provider（凭据缺省读环境变量，见 [DoubaoHttpTtsProvider]）。传入现成的 [tts]
/// 且未给 [providers] 时不追加默认 provider。
TtsService provideTts(
  Context ctx, {
  TtsService? tts,
  List<TtsProvider>? providers,
  String? appId,
  String? accessToken,
  String? cluster,
  String? voice,
  String url = defaultDoubaoHttpTtsUrl,
}) {
  final TtsService service = tts ?? TtsService();
  ctx.provide('tts', service);
  final List<TtsProvider> resolved = providers ??
      (tts != null
          ? const <TtsProvider>[]
          : <TtsProvider>[
              DoubaoHttpTtsProvider(
                appId: appId,
                accessToken: accessToken,
                cluster: cluster,
                voice: voice,
                url: url,
              ),
            ]);
  for (final TtsProvider provider in resolved) {
    ctx.effect(() => service.register(provider));
  }
  return service;
}

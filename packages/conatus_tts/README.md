# conatus_tts

conatus 的 TTS（语音合成）能力缝。把「文本 → 音频字节」作为可插拔能力，音频
写到哪由宿主提供的 **音频输出接口** `TtsAudioSink` 决定：CLI / 桌面写本地播放器
或文件，Flutter 写平台音频播放插件。

## 组成

| 层 | 类型 | 作用 |
|----|------|------|
| 能力缝 | `TtsService` / `TtsProvider` | provider 注册表 + 顺序回退 |
| 词汇 | `TtsSession` / `TtsVoice` / `TtsAudioFormat` | 文本进、音频出的会话 |
| 输出接口 | `TtsAudioSink` | **音频输出去向**（宿主实现） |
| 内置实现 | `BytesAudioSink` / `StreamAudioSink` / `CallbackAudioSink` | 内存 / 流 / 回调 |
| provider | `DoubaoStreamingTtsProvider` | 豆包/火山 v3 WebSocket 单向流式合成 |

## 接线

```dart
import 'package:conatus/conatus.dart';
import 'package:conatus_tts/conatus_tts.dart';

// 提供 'tts' 服务：凭据缺省读环境变量
provideTts(app);
```

环境变量（二选一）：

```bash
export VOLC_TTS_API_KEY="新版控制台 API Key"

# 或旧版控制台
export VOLC_TTS_APP_KEY="App ID"
export VOLC_TTS_ACCESS_TOKEN="Access Token"

# 可选：资源 ID 与音色，需成对匹配
export VOLC_TTS_RESOURCE_ID="seed-tts-2.0"          # 默认
export VOLC_TTS_VOICE="zh_female_vv_uranus_bigtts"  # 默认
```

也可显式注入：

```dart
provideTts(app, apiKey: '...', voice: '...');
```

## 用法

能力层是「文本进、音频字节出」——音频去哪由 `TtsAudioSink` 决定：

```dart
// 1) 收进内存（保存文件 / 上传等）
final List<int> mp3 = await ctx.tts.synthesize('你好，世界');
File('out.mp3').writeAsBytesSync(mp3);

// 2) 边合成边消费（推给播放器）
final sink = StreamAudioSink();
final session = await ctx.tts.start(sink);
session.send('第一句。');
session.send('第二句。');
await session.finish();
await for (final chunk in sink.stream) { /* 写入播放器 */ }

// 3) 直接写自定义 sink
await ctx.tts.speak('你好', MyAudioSink());
```

## 自定义音频输出（宿主接入点）

```dart
class MyAudioSink implements TtsAudioSink {
  final player = MyPlayer();

  @override
  void write(List<int> bytes) => player.feed(bytes);

  @override
  Future<void> close() => player.flushAndClose();
}
```

Flutter 端即用播放插件实现 `TtsAudioSink`；框架保证 `write` 按序、`close` 恰好
一次（成功或失败都会调用）。

## 自定义 provider

实现 `TtsProvider` / `TtsSession`，即可接入其它合成服务；失败时抛
`TtsException`，回退链由 `TtsService` 编排：

```dart
provideTts(app, providers: <TtsProvider>[MyTtsProvider()]);
```

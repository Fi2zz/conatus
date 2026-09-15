# conatus_asr

conatus 的 ASR（语音识别）能力缝。把「一段音频字节 → 文本」作为可插拔能力，
与音频来源解耦：CLI 用 ffmpeg 采集麦克风，Flutter 端用录音插件，二者只替换
`Stream<List<int>>` 的来源。

## 组成

| 层 | 类型 | 作用 |
|----|------|------|
| 能力缝 | `AsrService` / `AsrProvider` | provider 注册表 + 顺序回退 |
| 词汇 | `AsrSession` / `AsrEvent` / `AsrResult` | 输入源无关的流式识别会话 |
| provider | `DoubaoStreamingAsrProvider` | 豆包/火山 SAUC 双向流式 WebSocket |
| 协议 | `buildAsrFrame` / `decodeAsrFrame` | SAUC 二进制帧编解码（可单测） |
| 音频源 | `AsrAudioSource` / `FfmpegMicSource` | 音频来源缝 + ffmpeg 麦克风实现 |
| 工具 | `TranscribeAudioTool` / `provideAsrTools` | `transcribe_audio` 文件转写 |

## 接线

```dart
import 'package:conatus/conatus.dart';
import 'package:conatus_asr/conatus_asr.dart';

// 提供 'asr' 服务：凭据缺省读环境变量
provideAsr(app);
// 注册 transcribe_audio 工具（文件转写）
provideAsrTools(app);
```

环境变量（二选一）：

```bash
export VOLC_ASR_API_KEY="新版控制台 API Key"

# 或旧版控制台
export VOLC_ASR_APP_KEY="App ID"
export VOLC_ASR_ACCESS_KEY="Access Token"

# 可选：资源 ID，默认 volc.bigasr.sauc.duration（模型 1.0 小时版）
export VOLC_ASR_RESOURCE_ID="volc.seedasr.sauc.duration"
```

也可显式注入（任意来源：配置文件、密钥管理、后端下发）：

```dart
provideAsr(app, apiKey: mySecretStore.asrKey);
```

### 动态签名 / 短时令牌

Flutter 端不宜内置长期密钥。用 `auth` 回调动态产出鉴权头（会与默认头合并、
同名覆盖），适合「向后端换取短时签名」或 HMAC 签名：

```dart
provideAsr(
  app,
  auth: () async {
    // 例：向后端换取短时令牌；也可在此计算 HMAC 签名头
    final token = await myBackend.issueAsrToken();
    return <String, String>{'X-Api-Key': token};
  },
);
```

优先级：`auth` 回调 > 显式参数 > 环境变量。仅提供 `auth` 时无需静态凭据。

## 用法

树代码里 ASR 只是「字节流进、事件流/文本出」——任何 `Stream<List<int>>` 都可以：

```dart
// 任意来源：文件、网络、内存……
final String text = await ctx.asr.transcribeText(
  audioBytes,                    // Stream<List<int>>，PCM s16le / wav / mp3 / ogg
  language: 'zh-CN',
);

// 需要增量（边说边出字）就订阅事件流
await for (final AsrEvent event in ctx.asr.transcribe(audioBytes)) {
  switch (event) {
    case AsrPartial(:final result):
      stdout.write('\r${result.text}');
    case AsrFinal(:final result):
      print('\n${result.text}');
  }
}
```

### 麦克风（CLI / 桌面，需系统装有 ffmpeg）

```dart
final source = FfmpegMicSource();       // 默认 16k / 16bit / 单声道 PCM
await for (final AsrEvent event in transcribeSource(ctx.asr, source)) {
  if (event is AsrFinal) print(event.result.text);
}
// 需要停止时调用 source.stop()
```

### Flutter

移动端没有 ffmpeg，实现自己的 `AsrAudioSource`（用平台录音插件产出 PCM），
其余代码不变：

```dart
class RecorderAudioSource implements AsrAudioSource {
  @override
  AsrAudioFormat get format => const AsrAudioFormat();
  @override
  Stream<List<int>> get bytes => myRecorder.pcmStream;
  @override
  Future<void> start() => myRecorder.start();
  @override
  Future<void> stop() => myRecorder.stop();
}
```

## 自定义 provider

实现 `AsrProvider` / `AsrSession`，即可接入其它流式识别服务；失败时抛
`AsrException`，回退链由 `AsrService` 编排：

```dart
provideAsr(app, providers: <AsrProvider>[MyAsrProvider()]);
```

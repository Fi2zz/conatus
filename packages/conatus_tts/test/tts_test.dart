import 'dart:async';
import 'dart:convert';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_tts/conatus_tts.dart';
import 'package:test/test.dart';

class _FakeSession implements TtsSession {
  _FakeSession(this.sink, this.name);

  final TtsAudioSink sink;
  final String name;
  final StringBuffer text = StringBuffer();
  bool finished = false;
  bool closed = false;

  @override
  void send(String chunk) => text.write(chunk);

  @override
  Future<void> finish() async {
    finished = true;
    sink.write(utf8.encode('audio:$name:${text.toString()}'));
    await sink.close();
  }

  @override
  void close() => closed = true;
}

class _FakeProvider implements TtsProvider {
  _FakeProvider(this.name, {this.fails = false});

  @override
  final String name;
  final bool fails;
  _FakeSession? last;
  TtsVoice? lastVoice;

  @override
  TtsAudioFormat get audioFormat => const TtsAudioFormat();

  @override
  TtsVoice? get defaultVoice => const TtsVoice('v');

  @override
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    if (fails) throw const TtsException('boom');
    lastVoice = voice;
    return last = _FakeSession(sink, name);
  }
}

/// 捕获建连头与出站帧、可注入入站帧的假 socket。
class _FakeTtsSocket implements TtsSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<List<int>> sent = <List<int>>[];
  Map<String, String>? headers;

  void emit(List<int> frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  void send(List<int> data) => sent.add(data);

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

void main() {
  group('TtsAudioSink 实现', () {
    test('BytesAudioSink 累积字节', () async {
      final BytesAudioSink sink = BytesAudioSink()
        ..write(<int>[1, 2])
        ..write(<int>[3]);
      await sink.close();
      expect(sink.bytes, <int>[1, 2, 3]);
    });

    test('StreamAudioSink 按序投递并关闭', () async {
      final StreamAudioSink sink = StreamAudioSink();
      final Future<List<List<int>>> collected = sink.stream.toList();
      sink
        ..write(<int>[1])
        ..write(<int>[2]);
      await sink.close();
      expect(await collected, <List<int>>[
        <int>[1],
        <int>[2],
      ]);
    });
  });

  group('TtsService', () {
    test('register / providers / get', () {
      final TtsService service = TtsService();
      final Disposer off = service.register(_FakeProvider('a'));

      expect(service.providers.map((TtsProvider p) => p.name), <String>['a']);
      expect(service.get('a'), isNotNull);
      expect(service.get('nope'), isNull);

      off();
      expect(service.providers, isEmpty);
    });

    test('顺序回退：首个成功即返回', () async {
      final TtsService service = TtsService()
        ..register(_FakeProvider('a', fails: true))
        ..register(_FakeProvider('b'));

      final TtsSession session = await service.start(BytesAudioSink());
      expect(session, isA<_FakeSession>());
    });

    test('指定 provider / 无 provider / 全失败', () async {
      final TtsService service = TtsService()
        ..register(_FakeProvider('a'))
        ..register(_FakeProvider('b', fails: true));

      expect(
        await service.start(BytesAudioSink(), provider: 'a'),
        isA<_FakeSession>(),
      );
      await expectLater(
        service.start(BytesAudioSink(), provider: 'b'),
        throwsA(isA<TtsException>()),
      );
      await expectLater(
        service.start(BytesAudioSink(), provider: 'z'),
        throwsA(isA<TtsException>()),
      );
      await expectLater(
        TtsService().start(BytesAudioSink()),
        throwsA(isA<TtsException>()),
      );
    });

    test('synthesize 收集音频字节', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final TtsService service = TtsService()..register(provider);

      final List<int> bytes = await service.synthesize('你好');

      expect(utf8.decode(bytes), 'audio:a:你好');
      expect(provider.last!.finished, isTrue);
    });

    test('speak 写入自定义 sink 并透传 voice', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final TtsService service = TtsService()..register(provider);
      final BytesAudioSink sink = BytesAudioSink();

      await service.speak('hi', sink, voice: const TtsVoice('custom'));

      expect(utf8.decode(sink.bytes), 'audio:a:hi');
      expect(provider.lastVoice!.id, 'custom');
    });
  });

  group('provideTts / ctx.tts', () {
    test('默认注册豆包 provider', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      final TtsService service = provideTts(ctx);
      expect(service.providers.single.name, 'doubao');
      expect(identical(ctx.tts, service), isTrue);
    });

    test('显式 providers 随上下文释放撤销', () {
      final Context ctx = Context.root();
      final TtsService service =
          provideTts(ctx, providers: <TtsProvider>[_FakeProvider('x')]);

      expect(service.providers.single.name, 'x');
      ctx.dispose();
      expect(service.providers, isEmpty);
    });
  });

  group('tts_protocol', () {
    test('请求帧为 full client request + gzip JSON', () {
      final List<int> bytes = buildTtsRequest(<String, Object?>{
        'req_params': <String, Object?>{'text': 'hi'},
      });
      final TtsFrame frame = decodeTtsFrame(bytes);
      expect(frame.messageType, ttsMsgFullClientRequest);
      expect(frame.compression, ttsCompressionGzip);
      expect(frame.payload, isNotEmpty);
      expect(utf8.decode(frame.payload), contains('"text":"hi"'));
    });

    test('音频帧解析 event / session_id / 负载', () {
      final List<int> bytes = buildTtsFrame(
        messageType: ttsMsgAudioOnlyServer,
        flag: ttsFlagWithEvent,
        serialization: ttsSerializationRaw,
        event: ttsEventResponse,
        sessionId: 'sess-1',
        payload: <int>[9, 8, 7],
      );
      final TtsFrame frame = decodeTtsFrame(bytes);
      expect(frame.isAudio, isTrue);
      expect(frame.event, ttsEventResponse);
      expect(frame.sessionId, 'sess-1');
      expect(frame.payload, <int>[9, 8, 7]);
    });
  });

  group('DoubaoStreamingTtsProvider', () {
    test('建连头正确，合成音频写入 sink', () async {
      final _FakeTtsSocket socket = _FakeTtsSocket();
      final DoubaoStreamingTtsProvider provider = DoubaoStreamingTtsProvider(
        apiKey: 'k',
        connector: (Uri url, Map<String, String> headers) async {
          socket.headers = headers;
          return socket;
        },
      );
      final BytesAudioSink sink = BytesAudioSink();
      final TtsSession session = await provider.start(sink);
      session.send('你好');

      final Future<void> done = session.finish();
      socket.emit(buildTtsFrame(
        messageType: ttsMsgAudioOnlyServer,
        flag: ttsFlagWithEvent,
        serialization: ttsSerializationRaw,
        event: ttsEventResponse,
        sessionId: 'sess',
        payload: <int>[1, 2, 3],
      ));
      socket.emit(buildTtsFrame(
        messageType: ttsMsgFullServerResponse,
        flag: ttsFlagWithEvent,
        event: ttsEventSessionFinished,
        sessionId: 'sess',
        payload: utf8.encode('{"status_code":20000000,"message":"ok"}'),
      ));
      await done;

      expect(socket.headers!['X-Api-Key'], 'k');
      expect(socket.headers!['X-Api-Resource-Id'], defaultDoubaoTtsResourceId);
      expect(sink.bytes, <int>[1, 2, 3]);

      final TtsFrame request = decodeTtsFrame(socket.sent.single);
      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(request.payload)) as Map<String, dynamic>;
      final Map<String, dynamic> params =
          body['req_params'] as Map<String, dynamic>;
      expect(params['text'], '你好');
      expect(params['speaker'], defaultDoubaoTtsVoice);
    });

    test('错误帧抛 TtsException', () async {
      final _FakeTtsSocket socket = _FakeTtsSocket();
      final DoubaoStreamingTtsProvider provider = DoubaoStreamingTtsProvider(
        apiKey: 'k',
        connector: (Uri url, Map<String, String> headers) async => socket,
      );
      final TtsSession session = await provider.start(BytesAudioSink());
      session.send('你好');

      final Future<void> done = session.finish();
      socket.emit(buildTtsFrame(
        messageType: ttsMsgError,
        flag: ttsFlagNoSeq,
        errorCode: 40000000,
        payload: utf8.encode('bad'),
      ));

      await expectLater(done, throwsA(isA<TtsException>()));
    });

    test('缺少凭据时 start 抛 TtsException', () async {
      final DoubaoStreamingTtsProvider provider = DoubaoStreamingTtsProvider(
        apiKey: '',
        appKey: '',
        accessToken: '',
        connector: (Uri url, Map<String, String> headers) async =>
            throw StateError('不应建连'),
      );

      await expectLater(
        provider.start(BytesAudioSink()),
        throwsA(isA<TtsException>()),
      );
    });
  });
}
